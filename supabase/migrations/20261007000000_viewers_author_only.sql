-- ============================================================================
-- Nobody sees the watchlist of someone else's post (explicit request,
-- 2026-10-07: "remove the presence pill and the seen pill from the friends
-- feed ... seen only in their own profile, only for their own posts, no pill
-- can see the watchlist of other people's posts except anon posting").
--
-- Regular posts already were owner-only (post_viewers, post_presence_people's
-- posts branch). GROUP posts were not: group_post_viewers and the group branch
-- of post_presence_people let EVERY member of the group read who had opened a
-- post. Both are now limited to the post's author, enforced here so a patched
-- client can't read what the UI no longer shows. Anonymous posts keep their
-- open seen list (post_viewers' own anon branch) as asked.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.group_post_viewers(p_group_post_id uuid)
 RETURNS TABLE(user_id uuid, viewer_key text, username text, name text, avatar_url text, is_pinned boolean, viewed_at timestamp with time zone, branch text, anon_label text, anon_avatar_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid()),
  v as (
    select gpv.viewer_id, gpv.created_at,
           exists (select 1 from public.pinned_people pp
                    where pp.user_id = (select id from me) and pp.pinned_user_id = gpv.viewer_id) as pinned
      from public.group_post_views gpv
      join public.group_posts gp on gp.id = gpv.group_post_id
     where gpv.group_post_id = p_group_post_id
       -- the post's AUTHOR only (2026-10-07: no one sees the watchlist of
       -- someone else's post) — was: any member of the group
       and gp.user_id = (select id from me)
  )
  select
    case when v.pinned then u.id end,
    case when v.pinned then null else public.viewer_key((select id from me), u.id) end,
    case when v.pinned then u.username end,
    case when v.pinned then u.name end,
    case when v.pinned then u.profile_photo_url end,
    v.pinned,
    v.created_at,
    case when v.pinned then null
         else upper((select db.branch from public.derive_branch(a.email) db)) end,
    case when v.pinned then null else public.viewer_anon_label(u.id) end,
    case when v.pinned then null else u.anon_photo_url end
  from v
  join public.users u on u.id = v.viewer_id
  left join auth.users a on a.id = u.auth_id
  order by 6 desc, 7 desc;
$function$;

CREATE OR REPLACE FUNCTION public.post_presence_people(p_post_id uuid DEFAULT NULL::uuid, p_group_post_id uuid DEFAULT NULL::uuid, p_since timestamp with time zone DEFAULT (now() - '03:00:00'::interval))
 RETURNS TABLE(user_id uuid, viewer_key text, name text, avatar_url text, is_pinned boolean, last_seen_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid()),
  allowed as (
    select (
      (p_post_id is not null and exists (
         select 1 from public.posts p
          where p.id = p_post_id and p.deleted_at is null
            -- owners only: the poster, or their Duo partner
            and (select id from me) in (p.user_id, p.partner_user_id)
            and public.post_engagement_visible(p_post_id)))
      or
      (p_group_post_id is not null and exists (
         select 1 from public.group_posts gp
          where gp.id = p_group_post_id
            -- author only (was: any group member)
            and gp.user_id = (select id from me)))
    ) and (select id from me) is not null as ok
  ),
  live as (
    select ps.user_id as uid, ps.last_seen_at as at
      from public.post_presence ps
     where (select ok from allowed)
       and ps.user_id <> (select id from me)
       and ((p_post_id is not null and ps.post_id = p_post_id)
         or (p_group_post_id is not null and ps.group_post_id = p_group_post_id))
  ),
  opened as (
    select pv.viewer_id as uid, pv.created_at as at
      from public.post_views pv
     where p_post_id is not null and pv.post_id = p_post_id
       and (select ok from allowed) and pv.viewer_id <> (select id from me)
    union all
    select gv.viewer_id, gv.created_at
      from public.group_post_views gv
     where p_group_post_id is not null and gv.group_post_id = p_group_post_id
       and (select ok from allowed) and gv.viewer_id <> (select id from me)
  ),
  pinned_ids as (
    select pp.pinned_user_id as uid from public.pinned_people pp
     where pp.user_id = (select id from me)
  ),
  merged as (
    -- one row per person: their latest live heartbeat, else their latest
    -- open within the window; pinned people keep a live row at any age.
    select uid, max(at) as at from (
      select uid, at from live
       where at >= p_since or uid in (select uid from pinned_ids)
      union all
      select uid, at from opened where at >= p_since
    ) x
    group by uid
  )
  select u.id,
         public.viewer_key((select id from me), u.id),
         coalesce(nullif(u.username, ''), u.name),
         u.profile_photo_url,
         (m.uid in (select uid from pinned_ids)),
         m.at
    from merged m
    join public.users u on u.id = m.uid
   where not public.is_blocked_user(auth.uid(), u.id)
   order by 5 desc, 6 desc;
$function$;

COMMIT;
