-- Anon posts' SEEN dropdown shows every viewer's REAL name and photo
-- (explicit request, 2026-10-01). Other posts keep the masking from
-- 20260928090000 (pinned by name, everyone else "someone in <BRANCH>"), and
-- the profile section's my_post_viewers is untouched.
CREATE OR REPLACE FUNCTION public.post_viewers(p_post_id uuid, p_window_hours integer DEFAULT NULL::integer)
 RETURNS TABLE(user_id uuid, viewer_key text, username text, name text, avatar_url text, is_pinned boolean, viewed_at timestamp with time zone, branch text, anon_label text, anon_avatar_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid()),
  post as (
    select (p.visibility = 'anonymous') as is_anon
      from public.posts p where p.id = p_post_id
  ),
  v as (
    select pv.viewer_id, pv.created_at,
           exists (select 1 from public.pinned_people pp
                    where pp.user_id = (select id from me) and pp.pinned_user_id = pv.viewer_id) as pinned
      from public.post_views pv
     where pv.post_id = p_post_id
       and (select id from me) is not null
       and public.post_engagement_visible(p_post_id)
  ),
  r as (
    select v.*, (v.pinned or coalesce((select is_anon from post), false)) as named
      from v
  )
  select
    case when r.named then u.id end,
    case when r.named then null else public.viewer_key((select id from me), u.id) end,
    case when r.named then u.username end,
    case when r.named then u.name end,
    case when r.named then u.profile_photo_url end,
    r.pinned,
    r.created_at,
    case when r.named then null
         else upper((select db.branch from public.derive_branch(a.email) db)) end,
    case when r.named then null else public.viewer_anon_label(u.id) end,
    case when r.named then null else u.anon_photo_url end
  from r
  join public.users u on u.id = r.viewer_id
  left join auth.users a on a.id = u.auth_id
  where p_window_hours is null
     or r.created_at >= now() - make_interval(hours => p_window_hours)
     or r.pinned
  order by 6 desc, 7 desc;
$function$;
