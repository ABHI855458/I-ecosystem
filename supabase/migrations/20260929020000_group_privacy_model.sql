-- Group privacy model, by product request:
--   * Every group is INVITE-ONLY. "Public" never meant "anyone can join":
--     the self_join_public_group policy that let a public group be joined
--     unilaterally is dropped. Invites and member-shared QR join codes
--     (join_group_by_code) remain the ways in.
--   * A PUBLIC group's profile shows all of its (non-private) posts to
--     anyone who visits it — no per-viewer audience filter. This is the
--     profile only: the Friends feed keeps its existing rules, so a public
--     group's posts are not pushed into everyone's feed.
--   * A group post can be marked PRIVATE: then only the group's members see
--     it (their feed + the group profile). Never shown to non-members — not
--     via public-group visits, audience shares, community teasers or cards.

alter table public.group_posts
  add column if not exists is_private boolean not null default false;

-- ── invite-only ──────────────────────────────────────────────────────────
drop policy if exists self_join_public_group on public.group_members;

-- ── public group = visible profile ───────────────────────────────────────
create or replace function public.group_is_public(p_group uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.groups g
                  where g.id = p_group and g.visibility = 'public');
$$;
revoke all on function public.group_is_public(uuid) from public, anon;
grant execute on function public.group_is_public(uuid) to authenticated;

-- The group row itself (name, banner, icon) and its member list must be
-- readable for the profile to render for a visitor.
drop policy if exists groups_select_public on public.groups;
create policy groups_select_public on public.groups for select to authenticated
  using (visibility = 'public');

drop policy if exists group_members_select_public on public.group_members;
create policy group_members_select_public on public.group_members for select to authenticated
  using (public.group_is_public(group_id));

-- ── private posts: members only, everywhere ──────────────────────────────
create or replace function public.group_post_feed_access(p_group_post uuid)
returns text
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select case
    when public.is_group_member(gp.group_id, public.current_user_id()) then 'member'
    when gp.is_private then null
    when public.group_post_audience_admits(gp.id, gp.user_id)
      or public.is_public_group_in_my_community(gp.group_id) then 'open'
    when g.community_id is not null
      and coalesce(g.visibility, 'private') <> 'public'
      and public.is_community_member(g.community_id, auth.uid()) then 'locked'
    else null end
  from public.group_posts gp
  join public.groups g on g.id = gp.group_id
  where gp.id = p_group_post and gp.deleted_at is null
    and not public.is_blocked_user(auth.uid(), gp.user_id);
$function$;

drop policy if exists group_posts_select_public_community on public.group_posts;
create policy group_posts_select_public_community on public.group_posts for select
  using (deleted_at is null and not is_private and public.is_public_group_in_my_community(group_id));

drop policy if exists group_posts_select_shared_audience on public.group_posts;
create policy group_posts_select_shared_audience on public.group_posts for select
  using (deleted_at is null and not is_private and public.group_post_audience_admits(id, user_id));

-- ── the group profile for a non-member ───────────────────────────────────
create or replace function public.group_profile_posts_for_viewer(p_group_id uuid, p_via_user uuid default null::uuid)
returns table(id uuid, group_id uuid, user_id uuid, photo_url text, photo_urls text[],
              photo_url_secondary text, inset_on_right boolean, caption text, note text,
              place text, taken_at timestamptz, created_at timestamptz, aspect_ratio text,
              users jsonb, locked boolean)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with v as (
    select gp.*,
           public.group_post_feed_access(gp.id) as access,
           public.group_is_public(gp.group_id) as pub
      from public.group_posts gp
     where gp.group_id = p_group_id
       and gp.deleted_at is null
       and not gp.is_private
       and not public.is_blocked_user(auth.uid(), gp.user_id)
  ),
  shown as (
    select v.*,
           -- A public group shows everything in full; otherwise the old
           -- rule (first photo only for a 'locked' community teaser).
           (not v.pub and v.access = 'locked') as is_locked
      from v
     where v.pub
        or (v.access in ('open', 'locked')
            and (v.access = 'locked'
                 or public.is_public_group_in_my_community(v.group_id)
                 or (p_via_user is not null
                     and public.group_post_shared_via_admits(v.id, p_via_user))))
  )
  select s.id, s.group_id, s.user_id,
         case when s.is_locked then coalesce(s.photo_urls[1], s.photo_url) else s.photo_url end,
         case when s.is_locked
              then array_fill(coalesce(s.photo_urls[1], s.photo_url),
                              array[greatest(coalesce(array_length(s.photo_urls, 1), 0), 1)])
              else s.photo_urls end,
         case when s.is_locked then null else s.photo_url_secondary end,
         s.inset_on_right,
         s.caption, s.note, s.place, s.taken_at, s.created_at, s.aspect_ratio,
         jsonb_build_object('name', u.name, 'profile_photo_url', u.profile_photo_url),
         s.is_locked
    from shown s
    join public.users u on u.id = s.user_id
   order by s.created_at desc;
$function$;

-- share_group_post: refuse to share a private group post.
CREATE OR REPLACE FUNCTION public.share_group_post(p_group_post uuid, p_include_friends boolean, p_circle_ids uuid[] DEFAULT '{}'::uuid[], p_community_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id(); v_group uuid; v_n integer;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  SELECT group_id INTO v_group FROM public.group_posts
   WHERE id = p_group_post AND deleted_at IS NULL;
  IF v_group IS NULL OR NOT public.is_group_member(v_group, v_me) THEN
    RAISE EXCEPTION 'Only group members can share this post';
  END IF;
  -- A private group post is members-only: it can't be shared anywhere.
  IF EXISTS (SELECT 1 FROM public.group_posts WHERE id = p_group_post AND is_private) THEN
    RAISE EXCEPTION 'This post is private to the group';
  END IF;

  DELETE FROM public.group_post_audiences
   WHERE group_post_id = p_group_post AND shared_by = v_me;

  INSERT INTO public.group_post_audiences (group_post_id, audience_kind, shared_by, circle_id, community_id)
  SELECT p_group_post, 'friends', v_me, NULL::uuid, NULL::uuid WHERE COALESCE(p_include_friends, false)
  UNION ALL
  SELECT p_group_post, 'circle', v_me, c.id, NULL::uuid
    FROM public.circles c
   WHERE c.id = ANY (COALESCE(p_circle_ids, '{}')) AND c.creator_id = v_me
  UNION ALL
  SELECT p_group_post, 'community', v_me, NULL::uuid, cm.community_id
    FROM public.community_members cm
   WHERE cm.community_id = ANY (COALESCE(p_community_ids, '{}')) AND cm.user_id = auth.uid();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $function$
;
