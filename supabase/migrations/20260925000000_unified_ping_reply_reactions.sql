-- UNIFIED PING REPLY REACTIONS — 1:1 and group walls on one model.
--
-- WHY THIS REPLACES ping_replies.liked_by_sender
-- The 1:1 heart (20260924000000) stored a single boolean, which works there
-- because exactly one person may ever react: the ping's sender. Group walls
-- cannot use that. sendGroupPing writes ONE `pings` row per member, all
-- sharing a thread_id, and pings.sender_id is the SAME initiator on every
-- one of those rows — so "only pings.sender_id may react" would let only the
-- group's initiator react to anyone, while every other member who answered
-- and can see the whole wall could not react at all.
--
-- Product decision: on a group wall, ANYONE who has answered that thread may
-- heart another member's tile, never their own; tiles show a reaction COUNT.
-- Several reactors per reply means a per-reactor row, not a boolean.
--
-- The 1:1 heart migrates onto this same table so there is one mechanism
-- app-wide rather than two that drift apart.

-- ---------------------------------------------------------------------------
-- 1. The table. Shape deliberately mirrors ping_reply_views(reply_id,
--    viewer_id, viewed_at) — the per-person join table this codebase already
--    uses for wall replies. PK doubles as the uniqueness constraint and the
--    reply_id lookup index get_group_wall's LATERAL count needs.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ping_reply_reactions (
  reply_id   uuid NOT NULL REFERENCES public.ping_replies(id) ON DELETE CASCADE,
  reactor_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (reply_id, reactor_id)
);

ALTER TABLE public.ping_reply_reactions ENABLE ROW LEVEL SECURITY;

-- SELECT is deliberately NARROW: your own reaction rows only, matching
-- ping_reply_views_select's own shape.
--
-- ANONYMITY: a permissive "can_see_ping_reply(...)" policy here would be an
-- outright de-anonymization bug. On an ANONYMOUS 1:1 ping the sender is
-- hidden from the receiver — but the sender is also the only person who can
-- react, so a reaction row's reactor_id IS the hidden sender's user id. Let
-- the receiver read that row and the mask comes off. Counts therefore never
-- come from a direct client read of this table; both read paths below are
-- SECURITY DEFINER and return an aggregate count + a bool, never an identity.
DROP POLICY IF EXISTS ping_reply_reactions_select ON public.ping_reply_reactions;
CREATE POLICY ping_reply_reactions_select ON public.ping_reply_reactions
  FOR SELECT USING (reactor_id = public.current_user_id());

-- No INSERT/UPDATE/DELETE policy at all: every write goes through the
-- SECURITY DEFINER RPC below, same trust model toggle_ping_reply_like used.

-- ---------------------------------------------------------------------------
-- 2. Backfill BEFORE the old column is dropped. sender_id is the correct
--    historical reactor: under the old rule only the ping's sender could
--    like, so every liked_by_sender = true row was that sender's doing.
-- ---------------------------------------------------------------------------
INSERT INTO public.ping_reply_reactions (reply_id, reactor_id)
SELECT r.id, p.sender_id
FROM public.ping_replies r
JOIN public.pings p ON p.id = r.ping_id
WHERE r.liked_by_sender = true
  AND p.sender_id IS NOT NULL
