-- Dashboard sections backend repair: Community / Anon / Friends / Reporting
-- Applied live via `supabase db query --linked -f`, not `db push` (ledger is
-- known out of sync on this project — see project_live_db_schema_drift memory).
--
-- 1) Soft-delete leak: close_group_view_posts is a PERMISSIVE SELECT policy on
--    posts with no deleted_at check. Permissive policies OR together, so a
--    moderator "removing" a post via deleted_at left it visible to anyone
--    following the author through this policy alone. Never in version control
--    before this file.
drop policy if exists close_group_view_posts on posts;
create policy close_group_view_posts on posts
  for select
  using (
    deleted_at is null
    and (
      user_id in (select users.id from users where users.auth_id = auth.uid())
      or (
        not exists (select 1 from anonymous_post_authors where anonymous_post_authors.post_id = posts.id)
        and exists (
          select 1 from follows f
          join users pu on pu.id = posts.user_id
          where f.follower_id = pu.auth_id and f.following_id = auth.uid()
        )
      )
    )
  );

-- 2) group_posts cannot be soft-deleted at all: no deleted_at column, and no
--    moderator write policy. Breaks GroupService.deletePost in the app today
--    and makes the Friends dashboard's group-post Remove impossible.
alter table group_posts add column if not exists deleted_at timestamptz;

drop policy if exists group_posts_select on group_posts;
create policy group_posts_select on group_posts
  for select
  using (
    deleted_at is null
    and exists (
      select 1 from group_members gm
      join users u on u.id = gm.user_id
      where gm.group_id = group_posts.group_id and u.auth_id = auth.uid()
    )
  );

drop policy if exists members_view_posts on group_posts;
create policy members_view_posts on group_posts
  for select
  using (
    deleted_at is null
    and group_id in (
      select gm.group_id from group_members gm
      join users u on u.id = gm.user_id
      where u.auth_id = auth.uid()
    )
  );

drop policy if exists group_posts_update_moderator on group_posts;
create policy group_posts_update_moderator on group_posts
  for update
  using (is_admin_or_global_mod());

-- 3) Let global moderators (not just admin) manage communities, matching how
--    posts/daily_prompts already gate moderator writes via
--    is_admin_or_global_mod(). Approved 2026-09-04.
drop policy if exists communities_insert_moderator on communities;
create policy communities_insert_moderator on communities
  for insert
  with check (is_admin_or_global_mod());

drop policy if exists communities_update_moderator on communities;
create policy communities_update_moderator on communities
  for update
  using (is_admin_or_global_mod());

drop policy if exists communities_delete_moderator on communities;
create policy communities_delete_moderator on communities
  for delete
  using (is_admin_or_global_mod());

-- 4) Missing FK blocks PostgREST embeds of communities from community_members
--    rows (PGRST200) — the exact bug community_service.dart works around with
--    a manual two-step join. Validates cleanly against current live data.
alter table community_members
  add constraint community_members_community_id_fkey
  foreign key (community_id) references communities(id);

-- 5) Dead duplicate membership table: 0 rows live, fully superseded by
--    community_members (see community_service.dart's KEYSPACE FIX note).
drop table if exists user_communities;
