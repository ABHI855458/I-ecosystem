-- ---------------------------------------------------------------------------
-- Group post "Also show to: Friends / <community>" was a dead control.
--
-- GroupPostScreen has offered those pills for a while and GroupService.addPost
-- has been writing real group_post_audiences rows for them — but nothing ever
-- READ those rows. group_posts had exactly two SELECT policies, both
-- "you are a member of the group", so a post shared to a friend or to a
-- community was still visible only to the group's own members: the pills
-- changed nothing at all for the people they named.
--
-- This adds the missing read path, matching what posts already does for the
-- personal composer (can_view_post's post_audiences branch):
--   * audience_kind 'friends'   -> any accepted friend of the post's author
--   * audience_kind 'community' -> any member of that community
--
-- The helper is SECURITY DEFINER for the usual reason: the policy lives on
-- group_posts and the lookup reads group_post_audiences, whose own SELECT
-- policy reads group_posts back. Evaluating that inline is the 42P17
-- recursion this codebase has already hit twice (us_albums, groups).
--
-- Additive only. The two existing member policies are untouched, and this
-- one is PERMISSIVE, so it only ever widens — a group post with no audience
-- rows stays exactly as private as it is today.
-- ---------------------------------------------------------------------------

create or replace function public.group_post_audience_admits(
  p_group_post_id uuid,
  p_author_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
      from public.group_post_audiences a
     where a.group_post_id = p_group_post_id
       and (
            (a.audience_kind = 'friends' and public.is_friend_of(p_author_id))
         or (a.audience_kind = 'community'
             and a.community_id is not null
             and public.is_community_member(a.community_id, auth.uid()))
       )
  );
$$;

drop policy if exists group_posts_select_shared_audience on public.group_posts;

create policy group_posts_select_shared_audience
  on public.group_posts
  for select
  using (
    deleted_at is null
    and public.group_post_audience_admits(id, user_id)
  );
