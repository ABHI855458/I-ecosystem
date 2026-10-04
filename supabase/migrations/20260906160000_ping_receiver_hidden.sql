-- ---------------------------------------------------------------------------
-- pings.receiver_hidden — "I pinged this person, and I am not allowed to know
-- who they are."
--
-- Pinging from the anon feed goes through ping_post_author(), which resolves
-- the anonymous post's author server-side precisely so the client never
-- learns their identity. But PingService.fetchSent then read the recipient
-- back through `users!pings_receiver_id_fkey(name, profile_photo_url)` and
-- rendered their REAL name in the Sent list — handing back the identity the
-- RPC exists to withhold. Reported directly: "when pinged anonymously to
-- people from anon, in sent it shall [show] the anon name of the pinged
-- person, not the real name."
--
-- Why a new column instead of reusing `anonymous`: that flag means "the
-- SENDER is hidden from the receiver", which is a different question and is
-- also true for anonymous pings to people you picked BY NAME (ping_page's
-- openPromptSheet(anon: true, targetId: ...)). Masking on `anonymous` would
-- blank out recipients you deliberately chose. This flag is set in exactly
-- one place — the post-author path — so it says what it means.
--
-- Existing rows are left false. Nothing can reconstruct which historical
-- pings came from ping_post_author, and the Sent list only shows the last
-- 48h (PingService.sentVisibleWindow), so the backlog ages out on its own.
-- ---------------------------------------------------------------------------

alter table public.pings
  add column if not exists receiver_hidden boolean not null default false;

comment on column public.pings.receiver_hidden is
  'True when the sender must not be shown the recipient''s real identity — '
  'set by ping_post_author() for pings aimed at an anonymous post''s author.';

create or replace function public.ping_post_author(
  p_post_id uuid,
  p_prompt text,
  p_anonymous boolean default true,
  p_window_hours integer default 5
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_target uuid;
  v_thread uuid;
begin
  select p.user_id into v_target
    from public.posts p
   where p.id = p_post_id and p.deleted_at is null;
  if v_target is null then
    raise exception 'Post not found.';
  end if;

  v_thread := public.send_ping(v_target, p_prompt, p_anonymous, p_window_hours);

  -- send_ping returns the THREAD id, and a person ping fans out to exactly
  -- one pings row under it, so this flags the row it just wrote.
  update public.pings
     set receiver_hidden = true
   where thread_id = v_thread;

  return v_thread;
end;
$function$;
