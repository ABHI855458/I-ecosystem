-- Ping had NO block enforcement anywhere — a blocked relationship did
-- nothing to sends, replies, or inbox visibility in either direction.
-- Verified live pre-fix: a blocked user could still insert a real `pings`
-- row targeting the person who blocked them.
--
-- Every other content surface (posts/comments/group_posts/reactions/
-- post_realmoji_reactions/community_posts) already gates on the ONE shared
-- `is_blocked_user(auth.uid(), target_users_id)` chokepoint via a
-- RESTRICTIVE policy — reused verbatim here rather than a parallel check,
-- so this can never drift from how blocking works everywhere else.
--
-- Scoped to person-to-person pings only (receiver_id IS NOT NULL). Group
-- pings (receiver_id NULL, group_id set) are untouched — that's a
-- different, all-or-nothing visibility model (is_group_member +
-- has_answered_thread) that was never part of what was tested here, and
-- blocking semantics inside a group thread deserve their own separate
-- pass rather than an incidental side effect of this fix.

-- 1. INSERT-time gate — a blocked relationship (either direction) can no
-- longer send a NEW 1:1 ping. RESTRICTIVE so it ANDs with the existing
-- permissive `pings_insert` policy rather than replacing it.
CREATE POLICY "pings_block_filter_insert" ON pings AS RESTRICTIVE FOR INSERT
WITH CHECK (
  receiver_id IS NULL
  OR NOT is_blocked_user(auth.uid(), receiver_id)
);

-- 2. SELECT-time gate — hides EXISTING 1:1 pings from view once a block
-- exists, not just future ones.
--
-- Checks BOTH sender_id and receiver_id against the viewer, not just
-- receiver_id: unlike the INSERT check above (where the inserter is always
-- the sender, by construction of pings_insert's own WITH CHECK), a SELECT
-- viewer can legitimately be EITHER party. Checking only receiver_id was
-- live-tested and found wrong: when the viewer IS the receiver,
-- is_blocked_user(auth.uid(), receiver_id) is a self-vs-self check (a
-- users.id that maps back to the caller's own auth.uid()) and is_blocked_user
-- can never find a row where someone has blocked themselves, so it silently
-- evaluated to "never blocked" — the exact case (a blocked receiver still
-- seeing the ping in their own inbox) this fix exists to close. Checking
-- both ids is safe either way: whichever one equals the viewer resolves to
-- a harmless always-false self-check, and the other one is the real
-- "am I blocked with the OTHER party" comparison.
CREATE POLICY "pings_block_filter_select" ON pings AS RESTRICTIVE FOR SELECT
USING (
  receiver_id IS NULL
  OR (
    NOT is_blocked_user(auth.uid(), sender_id)
    AND NOT is_blocked_user(auth.uid(), receiver_id)
  )
);

-- 3. Same two gates on ping_replies, checked against the PARENT ping's
-- other party (sender_id) since a reply's own row has no receiver_id of
-- its own — the replier is implicitly the ping's receiver
-- (ping_replies_insert already requires is_ping_receiver(ping_id)).
--
-- Routed through a SECURITY DEFINER helper rather than a plain inline
-- `SELECT ... FROM pings` — live-tested and found broken as a plain
-- subquery: it runs under the CALLER's own RLS view of `pings`, which
-- `pings_block_filter_select` above now also gates. Once a block exists,
-- the very ping row this check needs to read becomes invisible to the
-- blocked/blocking party, so an inline subquery found zero rows and the
-- check silently passed — exactly backwards. Every other cross-ping-into-
-- another-table check in this schema (is_ping_sender, is_ping_receiver,
-- can_see_ping_reply) already avoids this by being SECURITY DEFINER;
-- this fix follows that same established pattern instead of introducing
-- a second, RLS-visible way of reading `pings`.
CREATE OR REPLACE FUNCTION public.ping_reply_blocked(p_ping uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pings p
    WHERE p.id = p_ping
      AND p.receiver_id IS NOT NULL
      AND public.is_blocked_user(auth.uid(), p.sender_id)
  );
$$;

CREATE POLICY "ping_replies_block_filter_insert" ON ping_replies AS RESTRICTIVE FOR INSERT
WITH CHECK (
  NOT public.ping_reply_blocked(ping_id)
);

CREATE POLICY "ping_replies_block_filter_select" ON ping_replies AS RESTRICTIVE FOR SELECT
USING (
  NOT is_blocked_user(auth.uid(), replier_id)
  AND NOT public.ping_reply_blocked(ping_id)
);

-- 4. ping_inbox() — the RPC PingService.fetchToReply() actually calls, NOT
-- a raw table read. It's SECURITY DEFINER, which means every RESTRICTIVE
-- policy added above is INVISIBLE to it — RLS never runs for a
-- SECURITY DEFINER function's own queries, regardless of what policies
-- exist on the tables it touches. Live-verified as a real, separate gap:
-- send_ping already carries its own inline block check (marked "THE
-- FIX." in its body — added before this pass), but nothing analogous
-- existed on the READ side, so a ping from someone who has since blocked
-- you (or you blocked) kept surfacing in the "to reply" inbox forever,
-- untouched by every policy above. Same is_blocked_user(auth.uid(),
-- p.sender_id) check send_ping already uses, added to the WHERE clause
-- directly since a SECURITY DEFINER function must do this explicitly —
-- it can never inherit it from a table policy.
CREATE OR REPLACE FUNCTION public.ping_inbox()
RETURNS TABLE(ping_id uuid, thread_id uuid, kind text, prompt text, created_at timestamp without time zone, window_hours integer, status text, anonymous boolean, group_id uuid, group_name text, group_size integer, sender_id uuid, sender_name text, sender_avatar text, expires_at timestamp with time zone, photo_url text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  select
    p.id, p.thread_id, t.kind, p.prompt, p.created_at, p.window_hours,
    p.status, p.anonymous,
    p.group_id,
    g.name,
    (select count(*)::int from public.group_members gm where gm.group_id = p.group_id),
    case when p.anonymous then null else p.sender_id end,
    case when p.anonymous then t.anon_display_name else u.name end,
    case when p.anonymous then null else u.profile_photo_url end,
    p.expires_at,
    p.photo_url
  from public.pings p
  join public.ping_threads t on t.id = p.thread_id
  left join public.users u on u.id = p.sender_id
  left join public.groups g on g.id = p.group_id
  where p.receiver_id = public.current_user_id()
    and p.sender_id <> p.receiver_id
    and p.expires_at > now()
    and (p.group_id is not null or not public.is_blocked_user(auth.uid(), p.sender_id))
  order by p.created_at desc;
$$;
