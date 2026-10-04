-- ============================================================================
-- RealMoji reactions in Ping (explicit request + choice, 2026-10-03): "make
-- the reactions in ping RealMoji reactions same as the friends feed, and
-- create a mechanism to see those reactions" — on any reply you open (photo
-- or text), on group wall answers, and on one-to-one pings. The quick heart
-- (ping_reply_reactions) STAYS; this is added alongside it.
--
-- Own table, not the feed's: post_realmoji_reactions carries a post XOR
-- group_post CHECK and five post-shaped triggers (community XP, anon
-- engagement score, reaction-given score, notify_realmoji_reaction, replace
-- prior) that all assume a post. Pointing ping rows at it would misfire
-- every one of them.
--
-- Same model as the feed otherwise: a reaction row stores only WHICH
-- emoji; the picture is the reactor's own saved selfie for that emoji in
-- user_realmojis (scope 'everyone', RealmojiService.kOneScope). So a ping
-- reaction looks exactly like a feed reaction.
--
-- Targets (exactly one per row):
--   ping_reply_id — a reply to one of my pings, or a group wall answer
--                   (wall answers ARE ping_replies rows).
--   ping_id       — a one-to-one ping someone sent me.
--
-- Who may react: the ping's sender (to a 1:1 reply), any member of the
-- group (to a wall answer), the receiver (to a 1:1 ping). Who may SEE:
-- those, plus the target's author — that is the "see who reacted" half.
-- ============================================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.ping_realmoji_reactions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ping_reply_id uuid REFERENCES public.ping_replies(id) ON DELETE CASCADE,
  ping_id       uuid REFERENCES public.pings(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  emoji_type    public.emoji_type_enum NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ping_realmoji_one_target
    CHECK ((ping_reply_id IS NOT NULL) <> (ping_id IS NOT NULL))
);

-- One RealMoji per person per target; reacting again REPLACES it (upsert).
CREATE UNIQUE INDEX IF NOT EXISTS ping_realmoji_reply_user_uniq
  ON public.ping_realmoji_reactions (ping_reply_id, user_id)
  WHERE ping_reply_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ping_realmoji_ping_user_uniq
  ON public.ping_realmoji_reactions (ping_id, user_id)
  WHERE ping_id IS NOT NULL;

-- ── Who may react / who may see ───────────────────────────────────────────

