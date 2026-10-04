-- ---------------------------------------------------------------------------
-- anon_post_reaction_faces(post) — the RealMoji faces on an anonymous post.
--
-- The anon feed could only ever show emoji + counts (anon_reaction_counts),
-- because post_realmoji_reactions stays closed for anonymous posts on
-- purpose: opening the raw rows would hand every client a reactor -> user_id
-- map. But a RealMoji IS the photo — "when reacted it shall get saved along
-- with the image, and it shall be able to be seen there in anonymous" — so
-- the count-only view left the feature looking broken.
--
-- This returns the PHOTOS WITHOUT THE PEOPLE: emoji_type and the reactor's
-- saved selfie url, and nothing else. No user_id, no name, no ordering that
-- correlates to a user. So a viewer sees the faces that reacted, exactly as
-- the feature intends, and cannot programmatically resolve any of them back
-- to an account the way an open table read would allow.
--
-- Gated on post_engagement_visible(), same as reactions and post_viewers:
-- you can only read this for a post you can already see.
--
-- The join is on (user_id, feed_scope='anonymous', emoji_type) because that
-- is exactly the key RealmojiService writes under for an anon-feed reaction
-- (captureSelfieOnly's upsert). A reaction whose saved selfie was later
-- retaken away comes back with a null url; the strip falls back to a plain
-- glyph rather than dropping the reaction.
-- ---------------------------------------------------------------------------

create or replace function public.anon_post_reaction_faces(p_post_id uuid)
returns table (
  emoji_type text,
  image_url text,
  reacted_at timestamptz
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select
    r.emoji_type::text,
    m.image_url,
    r.created_at
  from public.post_realmoji_reactions r
  left join public.user_realmojis m
    on m.user_id = r.user_id
   and m.feed_scope = 'anonymous'
   and m.emoji_type = r.emoji_type
  where r.post_id = p_post_id
    and public.post_engagement_visible(p_post_id)
  order by r.created_at desc;
$$;

revoke all on function public.anon_post_reaction_faces(uuid) from public;
grant execute on function public.anon_post_reaction_faces(uuid) to authenticated;