ON CONFLICT (reply_id, reactor_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3. The unified toggle. Replaces toggle_ping_reply_like — DROP first, not
--    CREATE OR REPLACE, because the return type changes from boolean to a
--    TABLE and Postgres rejects that ("cannot change return type of existing
--    function"; hit for real twice already on score_leaderboard/ping_inbox).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.toggle_ping_reply_like(uuid);

CREATE OR REPLACE FUNCTION public.toggle_ping_reply_reaction(p_reply_id uuid)
RETURNS TABLE(liked boolean, reaction_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me       uuid;
  v_sender   uuid;
  v_replier  uuid;
  v_ping_id  uuid;
  v_group    uuid;
  v_thread   uuid;
  v_existed  boolean;
BEGIN
  SELECT id INTO v_me FROM public.users WHERE auth_id = auth.uid();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  SELECT p.sender_id, r.replier_id, r.ping_id, p.group_id, p.thread_id
    INTO v_sender, v_replier, v_ping_id, v_group, v_thread
  FROM public.ping_replies r
  JOIN public.pings p ON p.id = r.ping_id
  WHERE r.id = p_reply_id AND r.deleted_at IS NULL;

  IF v_ping_id IS NULL THEN
    RAISE EXCEPTION 'reply not found';
  END IF;

  -- Branch on group_id, NOT thread_id. Verified on live data: all 53 1:1
  -- pings ALSO carry a thread_id, so thread_id does not discriminate the two
  -- shapes at all — group_id does (53 NULL vs 32 NOT NULL, no anomalies).
  IF v_group IS NULL THEN
    -- 1:1 — unchanged rule: only the ping's sender may react.
    IF v_sender IS DISTINCT FROM v_me THEN
      RAISE EXCEPTION 'only the ping sender can react to this reply';
    END IF;
  ELSE
    -- Group wall — anyone who has ANSWERED this thread may react, because
    -- answering is exactly what unlocks the wall (see get_group_wall's own
    -- v_unlocked gate). Reacting to your own tile is not a thing.
    --
    -- Checked against r.replier_id, not p.receiver_id: "my own tile" means
    -- the reply I wrote. Those coincide today for answered rows, but
    -- replier_id is the one that stays correct if they ever diverge.
    IF v_replier IS NOT DISTINCT FROM v_me THEN
      RAISE EXCEPTION 'cannot react to your own reply';
    END IF;
    IF NOT public.has_answered_thread(v_thread, v_me) THEN
      RAISE EXCEPTION 'answer this wall before reacting to it';
    END IF;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.ping_reply_reactions
     WHERE reply_id = p_reply_id AND reactor_id = v_me
  ) INTO v_existed;

  IF v_existed THEN
    DELETE FROM public.ping_reply_reactions
     WHERE reply_id = p_reply_id AND reactor_id = v_me;
  ELSE
    INSERT INTO public.ping_reply_reactions (reply_id, reactor_id)
    VALUES (p_reply_id, v_me)
    ON CONFLICT (reply_id, reactor_id) DO NOTHING;

    -- dedupe_key now carries the REACTOR. The old key was
    -- 'ping_reply_liked:<reply_id>' with no reactor in it, so on a group wall
    -- the 2nd..Nth person to react would have been silently swallowed by the
    -- ON CONFLICT DO NOTHING below and never notified anyone.
    IF v_replier IS DISTINCT FROM v_me THEN
      INSERT INTO public.notifications
        (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
      VALUES (v_replier, 'ping_reply_liked', v_me, 'minor',
              'Your photo got a ❤️', NULL,
              jsonb_build_object('screen','ping_reveal','ping_id', v_ping_id, 'ping_reply_id', p_reply_id),
              'ping_reply_liked:' || p_reply_id::text || ':' || v_me::text)
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    END IF;
  END IF;

  RETURN QUERY
  SELECT (NOT v_existed),
         (SELECT count(*)::int FROM public.ping_reply_reactions WHERE reply_id = p_reply_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.toggle_ping_reply_reaction(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. get_group_wall gains reaction_count + my_reaction. Body reproduced from
--    the LIVE pg_get_functiondef (this project's migration ledger is known to
--    drift from the real DB), with ONLY the reaction LATERAL + two output
--    columns added. DROP first — same return-type rule as above.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_group_wall(uuid);

CREATE OR REPLACE FUNCTION public.get_group_wall(p_thread_id uuid)
RETURNS TABLE(member_id uuid, member_name text, member_avatar text, is_me boolean, answered boolean, reply_id uuid, reply_kind text, reply_body text, reply_photo text, reply_selfie text, replied_at timestamp without time zone, opened boolean, reaction_count integer, my_reaction boolean)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me UUID;
  v_group UUID;
  v_sender UUID;
  v_unlocked BOOLEAN;
BEGIN
  v_me := public.current_user_id();
  SELECT t.group_id, t.sender_id INTO v_group, v_sender
    FROM public.ping_threads t WHERE t.id = p_thread_id;
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
    CASE WHEN v_unlocked THEN r.selfie_url END,
    CASE WHEN v_unlocked THEN r.created_at END,
    COALESCE(v.viewer_id IS NOT NULL, false),
    -- Gated exactly like every other reply field: a locked viewer learns
    -- nothing, not even how many hearts a tile has.
    CASE WHEN v_unlocked THEN COALESCE(rx.c, 0) ELSE 0 END,
    CASE WHEN v_unlocked THEN COALESCE(rx.mine, false) ELSE false END
  FROM public.pings p
  JOIN public.users u ON u.id = p.receiver_id
  LEFT JOIN LATERAL (
    SELECT rr.* FROM public.ping_replies rr
     WHERE rr.ping_id = p.id AND rr.deleted_at IS NULL
     ORDER BY rr.created_at DESC LIMIT 1
  ) r ON true
  LEFT JOIN public.ping_reply_views v ON v.reply_id = r.id AND v.viewer_id = v_me
  -- Aggregate only: a count and a bool. Never a reactor identity, which is
  -- what keeps this safe to hand to every member of the wall.
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS c, bool_or(x.reactor_id = v_me) AS mine
    FROM public.ping_reply_reactions x
    WHERE x.reply_id = r.id
  ) rx ON true
  WHERE p.thread_id = p_thread_id
  ORDER BY (u.id = v_me) DESC, r.created_at NULLS LAST;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 5. The old column, last — after the backfill above and after neither
--    function references it any more.
-- ---------------------------------------------------------------------------
ALTER TABLE public.ping_replies DROP COLUMN IF EXISTS liked_by_sender;