-- May the caller REACT to this target?
CREATE OR REPLACE FUNCTION public.can_react_ping_target(p_reply uuid, p_ping uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (SELECT public.current_user_id() AS uid)
  SELECT CASE
    WHEN p_reply IS NOT NULL THEN EXISTS (
      SELECT 1 FROM public.ping_replies r
        JOIN public.pings p ON p.id = r.ping_id, me
       WHERE r.id = p_reply
         AND r.replier_id <> me.uid
         AND (
           -- a 1:1 reply to MY ping
           (p.group_id IS NULL AND p.sender_id = me.uid)
           -- a group wall answer, and I'm in the group
           OR (p.group_id IS NOT NULL
               AND public.is_group_member(p.group_id, me.uid))
         )
    )
    WHEN p_ping IS NOT NULL THEN EXISTS (
      SELECT 1 FROM public.pings p, me
       WHERE p.id = p_ping AND p.receiver_id = me.uid
         AND p.sender_id <> me.uid
    )
    ELSE false
  END;
$function$;

-- May the caller SEE reactions on this target? Everyone who may react,
-- plus the target's own author.
CREATE OR REPLACE FUNCTION public.can_see_ping_target(p_reply uuid, p_ping uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (SELECT public.current_user_id() AS uid)
  SELECT public.can_react_ping_target(p_reply, p_ping)
      OR CASE
           WHEN p_reply IS NOT NULL THEN EXISTS (
             SELECT 1 FROM public.ping_replies r, me
              WHERE r.id = p_reply AND r.replier_id = me.uid)
           WHEN p_ping IS NOT NULL THEN EXISTS (
             SELECT 1 FROM public.pings p, me
              WHERE p.id = p_ping AND p.sender_id = me.uid)
           ELSE false
         END;
$function$;

REVOKE ALL ON FUNCTION public.can_react_ping_target(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_see_ping_target(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_react_ping_target(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_see_ping_target(uuid, uuid) TO authenticated;

ALTER TABLE public.ping_realmoji_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ping_realmoji_select ON public.ping_realmoji_reactions;
CREATE POLICY ping_realmoji_select ON public.ping_realmoji_reactions
  FOR SELECT TO authenticated
  USING (public.can_see_ping_target(ping_reply_id, ping_id));

DROP POLICY IF EXISTS ping_realmoji_insert ON public.ping_realmoji_reactions;
CREATE POLICY ping_realmoji_insert ON public.ping_realmoji_reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = public.current_user_id()
    AND public.can_react_ping_target(ping_reply_id, ping_id)
  );

DROP POLICY IF EXISTS ping_realmoji_update ON public.ping_realmoji_reactions;
CREATE POLICY ping_realmoji_update ON public.ping_realmoji_reactions
  FOR UPDATE TO authenticated
  USING (user_id = public.current_user_id())
  WITH CHECK (
    user_id = public.current_user_id()
    AND public.can_react_ping_target(ping_reply_id, ping_id)
  );

DROP POLICY IF EXISTS ping_realmoji_delete ON public.ping_realmoji_reactions;
CREATE POLICY ping_realmoji_delete ON public.ping_realmoji_reactions
  FOR DELETE TO authenticated
  USING (user_id = public.current_user_id());

REVOKE ALL ON public.ping_realmoji_reactions FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ping_realmoji_reactions TO authenticated;

-- ── Reading them back, with the selfie ────────────────────────────────────

-- Every reaction on the given targets the caller may see, each with the
-- reactor's name and their saved selfie for that emoji — one call serves a
-- single reply viewer or a whole page of cards.
CREATE OR REPLACE FUNCTION public.ping_realmojis_for(
  p_reply_ids uuid[] DEFAULT '{}',
  p_ping_ids  uuid[] DEFAULT '{}'
)
 RETURNS TABLE (
   ping_reply_id uuid,
   ping_id uuid,
   user_id uuid,
   name text,
   emoji_type text,
   image_url text,
   is_mine boolean,
   created_at timestamptz
 )
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT x.ping_reply_id, x.ping_id, x.user_id,
         COALESCE(NULLIF(btrim(u.name), ''), u.anon_name, 'Someone'),
         x.emoji_type::text,
         ur.image_url,
         x.user_id = public.current_user_id(),
         x.created_at
    FROM public.ping_realmoji_reactions x
    LEFT JOIN public.users u ON u.id = x.user_id
    LEFT JOIN LATERAL (
      SELECT ur.image_url FROM public.user_realmojis ur
       WHERE ur.user_id = x.user_id
         AND ur.emoji_type = x.emoji_type
         AND ur.feed_scope::text = 'everyone'
       ORDER BY ur.created_at DESC
       LIMIT 1
    ) ur ON true
   WHERE (x.ping_reply_id = ANY (COALESCE(p_reply_ids, '{}'))
          OR x.ping_id = ANY (COALESCE(p_ping_ids, '{}')))
     AND public.can_see_ping_target(x.ping_reply_id, x.ping_id)
   ORDER BY x.created_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.ping_realmojis_for(uuid[], uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ping_realmojis_for(uuid[], uuid[]) TO authenticated;

-- ── Tell the author ───────────────────────────────────────────────────────

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (
  type = ANY (ARRAY[
    'reaction','ping','branch_view','us_album_mutual','report_resolved',
    'report_filed','announcement','ping_answered','us_album_invite','comment',
    'moment_contribution','group_added','group_invite','group_post','group_dip',
    'community_post','friend_post','streak_risk_red','streak_risk_blue',
    'streak_milestone_blue','group_streak_ping','group_streak_risk',
    'group_streak_broken','level_up','level_progress','leaderboard_movement',
    'ping_unanswered','group_ping_waiting','group_ping_replied',
    'pinned_post_view','pinned_group_post_view','moment_new_post',
    'moment_reply_nudge','pinned_profile_view','rank_overtaken','rank_regained',
    'streak_rank_overtaken','start_streak_nudge','streak_standing',
    'window_prompt','break_live_count','midday_report','day_digest',
    'lifecycle_cooling','lifecycle_lapsed','lifecycle_dormant',
    'activation_nudge','graduation','ping_reply_liked','us_album_accepted',
    'group_profile_view','us_album_ended','daily_drop','weekly_recap',
    'ping_unreplied','group_message','duo_post',
    -- new
    'ping_realmoji'
  ])
);

CREATE OR REPLACE FUNCTION public.notify_ping_realmoji()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_author uuid; v_who text; v_what text; v_ping uuid;
BEGIN
  IF NEW.ping_reply_id IS NOT NULL THEN
    SELECT r.replier_id, r.ping_id INTO v_author, v_ping
      FROM public.ping_replies r WHERE r.id = NEW.ping_reply_id;
    v_what := 'your reply';
  ELSE
    SELECT p.sender_id, p.id INTO v_author, v_ping
      FROM public.pings p WHERE p.id = NEW.ping_id;
    v_what := 'your ping';
  END IF;
  IF v_author IS NULL OR v_author = NEW.user_id THEN RETURN NEW; END IF;

  SELECT COALESCE(NULLIF(btrim(u.name), ''), u.anon_name, 'Someone')
    INTO v_who FROM public.users u WHERE u.id = NEW.user_id;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (v_author, 'ping_realmoji', NEW.user_id, 'major',
          COALESCE(v_who, 'Someone') || ' reacted to ' || v_what,
          NULL,
          jsonb_build_object('screen', 'ping', 'ping_id', v_ping,
                             'ping_reply_id', NEW.ping_reply_id),
          'ping_realmoji:' || COALESCE(NEW.ping_reply_id, NEW.ping_id)::text
            || ':' || NEW.user_id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_ping_realmoji ON public.ping_realmoji_reactions;
CREATE TRIGGER trg_notify_ping_realmoji
  AFTER INSERT ON public.ping_realmoji_reactions
  FOR EACH ROW EXECUTE FUNCTION public.notify_ping_realmoji();

REVOKE ALL ON FUNCTION public.notify_ping_realmoji() FROM PUBLIC, anon, authenticated;

-- A reaction is person-to-person — push it now, like an answered ping.
CREATE OR REPLACE FUNCTION public.push_allowed(p_tier text, p_type text, p_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_type IN ('ping_answered', 'ping_reply_liked', 'duo_post',
                    'group_message', 'ping_realmoji') THEN TRUE
    WHEN p_tier = 'major'    THEN w <> 'quiet'
    WHEN p_tier = 'standard' THEN w IN ('wake_digest','pre_class','snack_peak','lunch_peak','day_end','evening','last_call')
    ELSE                          w IN ('wake_digest','snack_peak','lunch_peak')
  END
  FROM (SELECT public.notification_window(p_at) AS w) s;
$function$;

COMMIT;
