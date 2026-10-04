-- ---------------------------------------------------------------------------
-- PING LIFECYCLE — a ping closes on a real schedule, and one person can only
-- have one open ping to another at a time.
--
-- Old rule: a ping expired `window_hours` (5) after it was SENT, full stop.
-- Two problems that produced live:
--   * an anonymous ping sent at 04:42 was gone by 09:42 — the recipient
--     opening the app that evening saw nothing, which read as "the anon ping
--     isn't received" even though ping_inbox() was returning the row
--     correctly (confirmed live).
--   * nothing stopped the same sender queueing 5 pings at the same person;
--     4 such rows are in the table right now, all pending, from one sender
--     to one receiver within minutes.
--
-- New rule, as specified:
--   * opened  -> closes 6h after it was opened  (pings.seen_at)
--   * unopened-> closes 24h after it was sent
--   * only when the current one has closed (or been replied to) may the same
--     sender ping that same person again.
--
-- expires_at is a GENERATED column so the two branches can never disagree
-- with whatever a client computes, and so the partial unique index below can
-- be expressed against real data rather than a moving now().
-- ---------------------------------------------------------------------------

-- Existing `expires_at` is a plain nullable column nothing maintains; replace
-- it with the generated rule. Dropping is safe: no policy or index uses it.
alter table public.pings drop column if exists expires_at;

alter table public.pings
  add column expires_at timestamptz
  generated always as (
    case
      when seen_at is not null then seen_at + interval '6 hours'
      else created_at + interval '24 hours'
    end
  ) stored;

comment on column public.pings.expires_at is
  'Generated: seen_at + 6h once opened, else created_at + 24h. A ping past '
  'this is closed — it leaves the sender''s UI and frees them to ping that '
  'person again.';

create index if not exists pings_open_pair_idx
  on public.pings (sender_id, receiver_id, expires_at)
  where status = 'pending' and receiver_id is not null;

-- ── One open ping per (sender, receiver) ───────────────────────────────────
-- Enforced in send_ping rather than as a constraint: "open" depends on now(),
-- which no unique index can express. Raising a named error lets the client
-- show the real reason instead of a generic failure.
create or replace function public.send_ping(
  p_receiver_id uuid,
  p_prompt text,
  p_anonymous boolean default false,
  p_window_hours integer default 5
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_me uuid;
  v_thread uuid;
  v_label text;
  v_open_until timestamptz;
begin
  v_me := public.current_user_id();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if p_receiver_id = v_me then raise exception 'Cannot ping yourself.'; end if;

  -- Already have a live ping sitting with this person? Wait for it to close.
  select max(expires_at) into v_open_until
    from public.pings
   where sender_id = v_me
     and receiver_id = p_receiver_id
     and status = 'pending'
     and expires_at > now();

  if v_open_until is not null then
    raise exception 'PING_ALREADY_OPEN:%',
      to_char(v_open_until at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  end if;

  if p_anonymous then
    v_label := public.gen_handle();
  end if;

  insert into public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours)
  values (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours)
  returning id into v_thread;

  insert into public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours)
  values (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours);

  update public.users set ping_score = ping_score + 25 where id = v_me;
  perform public.bump_daily_streak(v_me);

  return v_thread;
end;
$$;

-- ── Inbox / sent lists respect the new close rule ──────────────────────────
-- ping_inbox gains expires_at so the client stops computing expiry from
-- window_hours (which no longer describes when a ping closes) and drops rows
-- that have already closed.
-- Signature changes (adds expires_at), so it must be dropped first —
-- Postgres will not replace a function whose OUT-parameter row type differs.
drop function if exists public.ping_inbox();

create or replace function public.ping_inbox()
returns table (
  ping_id uuid, thread_id uuid, kind text, prompt text,
  created_at timestamp without time zone, window_hours integer, status text,
  anonymous boolean, group_id uuid, group_name text, group_size integer,
  sender_id uuid, sender_name text, sender_avatar text,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select
    p.id, p.thread_id, t.kind, p.prompt, p.created_at, p.window_hours,
    p.status, p.anonymous,
    p.group_id,
    g.name,
    (select count(*)::int from public.group_members gm where gm.group_id = p.group_id),
    case when p.anonymous then null else p.sender_id end,
    case when p.anonymous then t.anon_display_name else u.name end,
    case when p.anonymous then null else u.profile_photo_url end,
    p.expires_at
  from public.pings p
  join public.ping_threads t on t.id = p.thread_id
  left join public.users u on u.id = p.sender_id
  left join public.groups g on g.id = p.group_id
  where p.receiver_id = public.current_user_id()
    and p.sender_id <> p.receiver_id
    and p.expires_at > now()
  order by p.created_at desc;
$$;
