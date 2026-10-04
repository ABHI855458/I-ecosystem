-- ---------------------------------------------------------------------------
-- score_events.user_id pointed at the WRONG identity table.
--
-- The ledger was built for the legacy `profiles` keyspace (its dead
-- apply_score trigger wrote profiles.score), so its FK is
-- score_events_user_id_fkey -> profiles(id). Every score function added in
-- 20260907030000 passes a `users.id`, which is a different keyspace — so
-- log_score_event() raised 23503 and, because it's called inside
-- record_daily_open() and the two award triggers, took the whole write down
-- with it.
--
-- Caught live on device: the +2 daily-open never landed, users.last_open_at
-- stayed null. Reproduced directly:
--   ERROR 23503: Key (user_id)=(726dc111-…) is not present in table "profiles"
--
-- Repoint the FK at users(id), which is what every caller actually has.
-- The table has 0 rows, so there is nothing to migrate.
-- ---------------------------------------------------------------------------

alter table public.score_events
  drop constraint if exists score_events_user_id_fkey;

alter table public.score_events
  add constraint score_events_user_id_fkey
  foreign key (user_id) references public.users(id) on delete cascade;

-- Belt and braces: the ledger is an audit trail, not the score itself
-- (users.glow_score/ping_score are). A failure to LOG must never roll back
-- the score it was logging, or one bad row silently costs someone points.
create or replace function public.log_score_event(
  p_user uuid, p_type text, p_points integer
) returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  insert into public.score_events (user_id, event_type, points)
  values (p_user, p_type, p_points);
exception when others then
  -- Swallowed on purpose. See above.
  null;
end;
$$;
