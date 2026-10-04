-- A Dip can be posted to SEVERAL communities at once (camera → Next → pick
-- any number). It stays ONE posts row: posts.community_id holds the first
-- pick, the rest are post_audiences rows (audience_kind 'community').
-- That extra tagging:
--   * counts toward each extra community's streak (no extra score points,
--     so ticking every community can't farm XP), and
--   * shows the Dip to each of those communities' moderators in the
--     dashboard feed.

create or replace function public.bump_extra_community_streak()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_post record;
  d  date;
  wk date := public.current_week_start();
begin
  if new.audience_kind is distinct from 'community' or new.community_id is null then
    return new;
  end if;
  select p.user_id, p.visibility, p.community_id, p.created_at into v_post
    from public.posts p where p.id = new.post_id;
  if v_post.user_id is null or v_post.visibility <> 'anonymous'
     or v_post.community_id is not distinct from new.community_id then
    return new;
  end if;
  d := (v_post.created_at at time zone 'Asia/Kolkata')::date;

  insert into public.community_streaks as cs (
    community_id, user_id, current_streak, longest_streak, last_post_on,
    xp, week_xp, week_start_on, updated_at)
  values (new.community_id, v_post.user_id, 1, 1, d, 10, 10, wk, now())
  on conflict (community_id, user_id) do update set
    current_streak = case
      when cs.last_post_on = d then cs.current_streak
      when cs.last_post_on = d - 1 then cs.current_streak + 1
      else 1 end,
    longest_streak = greatest(cs.longest_streak, case
      when cs.last_post_on = d then cs.current_streak
      when cs.last_post_on = d - 1 then cs.current_streak + 1
      else 1 end),
    last_post_on = d,
    xp = cs.xp + case when cs.last_post_on = d then 0 else 10 end,
    week_xp = case when cs.week_start_on = wk
                   then cs.week_xp + case when cs.last_post_on = d then 0 else 10 end
                   else 10 end,
    week_start_on = wk,
    updated_at = now();
  return new;
end $$;

drop trigger if exists post_audiences_bump_community_streak on public.post_audiences;
create trigger post_audiences_bump_community_streak
  after insert on public.post_audiences
  for each row execute function public.bump_extra_community_streak();

CREATE OR REPLACE FUNCTION public.dashboard_feed(p_scope text DEFAULT 'all'::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, user_id uuid, author_name text, author_avatar text, is_anonymous boolean, anon_name text, content text, image_url text, visibility text, post_type text, prompt text, community_id uuid, community_name text, comment_count integer, reaction_count integer, view_count integer, created_at timestamp without time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_scoped uuid;   -- non-null => a community moderator, limited to this one
BEGIN
  IF public.is_admin_or_global_mod() THEN
    v_scoped := NULL;
  ELSIF public.current_moderator_role() = 'community_moderator' THEN
    v_scoped := public.current_moderator_community_id();
    IF v_scoped IS NULL THEN
      RAISE EXCEPTION 'no community assigned';
    END IF;
  ELSE
    RAISE EXCEPTION 'not authorised';
  END IF;

  RETURN QUERY
  SELECT p.id,
         CASE WHEN p.visibility = 'anonymous' THEN NULL::uuid ELSE p.user_id END,
         CASE WHEN p.visibility = 'anonymous' THEN NULL::text ELSE u.name END,
         CASE WHEN p.visibility = 'anonymous' THEN NULL::text ELSE u.profile_photo_url END,
         (p.visibility = 'anonymous'),
         CASE WHEN p.visibility = 'anonymous'
              THEN COALESCE(NULLIF(btrim(u.anon_name),''),'anonymous') END,
         p.content, p.image_url, p.visibility, p.post_type, p.prompt,
         p.community_id, c.name,
         (SELECT COUNT(*)::int FROM comments cm WHERE cm.post_id = p.id AND cm.deleted_at IS NULL),
         (SELECT COUNT(*)::int FROM post_realmoji_reactions r WHERE r.post_id = p.id),
         COALESCE(p.view_count,0),
         p.created_at
    FROM posts p
    JOIN users u ON u.id = p.user_id
    LEFT JOIN communities c ON c.id = p.community_id
   WHERE p.deleted_at IS NULL
     AND p.post_type IS DISTINCT FROM 'memory'
     -- Moderators see every live post (the app's Dip feed resurfaces older
     -- Dips, so a 48h window hid posts students can still see). Moments
     -- still end at 24h, same as in the app.
     AND (p.post_type IS DISTINCT FROM 'moment'
          OR p.created_at > (now() AT TIME ZONE 'utc') - interval '24 hours')
     AND (v_scoped IS NULL OR p.community_id = v_scoped
          OR EXISTS (SELECT 1 FROM post_audiences pa
                      WHERE pa.post_id = p.id AND pa.audience_kind = 'community'
                        AND pa.community_id = v_scoped))
     AND (p_scope = 'all'
       OR (p_scope = 'anon'     AND p.visibility = 'anonymous')
       OR (p_scope = 'friends'  AND p.visibility = 'friends')
       OR (p_scope = 'everyone' AND p.visibility = 'everyone')
       OR (p_scope = 'moment'   AND p.post_type  = 'moment')
       OR (p_scope = 'us'       AND p.post_type  = 'us'))
   ORDER BY p.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END;
$function$
;
