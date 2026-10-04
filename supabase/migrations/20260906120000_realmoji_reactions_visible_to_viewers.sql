-- ---------------------------------------------------------------------------
-- RealMoji reactions were only ever readable by the POST AUTHOR.
--
-- post_realmoji_reactions_select gated every non-group row on
--   (visibility <> 'anonymous' OR auth.uid() = author)
--   AND (visibility <> 'friends'   OR auth.uid() = author)
-- which is fine for 'everyone' posts and wrong for the other two: on a
-- 'friends' post, nobody but the author could read the reactions at all, so
-- PostReactions.loadReactionSummary came back with the RealMoji half empty
-- for every other viewer. Verified live before this change: user
-- abisheksdpatel could SELECT the post a2b2b97c (visibility 'friends') and
-- its `reactions` row, but saw 0 of its 1 post_realmoji_reactions row.
--
-- The sibling `reactions` table already had this right — it gates on
-- post_engagement_visible(), a SECURITY DEFINER helper that says
-- "engagement is as readable as the post is", reusing can_view_post for
-- the 'friends' case. This aligns the two.
--
-- ANONYMOUS POSTS STAY EXCLUDED, deliberately. The anon feed shows an
-- identity-free breakdown (emoji + count, never a reactor list) and reads
-- it from the anon_reaction_counts view, which is owned by postgres and so
-- bypasses RLS on this table entirely — anon counts are already visible to
-- every viewer without exposing user_id. Opening raw rows for anon posts
-- would hand every client the identity of everyone who reacted, which is
-- the one thing that view exists to avoid.
--
-- post_realmoji_reactions_select_own is untouched, so a reactor still
-- reads their OWN row on an anon post (RealmojiService.myReaction, which
-- drives the "already reacted" glow).
-- ---------------------------------------------------------------------------

drop policy if exists post_realmoji_reactions_select on public.post_realmoji_reactions;

create policy post_realmoji_reactions_select
  on public.post_realmoji_reactions
  for select
  using (
    (
      post_id is not null
      and public.post_engagement_visible(post_id)
      and exists (
        select 1
          from public.posts p
         where p.id = post_realmoji_reactions.post_id
           and p.visibility is distinct from 'anonymous'
      )
    )
    or exists (
      select 1
        from public.group_posts gp
        join public.group_members gm on gm.group_id = gp.group_id
        join public.users u on u.id = gm.user_id
       where gp.id = post_realmoji_reactions.group_post_id
         and u.auth_id = auth.uid()
    )
  );
