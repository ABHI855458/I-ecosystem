-- ============================================================================
-- my_ping_reply_reactions() — reactions on replies I SENT, independent of the
-- ping's own lifetime.
--
-- Reported twice (2026-10-04): "people aren't able to view the reactions for
-- their ping replies". The cause was not permissions — can_see_ping_target
-- already lets the replier see them — but WHERE they could be looked up:
-- every surface was built from ping_inbox(), which only returns live pings.
-- A ping now expires 6h after it was sent, so a reply older than that (and
-- the reactions on it) had nowhere left to appear, even though the reaction
-- and its notification still existed.
--
-- This returns my own replies from the last [p_days] days that have at least
-- one RealMoji reaction, newest reaction first, each with its reactors and
-- their selfies — the same shape ping_realmojis_for returns, plus enough of
-- the reply to show what was reacted to.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.my_ping_reply_reactions(p_days int DEFAULT 7)
 RETURNS TABLE(
   reply_id uuid,
   ping_id uuid,
   kind text,
   photo_url text,
   body text,
   other_name text,
   is_group boolean,
   reacted_at timestamptz,
   reactions jsonb
 )
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (SELECT public.current_user_id() AS uid)
  SELECT r.id,
         r.ping_id,
         r.kind::text,
         r.photo_url,
         r.body,
         -- Who the reply went to: the group, or the person who pinged me.
         COALESCE(g.name, NULLIF(btrim(u.name), ''), u.anon_name, 'Someone'),
         p.group_id IS NOT NULL,
         MAX(x.created_at),
         jsonb_agg(
           jsonb_build_object(
             'ping_reply_id', x.ping_reply_id,
             'ping_id', NULL,
             'user_id', x.user_id,
             'name', COALESCE(NULLIF(btrim(ru.name), ''), ru.anon_name, 'Someone'),
             'emoji_type', x.emoji_type::text,
             'image_url', (
               SELECT ur.image_url FROM public.user_realmojis ur
                WHERE ur.user_id = x.user_id
                  AND ur.emoji_type = x.emoji_type
                  AND ur.feed_scope::text = 'everyone'
                ORDER BY ur.created_at DESC LIMIT 1
             ),
             'is_mine', x.user_id = (SELECT uid FROM me)
           ) ORDER BY x.created_at DESC
         )
    FROM public.ping_realmoji_reactions x
    JOIN public.ping_replies r ON r.id = x.ping_reply_id
    JOIN public.pings p ON p.id = r.ping_id
    LEFT JOIN public.groups g ON g.id = p.group_id
    LEFT JOIN public.users u ON u.id = p.sender_id AND p.anonymous IS NOT TRUE
    LEFT JOIN public.users ru ON ru.id = x.user_id
   WHERE r.replier_id = (SELECT uid FROM me)
     AND r.deleted_at IS NULL
     AND x.created_at > now() - make_interval(days => GREATEST(p_days, 1))
   GROUP BY r.id, r.ping_id, r.kind, r.photo_url, r.body, g.name, u.name, u.anon_name, p.group_id
   ORDER BY MAX(x.created_at) DESC
   LIMIT 50;
$function$;

REVOKE ALL ON FUNCTION public.my_ping_reply_reactions(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_ping_reply_reactions(int) TO authenticated;

COMMIT;
