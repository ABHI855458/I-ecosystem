-- ============================================================================
-- my_chat_list() — backs the Community tab's WhatsApp-style chat list
-- (explicit request, 2026-10-02/03: "in community make chat like thing ...
-- like WhatsApp ... for communities and as well groups ... same as priority
-- and normal chats").
--
-- One row per community I've joined and per group I'm in, with the newest
-- thing said there (preview text + time), so the list loads in one call
-- instead of N feed fetches. Unread state is client-side (last-opened per
-- chat), so nothing here writes.
--
--   kind          'community' | 'group'
--   last_text     newest community post / notice, or group post / ping
--   last_at       when that happened (null = nothing yet)
--   priority_at   community: newest PRIORITY notice (last 7 days);
--                 group: newest group ping still waiting on MY answer
--                 — the client puts a chat under PRIORITY when this is
--                 newer than the last time I opened it.
--   member_count  for the row subtitle
--
-- Privacy: author names are never returned for community posts (they can
-- be anonymous); a private group post contributes "📷 Photo" only; an
-- anonymous group ping shows its anon label, never the sender.
-- SECURITY DEFINER, scoped to the caller via auth.uid()/current_user_id().
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.my_chat_list()
 RETURNS TABLE (
   kind text,
   id uuid,
   name text,
   icon_url text,
   last_text text,
   last_at timestamptz,
   priority_at timestamptz,
   member_count integer
 )
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (
    SELECT auth.uid() AS auth_id, public.current_user_id() AS uid
  ),
  my_comms AS (
    SELECT c.id, c.name, c.icon_url
      FROM public.community_members m
      JOIN public.communities c ON c.id = m.community_id
      JOIN me ON m.user_id = me.auth_id
     WHERE c.deleted_at IS NULL
  ),
  comm_last AS (
    SELECT DISTINCT ON (x.community_id) x.community_id, x.txt, x.at
      FROM (
        SELECT p.community_id,
               COALESCE(NULLIF(btrim(p.body), ''), '📷 Photo') AS txt,
               p.created_at AS at
          FROM public.community_posts p
         WHERE p.deleted_at IS NULL
           AND p.community_id IN (SELECT id FROM my_comms)
           -- Same 48h window the board's feed shows (community_posts_feed
           -- p_since / CommunityFeedService._communityPostCutoff) — the
           -- list must never preview a post the chat won't show.
           AND p.created_at > now() - interval '48 hours'
        UNION ALL
        SELECT f.community_id,
               COALESCE(NULLIF(btrim(f.title), ''), NULLIF(btrim(f.body), ''), 'New notice'),
               f.created_at
          FROM public.community_feed_items f
         WHERE f.deleted_at IS NULL AND f.is_priority
           AND f.created_at > now() - interval '7 days'
           AND f.community_id IN (SELECT id FROM my_comms)
      ) x
     ORDER BY x.community_id, x.at DESC
  ),
  comm_prio AS (
    SELECT f.community_id, max(f.created_at) AS at
      FROM public.community_feed_items f
     WHERE f.deleted_at IS NULL AND f.is_priority
       AND f.created_at > now() - interval '7 days'
       AND f.community_id IN (SELECT id FROM my_comms)
     GROUP BY f.community_id
  ),
  comm_count AS (
    SELECT m.community_id, count(*)::int AS n
      FROM public.community_members m
     WHERE m.community_id IN (SELECT id FROM my_comms)
     GROUP BY m.community_id
  ),
  my_groups AS (
    SELECT g.id, g.name, g.icon_url
      FROM public.group_members gm
      JOIN public.groups g ON g.id = gm.group_id
      JOIN me ON gm.user_id = me.uid
  ),
  group_last AS (
    SELECT DISTINCT ON (x.group_id) x.group_id, x.txt, x.at
      FROM (
        SELECT gp.group_id,
               CASE WHEN gp.is_private THEN '📷 Photo'
                    ELSE COALESCE(NULLIF(btrim(gp.caption), ''), NULLIF(btrim(gp.note), ''), '📷 Photo')
               END AS txt,
               gp.created_at AS at
          FROM public.group_posts gp
         WHERE gp.deleted_at IS NULL
           AND gp.group_id IN (SELECT id FROM my_groups)
        UNION ALL
        SELECT t.group_id,
               COALESCE(
                 CASE WHEN t.anonymous THEN NULLIF(btrim(t.anon_display_name), '')
                      ELSE (SELECT COALESCE(NULLIF(btrim(u.name), ''), u.anon_name)
                              FROM public.users u WHERE u.id = t.sender_id)
                 END, 'Someone')
               || CASE WHEN NULLIF(btrim(t.prompt), '') IS NULL
                       THEN ' pinged the group'
                       ELSE ': ' || btrim(t.prompt) END,
               t.created_at AT TIME ZONE 'utc'
          FROM public.ping_threads t
         WHERE t.group_id IN (SELECT id FROM my_groups)
      ) x
     ORDER BY x.group_id, x.at DESC
  ),
  group_prio AS (
    SELECT p.group_id, max(p.created_at AT TIME ZONE 'utc') AS at
      FROM public.pings p, me
     WHERE p.receiver_id = me.uid
       AND p.group_id IN (SELECT id FROM my_groups)
       AND p.status = 'pending'
       AND p.expires_at > now()
       AND p.sender_id <> me.uid
     GROUP BY p.group_id
  ),
  group_count AS (
    SELECT gm.group_id, count(*)::int AS n
      FROM public.group_members gm
     WHERE gm.group_id IN (SELECT id FROM my_groups)
     GROUP BY gm.group_id
  )
  SELECT 'community'::text, c.id, c.name, c.icon_url, l.txt, l.at, pr.at, cc.n
    FROM my_comms c
    LEFT JOIN comm_last l ON l.community_id = c.id
    LEFT JOIN comm_prio pr ON pr.community_id = c.id
    LEFT JOIN comm_count cc ON cc.community_id = c.id
  UNION ALL
  SELECT 'group'::text, g.id, g.name, g.icon_url, l.txt, l.at, pr.at, gc.n
    FROM my_groups g
    LEFT JOIN group_last l ON l.group_id = g.id
    LEFT JOIN group_prio pr ON pr.group_id = g.id
    LEFT JOIN group_count gc ON gc.group_id = g.id;
$function$;

REVOKE ALL ON FUNCTION public.my_chat_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_chat_list() TO authenticated;

COMMIT;
