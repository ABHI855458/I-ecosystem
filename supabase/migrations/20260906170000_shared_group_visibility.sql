-- ---------------------------------------------------------------------------
-- A group post shared out to friends/a community showed up in the feed with
-- no members and no group.
--
-- 20260906130000 made the POST visible to its shared audience, but nothing
-- else about the group was. Verified live as user `abi`, who is neither a
-- member nor friends with the members:
--     shared_posts_visible = 1
--     members_visible      = 0     <- group_members_select / _select_friend
--     group_row_visible    = 0     <- groups' own policies
-- so DesignGroupCard rendered "0 members", an empty streak row, and had no
-- groups row to navigate to. Reported as "I did a recent group post and it
-- doesn't show members in the group in the feed."
--
-- This grants exactly what the card needs and nothing more: if a group has
-- at least one post shared WITH YOU, you may read that group's row and its
-- membership. You still cannot read its other posts — group_posts keeps its
-- own per-post policies, so only the shared ones come through.
--
-- group_shared_to_me() is SECURITY DEFINER for the usual reason and a
-- sharper one: a policy on group_members that queried group_posts directly
-- would re-enter group_posts_select, which queries group_members — a
-- guaranteed 42P17. Running the lookup with RLS off breaks that cycle.
-- group_post_audience_admits() (also SECURITY DEFINER) does the audience
-- test, so this adds no new notion of who is admitted.
-- ---------------------------------------------------------------------------

create or replace function public.group_shared_to_me(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
      from public.group_posts gp
     where gp.group_id = p_group_id
       and gp.deleted_at is null
       and public.group_post_audience_admits(gp.id, gp.user_id)
  );
$$;

drop policy if exists group_members_select_shared_group on public.group_members;
create policy group_members_select_shared_group
  on public.group_members
  for select
  using (public.group_shared_to_me(group_id));

drop policy if exists groups_select_shared_post on public.groups;
create policy groups_select_shared_post
  on public.groups
  for select
  using (public.group_shared_to_me(id));
