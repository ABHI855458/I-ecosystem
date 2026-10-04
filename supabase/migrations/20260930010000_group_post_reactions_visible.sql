-- Reactions on a GROUP post were readable only by group members, but
-- non-members legitimately see some group posts in full (shared to them, or
-- a public group's non-private post) and can react to them. They saw a
-- reaction count of 0 (or just their own) while everyone else saw the real
-- one. Rule now: if you can see the group post in full, you can see its
-- reactions — both tables. Locked teasers and private posts stay closed.
create or replace function public.group_post_reactions_visible(p_group_post uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.group_post_feed_access(p_group_post) in ('member', 'open'), false)
      or exists (select 1 from public.group_posts gp
                  where gp.id = p_group_post and gp.deleted_at is null
                    and not gp.is_private
                    and public.group_is_public(gp.group_id));
$$;
revoke all on function public.group_post_reactions_visible(uuid) from public, anon;
grant execute on function public.group_post_reactions_visible(uuid) to authenticated;

drop policy if exists post_realmoji_reactions_select_group_visible on public.post_realmoji_reactions;
create policy post_realmoji_reactions_select_group_visible on public.post_realmoji_reactions
  for select to authenticated
  using (group_post_id is not null and public.group_post_reactions_visible(group_post_id));

drop policy if exists reactions_select_group_visible on public.reactions;
create policy reactions_select_group_visible on public.reactions
  for select to authenticated
  using (group_post_id is not null and public.group_post_reactions_visible(group_post_id));
