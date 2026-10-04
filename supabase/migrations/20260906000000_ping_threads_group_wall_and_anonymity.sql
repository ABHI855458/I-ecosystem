-- ============================================================================
-- PING — group threads (the Group Wall) + real anonymity.
--
-- Until now a "group ping" was N independent `pings` rows with nothing tying
-- them together (PingService.pingGroupMembers left `group_id` unset, per its
-- own doc comment) and the Group Wall UI in ping_page.dart (_groupWall et al)
-- was 100% hardcoded fixture data (kGroupWall/kWallGroup/kWallPrompt).
-- Anonymous pings did not write to the database at all — openPromptSheet
-- skipped the real send whenever `anon` was true.
--
-- CONFIRMED LIVE before writing this (not from the stale schema.sql):
--   pings 0 rows, ping_replies 0 rows.
--   pings.group_id FKs communities(id) ON DELETE SET NULL, referenced by
--     ZERO Dart code (grep found only two doc-comment mentions) — safe to
--     repoint at groups(id).
--   ping_groups / ping_group_members / anon_ping_threads(+participants,
--     messages) are vestigial (0 rows, keyed on the legacy `profiles`
--     table) — deliberately not built on.
--   users_select is `USING (true)` for every authenticated user, i.e.
--     users.anon_name is globally look-up-able. A ping's anonymous label is
--     therefore a freshly generated gen_handle() (same function this app
--     already uses for anon post comments, see post_thread_handles /
--     20260905030000_thread_handles_batch_rpc.sql) — NEVER a snapshot of
--     users.anon_name/anon_name_2, which would be trivially reversible via
--     that one policy regardless of anything else in this file.
--   notify_webhook() does not exist; no notify triggers are attached to
--     pings/ping_replies despite schema.sql's stale claim otherwise — out of
--     scope here, tracked as a separate gap.
--
-- All new timestamp columns are `timestamp` (no tz), matching every existing
-- column on pings/ping_replies, so lib/shared/time_ago.dart's
-- parsePostgresTimestamp keeps parsing them uniformly.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- ping_threads — ONE row per logical ping. A person ping has exactly one
-- child `pings` row; a group ping has one per recipient (plus the sender's
-- own row when the group ping is anonymous — see send_group_ping below).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ping_threads (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind              TEXT NOT NULL DEFAULT 'person',
  group_id          UUID REFERENCES public.groups(id) ON DELETE CASCADE,
  prompt            TEXT NOT NULL,
  anonymous         BOOLEAN NOT NULL DEFAULT false,
  -- A random gen_handle() output generated once at send time — e.g.
  -- "silent_owl42" — NOT derived from users.anon_name. See the header note:
  -- anon_name is world-readable via users_select, so anything traceable back
  -- to it is not actually anonymous.
  anon_display_name TEXT,
  window_hours      INT NOT NULL DEFAULT 3,
  created_at        TIMESTAMP NOT NULL DEFAULT now(),
  updated_at        TIMESTAMP NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE public.ping_threads
    ADD CONSTRAINT ping_threads_kind_check CHECK (kind IN ('person', 'group'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.ping_threads
    ADD CONSTRAINT ping_threads_group_required
      CHECK ((kind = 'group') = (group_id IS NOT NULL));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.ping_threads
    ADD CONSTRAINT ping_threads_anon_name_required
      CHECK (NOT anonymous OR anon_display_name IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS ping_threads_sender_created_idx
  ON public.ping_threads (sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ping_threads_group_created_idx
  ON public.ping_threads (group_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- pings — thread linkage + a denormalized `anonymous` copy so the SELECT
-- policy (below) is a single-row predicate rather than a join into
-- ping_threads, which has its own restrictive RLS and would silently
-- evaluate the join to nothing from inside another table's policy.
-- ---------------------------------------------------------------------------
ALTER TABLE public.pings
  ADD COLUMN IF NOT EXISTS thread_id UUID REFERENCES public.ping_threads(id) ON DELETE CASCADE;
ALTER TABLE public.pings
  ADD COLUMN IF NOT EXISTS anonymous BOOLEAN NOT NULL DEFAULT false;

-- Repoint group_id: communities(id) -> groups(id). Verified safe (see header
-- note: 0 live rows, 0 code references to pings.group_id).
ALTER TABLE public.pings DROP CONSTRAINT IF EXISTS pings_group_id_fkey;
DO $$ BEGIN
  ALTER TABLE public.pings
    ADD CONSTRAINT pings_group_id_fkey
      FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS pings_thread_idx ON public.pings (thread_id);
CREATE INDEX IF NOT EXISTS pings_group_idx ON public.pings (group_id);
-- enforce_ping_limit() (rewritten below) runs a per-sender 24h scan on every
-- INSERT; a large group fan-out is that many rows in one statement.
CREATE INDEX IF NOT EXISTS pings_sender_created_idx
  ON public.pings (sender_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- ping_reply_views — per-VIEWER reveal state. ping_replies.viewed/viewed_at
-- is single-valued and already means something specific: "the ORIGINAL
-- SENDER opened this reply", driving the 24h ping-back window
-- (ReceivedReplyRow.pingBackAvailable). A wall reply has N viewers, so the
-- wall's "$opened opened" counter needs its own per-viewer table rather than
-- overloading that column.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ping_reply_views (
  reply_id  UUID NOT NULL REFERENCES public.ping_replies(id) ON DELETE CASCADE,
  viewer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  viewed_at TIMESTAMP NOT NULL DEFAULT now(),
  PRIMARY KEY (reply_id, viewer_id)
);
ALTER TABLE public.ping_reply_views ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- SECURITY DEFINER helpers.
--
-- Two traps drive every one of these:
--  1. A policy on `pings` cannot subquery `pings` directly without infinite
--     recursion (same reason the existing is_group_member() helper exists
--     for `groups`).
--  2. RLS applies to tables referenced INSIDE another table's policy
--     expression. All three live ping_replies policies do
--     `EXISTS (SELECT 1 FROM pings WHERE ...)` — the moment pings_select
--     (below) hides an anonymous row from its receiver, that subquery goes
--     through the narrowed policy too, and a receiver could no longer read
--     back or insert their own reply to an anonymous ping. RLS failures
--     return EMPTY RESULTS, not errors, so this fails silently as "the
--     reply didn't save" rather than a visible permissions error — every
--     policy that needs to look inside `pings` goes through one of these
--     DEFINER helpers instead of a raw subquery.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.current_user_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public'
AS $$
  SELECT id FROM public.users WHERE auth_id = auth.uid() LIMIT 1
$$;

-- The reciprocity gate, in one place: has this user posted a reply against
-- their own ping row in this thread. This is what makes "post yours to see
-- the rest" a real server-side lock rather than a client-side illusion.
CREATE OR REPLACE FUNCTION public.has_answered_thread(p_thread UUID, p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.ping_replies r
    JOIN public.pings p ON p.id = r.ping_id
    WHERE p.thread_id = p_thread
      AND r.replier_id = p_user
      AND r.deleted_at IS NULL
  )
$$;

CREATE OR REPLACE FUNCTION public.is_ping_receiver(p_ping UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pings p
    WHERE p.id = p_ping AND p.receiver_id = public.current_user_id()
  )
$$;

CREATE OR REPLACE FUNCTION public.is_ping_sender(p_ping UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pings p
    WHERE p.id = p_ping AND p.sender_id = public.current_user_id()
  )
$$;

-- Full visibility rule for a reply, in one DEFINER hop: the ping's sender,
-- the reply's own author, or a group-wall peer who has themselves answered.
CREATE OR REPLACE FUNCTION public.can_see_ping_reply(p_ping UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.pings p
    WHERE p.id = p_ping
      AND (
        p.sender_id = public.current_user_id()
        OR p.receiver_id = public.current_user_id()
        OR (
          p.group_id IS NOT NULL
          AND public.is_group_member(p.group_id, public.current_user_id())
          AND public.has_answered_thread(p.thread_id, public.current_user_id())
        )
      )
  )
$$;

GRANT EXECUTE ON FUNCTION public.current_user_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_answered_thread(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_ping_receiver(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_ping_sender(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_see_ping_reply(UUID) TO authenticated;

-- ============================================================================
-- RLS
-- ============================================================================

ALTER TABLE public.ping_threads ENABLE ROW LEVEL SECURITY;

-- Only the sender may ever read a thread row directly. Recipients get the
-- prompt/window/label through ping_inbox() and get_group_wall(), which strip
-- sender_id for an anonymous thread. Deliberately NO insert/update/delete
-- policy: ping_threads is written exclusively by the SECURITY DEFINER
-- send_* RPCs below, so a client cannot forge a thread — in particular
-- cannot mint `anonymous = true` on one directly.
DROP POLICY IF EXISTS "ping_threads_select" ON public.ping_threads;
CREATE POLICY "ping_threads_select" ON public.ping_threads FOR SELECT USING (
  sender_id = public.current_user_id()
);

DROP POLICY IF EXISTS "pings_select" ON public.pings;
CREATE POLICY "pings_select" ON public.pings FOR SELECT USING (
  -- My own sent rows, anonymous or not: I already know who I am.
  sender_id = public.current_user_id()

  -- Addressed to me — but ONLY when not anonymous. An anonymous ping's row
  -- is unreachable from PostgREST by design; the receiver sees it through
  -- ping_inbox(), which returns sender_id AS NULL. This is what makes the
  -- anonymity real rather than a client-side courtesy.
  OR (receiver_id = public.current_user_id() AND anonymous = false)

  -- GROUP WALL. Any member of the ping's group may read every member's ping
  -- row for that group — but only after answering their own (reciprocity).
  -- Anonymous group threads are excluded here too and served only by
  -- get_group_wall(), same reasoning as the receiver branch above.
  OR (
    group_id IS NOT NULL
    AND anonymous = false
    AND public.is_group_member(group_id, public.current_user_id())
    AND public.has_answered_thread(thread_id, public.current_user_id())
  )
);

-- An UPDATE's WHERE clause also evaluates SELECT policies to find the row,
-- so without the `anonymous = false` guard here, the receiver of an
-- anonymous ping could never stamp seen_at through this policy — markSeen
-- moves to the mark_ping_seen() RPC below, which bypasses this via
-- SECURITY DEFINER.
DROP POLICY IF EXISTS "pings_update_receiver" ON public.pings;
CREATE POLICY "pings_update_receiver" ON public.pings FOR UPDATE USING (
  receiver_id = public.current_user_id() AND anonymous = false
);

-- ping_replies: all three of these subqueried `pings` directly before this
-- migration, which — per the header note on RLS-inside-policies — silently
-- breaks the moment pings_select excludes anonymous rows from their
-- receiver. Rerouted through the DEFINER helpers above.

DROP POLICY IF EXISTS "ping_replies_select" ON public.ping_replies;
CREATE POLICY "ping_replies_select" ON public.ping_replies FOR SELECT USING (
  deleted_at IS NULL AND public.can_see_ping_reply(ping_id)
);

-- Unchanged in MEANING — still "only the parent ping's receiver may insert a
-- reply", which already covers group pings correctly with no widening: a
-- fan-out gives every member their own `pings` row on which THEY are the
-- receiver, so each member is authorized to reply exactly once, to their own
-- row, and never anyone else's. New: also requires replier_id = the caller,
-- closing a gap where a receiver could previously insert a reply row
-- claiming to be someone else.
DROP POLICY IF EXISTS "ping_replies_insert" ON public.ping_replies;
CREATE POLICY "ping_replies_insert" ON public.ping_replies FOR INSERT WITH CHECK (
  public.is_ping_receiver(ping_id) AND replier_id = public.current_user_id()
);

DROP POLICY IF EXISTS "ping_replies_update_ping_sender" ON public.ping_replies;
CREATE POLICY "ping_replies_update_ping_sender" ON public.ping_replies FOR UPDATE USING (
  public.is_ping_sender(ping_id)
);

-- pings_select_moderator (is_admin_or_global_mod()) is left exactly as-is —
-- deliberately not narrowed. Permissive policies OR together, so moderators
-- keep full read access to `pings` including sender_id on anonymous rows.
-- That's the moderation/abuse-reporting path: anonymity holds against other
-- users, not against staff.

DROP POLICY IF EXISTS "ping_reply_views_select" ON public.ping_reply_views;
CREATE POLICY "ping_reply_views_select" ON public.ping_reply_views FOR SELECT USING (
  viewer_id = public.current_user_id()
);
DROP POLICY IF EXISTS "ping_reply_views_insert" ON public.ping_reply_views;
CREATE POLICY "ping_reply_views_insert" ON public.ping_reply_views FOR INSERT WITH CHECK (
  viewer_id = public.current_user_id()
  AND public.can_see_ping_reply((SELECT ping_id FROM public.ping_replies WHERE id = reply_id))
);

-- ============================================================================
-- enforce_ping_limit() — was a per-ROW count (5 rows/24h), so a group
-- fan-out to N members cost N of the sender's 5 daily pings, and any group
-- larger than 5 could never be pinged at all. Rewritten to count DISTINCT
-- LOGICAL pings (thread_id, falling back to id for any thread-less legacy
-- row) instead. The row currently being inserted is UNIONed into the count
-- rather than compared separately — the trigger is BEFORE INSERT ... FOR
-- EACH ROW, so row 2+ of the group fan-out's single multi-row INSERT
-- already sees rows 1..N-1 as committed-within-the-statement; this makes
-- that visibility fold all of them into one thread_id instead of
-- double-counting.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.enforce_ping_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE c INT;
BEGIN
  SELECT count(DISTINCT COALESCE(t.thread_id, t.id)) INTO c
  FROM (
    SELECT p.thread_id, p.id FROM public.pings p
     WHERE p.sender_id = NEW.sender_id
       AND p.created_at > now() - interval '24 hours'
    UNION ALL
    SELECT NEW.thread_id, NEW.id
  ) t;

  IF c > 5 THEN
    RAISE EXCEPTION 'Ping limit reached (5 per 24h).';
  END IF;
  RETURN NEW;
END;
$$;

-- Message text kept byte-identical: PingService.send's
-- e.toString().contains('Ping limit reached') -> PingLimitExceeded mapping
-- depends on it.

DROP TRIGGER IF EXISTS trg_enforce_ping_limit ON public.pings;
CREATE TRIGGER trg_enforce_ping_limit
  BEFORE INSERT ON public.pings FOR EACH ROW
  EXECUTE FUNCTION public.enforce_ping_limit();

-- Deliberately NOT adding a second limit trigger on ping_threads: it would
-- double-enforce, and a thread created for a fan-out that then fails on the
-- limit would permanently consume budget with no ping to show for it.
-- `pings` stays the single source of truth for the count.

-- ============================================================================
-- RPCs
-- ============================================================================

-- Person ping, replacing the direct `pings` insert in PingService.send.
-- Thread + ping row in one function so the limit trigger's abort rolls both
-- back together (no orphan thread left behind on failure).
CREATE OR REPLACE FUNCTION public.send_ping(
  p_receiver_id  UUID,
  p_prompt       TEXT,
  p_anonymous    BOOLEAN DEFAULT false,
  p_window_hours INT DEFAULT 3
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_me UUID;
  v_thread UUID;
  v_label TEXT;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF p_receiver_id = v_me THEN RAISE EXCEPTION 'Cannot ping yourself.'; END IF;

  IF p_anonymous THEN
    v_label := public.gen_handle();
  END IF;

  INSERT INTO public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours)
  VALUES (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours)
  RETURNING id INTO v_thread;

  -- enforce_ping_limit() fires on this insert and may abort the whole
  -- function, rolling the thread row back with it.
  INSERT INTO public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours)
  VALUES (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours);

  RETURN v_thread;
END;
$$;
GRANT EXECUTE ON FUNCTION public.send_ping(UUID, TEXT, BOOLEAN, INT) TO authenticated;

-- Group ping: creates the thread and fans out to every member in ONE
-- statement (deliberately not a loop, so enforce_ping_limit's row-visibility
-- trick above actually applies). Excludes the sender UNLESS the ping is
-- anonymous — for an anonymous group ping, a conspicuously absent member (no
-- "your turn" wall tile) would de-anonymise the asker by elimination in a
-- small group, so the asker gets a row and has to answer their own prompt
-- like everyone else.
CREATE OR REPLACE FUNCTION public.send_group_ping(
  p_group_id     UUID,
  p_prompt       TEXT,
  p_anonymous    BOOLEAN DEFAULT false,
  p_window_hours INT DEFAULT 3
) RETURNS TABLE(thread_id UUID, recipients INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_me UUID;
  v_thread UUID;
  v_label TEXT;
  v_n INT;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF NOT public.is_group_member(p_group_id, v_me) THEN
    RAISE EXCEPTION 'Not a member of that group.';
  END IF;

  IF p_anonymous THEN
    v_label := public.gen_handle();
  END IF;

  INSERT INTO public.ping_threads (sender_id, kind, group_id, prompt, anonymous, anon_display_name, window_hours)
  VALUES (v_me, 'group', p_group_id, p_prompt, p_anonymous, v_label, p_window_hours)
  RETURNING id INTO v_thread;

  INSERT INTO public.pings (thread_id, sender_id, receiver_id, group_id, prompt, anonymous, window_hours)
  SELECT v_thread, v_me, gm.user_id, p_group_id, p_prompt, p_anonymous, p_window_hours
    FROM public.group_members gm
   WHERE gm.group_id = p_group_id
     AND (p_anonymous OR gm.user_id <> v_me);

  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_n = 0 THEN
    DELETE FROM public.ping_threads WHERE id = v_thread;
    RETURN QUERY SELECT NULL::UUID, 0;
    RETURN;
  END IF;

  RETURN QUERY SELECT v_thread, v_n;
END;
$$;
GRANT EXECUTE ON FUNCTION public.send_group_ping(UUID, TEXT, BOOLEAN, INT) TO authenticated;

-- The masked To-Reply/Sent feed, replacing fetchToReply's raw
-- .from('pings').select(...users!pings_sender_id_fkey...). sender_id/
-- sender_name/sender_avatar are literal CASE expressions in the function
-- body for an anonymous row — there is no column the client can request to
-- defeat this, unlike a view. Deliberately does NOT filter status='pending'
-- — PingService/ping_page.dart filter that client-side — because the same
-- rows also back the wall's "who am I answering" lookups.
CREATE OR REPLACE FUNCTION public.ping_inbox()
RETURNS TABLE(
  ping_id       UUID,
  thread_id     UUID,
  kind          TEXT,
  prompt        TEXT,
  created_at    TIMESTAMP,
  window_hours  INT,
  status        TEXT,
  anonymous     BOOLEAN,
  group_id      UUID,
  group_name    TEXT,
  group_size    INT,
  sender_id     UUID,
  sender_name   TEXT,
  sender_avatar TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
  SELECT
    p.id, p.thread_id, t.kind, p.prompt, p.created_at, p.window_hours,
    p.status, p.anonymous,
    p.group_id,
    g.name,
    (SELECT count(*)::INT FROM public.group_members gm WHERE gm.group_id = p.group_id),
    CASE WHEN p.anonymous THEN NULL ELSE p.sender_id END,
    CASE WHEN p.anonymous THEN t.anon_display_name ELSE u.name END,
    CASE WHEN p.anonymous THEN NULL ELSE u.profile_photo_url END
  FROM public.pings p
  JOIN public.ping_threads t ON t.id = p.thread_id
  LEFT JOIN public.users u ON u.id = p.sender_id
  LEFT JOIN public.groups g ON g.id = p.group_id
  WHERE p.receiver_id = public.current_user_id()
    AND p.sender_id <> p.receiver_id
  ORDER BY p.created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.ping_inbox() TO authenticated;

-- One row per group member for a given thread: name/avatar/is_me/answered,
-- and — ONLY if the caller has answered their own ping in this thread, or is
-- the thread's sender — the reply payload. The lock is enforced INSIDE the
-- function: a locked caller still gets answered=true (drives "3 of 4
-- answered"), but every reply-payload column is NULL, so there's no way to
-- read the photos early by calling this RPC directly.
CREATE OR REPLACE FUNCTION public.get_group_wall(p_thread_id UUID)
RETURNS TABLE(
  member_id     UUID,
  member_name   TEXT,
  member_avatar TEXT,
  is_me         BOOLEAN,
  answered      BOOLEAN,
  reply_id      UUID,
  reply_kind    TEXT,
  reply_body    TEXT,
  reply_photo   TEXT,
  replied_at    TIMESTAMP,
  opened        BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_me UUID;
  v_group UUID;
  v_unlocked BOOLEAN;
BEGIN
  v_me := public.current_user_id();
  SELECT t.group_id INTO v_group FROM public.ping_threads t WHERE t.id = p_thread_id;
  IF v_group IS NULL OR NOT public.is_group_member(v_group, v_me) THEN
    RETURN;
  END IF;

  v_unlocked := public.has_answered_thread(p_thread_id, v_me);

  RETURN QUERY
  SELECT
    u.id, u.name, u.profile_photo_url,
    (u.id = v_me),
    (r.id IS NOT NULL),
    CASE WHEN v_unlocked THEN r.id END,
    CASE WHEN v_unlocked THEN r.kind END,
    CASE WHEN v_unlocked THEN r.body END,
    CASE WHEN v_unlocked THEN r.photo_url END,
    CASE WHEN v_unlocked THEN r.created_at END,
    COALESCE(v.viewer_id IS NOT NULL, false)
  FROM public.pings p
  JOIN public.users u ON u.id = p.receiver_id
  LEFT JOIN LATERAL (
    SELECT rr.* FROM public.ping_replies rr
     WHERE rr.ping_id = p.id AND rr.deleted_at IS NULL
     ORDER BY rr.created_at DESC LIMIT 1
  ) r ON true
  LEFT JOIN public.ping_reply_views v ON v.reply_id = r.id AND v.viewer_id = v_me
  WHERE p.thread_id = p_thread_id
  ORDER BY (u.id = v_me) DESC, r.created_at NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_group_wall(UUID) TO authenticated;

-- Active group threads the caller is a member of — lets ping_page.dart
-- render one wall card per thread instead of one hardcoded wall.
CREATE OR REPLACE FUNCTION public.my_group_walls()
RETURNS TABLE(
  thread_id    UUID,
  group_id     UUID,
  group_name   TEXT,
  prompt       TEXT,
  created_at   TIMESTAMP,
  window_hours INT,
  anonymous    BOOLEAN,
  asked_by     TEXT,
  my_ping_id   UUID,
  unlocked     BOOLEAN,
  answered     INT,
  total        INT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
  WITH me AS (SELECT public.current_user_id() AS id)
  SELECT DISTINCT ON (t.id)
    t.id, t.group_id, g.name, t.prompt, t.created_at, t.window_hours,
    t.anonymous,
    CASE WHEN t.anonymous THEN t.anon_display_name ELSE su.name END,
    (SELECT p.id FROM public.pings p, me WHERE p.thread_id = t.id AND p.receiver_id = me.id),
    public.has_answered_thread(t.id, (SELECT id FROM me)),
    (SELECT count(DISTINCT r.ping_id)::INT
       FROM public.ping_replies r JOIN public.pings p2 ON p2.id = r.ping_id
      WHERE p2.thread_id = t.id AND r.deleted_at IS NULL),
    (SELECT count(*)::INT FROM public.pings p3 WHERE p3.thread_id = t.id)
  FROM public.ping_threads t
  JOIN public.groups g ON g.id = t.group_id
  LEFT JOIN public.users su ON su.id = t.sender_id
  , me
  WHERE t.kind = 'group'
    AND public.is_group_member(t.group_id, me.id)
    AND t.created_at > now() - interval '7 days'
  ORDER BY t.id, t.created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.my_group_walls() TO authenticated;

-- Replaces PingService.markSeen's direct table update — required, not a
-- nicety: after pings_update_receiver above, the receiver of an ANONYMOUS
-- ping cannot see the row via a normal UPDATE...WHERE, so the direct update
-- would silently no-op for exactly the pings anonymity matters most for.
CREATE OR REPLACE FUNCTION public.mark_ping_seen(p_ping_id UUID)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
  UPDATE public.pings SET seen_at = now()
   WHERE id = p_ping_id AND receiver_id = public.current_user_id() AND seen_at IS NULL;
$$;
GRANT EXECUTE ON FUNCTION public.mark_ping_seen(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_wall_reply_opened(p_reply_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT public.can_see_ping_reply((SELECT ping_id FROM public.ping_replies WHERE id = p_reply_id)) THEN
    RETURN;
  END IF;
  INSERT INTO public.ping_reply_views (reply_id, viewer_id)
  VALUES (p_reply_id, public.current_user_id())
  ON CONFLICT (reply_id, viewer_id) DO NOTHING;
END;
$$;
GRANT EXECUTE ON FUNCTION public.mark_wall_reply_opened(UUID) TO authenticated;

-- A receiver replying to an anonymous ping never learns the sender's real
-- id, so they cannot call send_ping themselves — this resolves the sender
-- server-side. Gated to "I am the receiver AND I already replied within the
-- last 24h" (mirrors ReceivedReplyRow.pingBackAvailable's existing rule) so
-- it can't be used as a probe to test who sent something.
CREATE OR REPLACE FUNCTION public.ping_back_anonymous(
  p_ping_id   UUID,
  p_prompt    TEXT,
  p_anonymous BOOLEAN DEFAULT true
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_me UUID;
  v_target UUID;
BEGIN
  v_me := public.current_user_id();
  SELECT p.sender_id INTO v_target
    FROM public.pings p
   WHERE p.id = p_ping_id
     AND p.receiver_id = v_me
     AND EXISTS (
       SELECT 1 FROM public.ping_replies r
        WHERE r.ping_id = p.id AND r.replier_id = v_me
          AND r.deleted_at IS NULL
          AND r.created_at > now() - interval '24 hours'
     );
  IF v_target IS NULL THEN
    RAISE EXCEPTION 'Ping-back window closed.';
  END IF;
  RETURN public.send_ping(v_target, p_prompt, p_anonymous, 3);
END;
$$;
GRANT EXECUTE ON FUNCTION public.ping_back_anonymous(UUID, TEXT, BOOLEAN) TO authenticated;

-- Pings the author of an anonymous post without the caller ever learning
-- who that is. Powers the anon-feed's existing (currently inert) ping
-- button — see lib/features/home/anon_feed_v2/anon_feed_screen.dart and
-- lib/features/home/anonymous_tab.dart.
CREATE OR REPLACE FUNCTION public.ping_post_author(
  p_post_id   UUID,
  p_prompt    TEXT,
  p_anonymous BOOLEAN DEFAULT true
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_target UUID;
BEGIN
  SELECT p.user_id INTO v_target FROM public.posts p
   WHERE p.id = p_post_id AND p.deleted_at IS NULL;
  IF v_target IS NULL THEN
    RAISE EXCEPTION 'Post not found.';
  END IF;
  RETURN public.send_ping(v_target, p_prompt, p_anonymous, 3);
END;
$$;
GRANT EXECUTE ON FUNCTION public.ping_post_author(UUID, TEXT, BOOLEAN) TO authenticated;
