-- ============================================================================
-- Group chat v2 (explicit request, 2026-10-03):
--  * "+" photos — group_messages.photo_urls (up to 6). A message is text,
--    photos, or both; the body check now allows an empty body when photos
--    are attached. Files live in the existing public `group-photos` bucket
--    under <group>/chat/<user>/... (same model as group posts).
--  * "let group chat go off after 48 hrs" — messages older than 48h are
--    invisible everywhere (RLS SELECT, group_messages_page, my_chat_list
--    preview) the moment they cross the line, and an hourly pg_cron job
--    deletes the rows for good.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

ALTER TABLE public.group_messages
  ADD COLUMN IF NOT EXISTS photo_urls text[] NOT NULL DEFAULT '{}';
ALTER TABLE public.group_messages ALTER COLUMN body SET DEFAULT '';

ALTER TABLE public.group_messages DROP CONSTRAINT IF EXISTS group_messages_body_check;
ALTER TABLE public.group_messages ADD CONSTRAINT group_messages_body_check CHECK (
  char_length(body) <= 1000
  AND cardinality(photo_urls) <= 6
  AND (char_length(btrim(body)) >= 1 OR cardinality(photo_urls) >= 1)
);

GRANT INSERT (group_id, sender_id, body, photo_urls) ON public.group_messages TO authenticated;

DROP POLICY IF EXISTS group_messages_select_member ON public.group_messages;
CREATE POLICY group_messages_select_member ON public.group_messages
  FOR SELECT TO authenticated
  USING (
    public.is_group_member(group_id, public.current_user_id())
    AND created_at > now() - interval '48 hours'
  );

DROP FUNCTION IF EXISTS public.group_messages_page(uuid, timestamptz, integer);
CREATE FUNCTION public.group_messages_page(
  p_group uuid,
  p_before timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 50
)
 RETURNS TABLE (
   id uuid,
   sender_id uuid,
   sender_name text,
   sender_avatar text,
   body text,
   photo_urls text[],
   created_at timestamptz,
   is_mine boolean
 )
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (SELECT public.current_user_id() AS uid)
  SELECT m.id, m.sender_id,
         COALESCE(NULLIF(btrim(u.name), ''), u.anon_name, 'Member'),
         u.profile_photo_url,
         m.body, m.photo_urls, m.created_at,
         m.sender_id = me.uid
    FROM public.group_messages m
    JOIN me ON public.is_group_member(p_group, me.uid)
    LEFT JOIN public.users u ON u.id = m.sender_id
   WHERE m.group_id = p_group
     AND m.deleted_at IS NULL
     AND m.created_at > now() - interval '48 hours'
     AND (p_before IS NULL OR m.created_at < p_before)
   ORDER BY m.created_at DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
$function$;

REVOKE ALL ON FUNCTION public.group_messages_page(uuid, timestamptz, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_messages_page(uuid, timestamptz, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.my_chat_list()
 RETURNS TABLE (
   kind text,
   id uuid,
   name text,
   icon_url text,
   last_text text,
   last_at timestamptz,
   priority_at timestamptz,
   member_count integer,
   member_avatars text[]
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
        UNION ALL
        SELECT gm.group_id,
               COALESCE(NULLIF(btrim(u.name), ''), u.anon_name, 'Someone')
               || ': ' || COALESCE(NULLIF(btrim(gm.body), ''), '📷 Photo'),
               gm.created_at
          FROM public.group_messages gm
          LEFT JOIN public.users u ON u.id = gm.sender_id
         WHERE gm.deleted_at IS NULL
           AND gm.created_at > now() - interval '48 hours'
           AND gm.group_id IN (SELECT id FROM my_groups)
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
  ),
  -- Up to 3 member photos (earliest joined first) — a group with no DP of
  -- its own shows these stacked, the same way the Ping page draws it.
  group_faces AS (
    SELECT x.group_id, array_agg(x.url ORDER BY x.joined_at) AS urls
      FROM (
        SELECT gm.group_id, u.profile_photo_url AS url, gm.joined_at,
               row_number() OVER (PARTITION BY gm.group_id ORDER BY gm.joined_at) AS rn
          FROM public.group_members gm
          JOIN public.users u ON u.id = gm.user_id
         WHERE gm.group_id IN (SELECT id FROM my_groups)
           AND NULLIF(btrim(u.profile_photo_url), '') IS NOT NULL
      ) x
     WHERE x.rn <= 3
     GROUP BY x.group_id
  )
  SELECT 'community'::text, c.id, c.name, c.icon_url, l.txt, l.at, pr.at, cc.n, NULL::text[]
    FROM my_comms c
    LEFT JOIN comm_last l ON l.community_id = c.id
    LEFT JOIN comm_prio pr ON pr.community_id = c.id
    LEFT JOIN comm_count cc ON cc.community_id = c.id
  UNION ALL
  -- Groups carry NO priority (explicit request, 2026-10-03: "group chat
  -- shall not have priority ... communities shall have priority").
  SELECT 'group'::text, g.id, g.name, g.icon_url, l.txt, l.at, NULL::timestamptz, gc.n, gf.urls
    FROM my_groups g
    LEFT JOIN group_last l ON l.group_id = g.id
    LEFT JOIN group_prio pr ON pr.group_id = g.id
    LEFT JOIN group_count gc ON gc.group_id = g.id
    LEFT JOIN group_faces gf ON gf.group_id = g.id;
$function$;

REVOKE ALL ON FUNCTION public.my_chat_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_chat_list() TO authenticated;


-- Hourly purge: rows past 48h are already invisible; this removes them.
SELECT cron.unschedule('purge-group-messages')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-group-messages');
SELECT cron.schedule(
  'purge-group-messages',
  '23 * * * *',
  $$DELETE FROM public.group_messages WHERE created_at < now() - interval '48 hours'$$
);

COMMIT;
