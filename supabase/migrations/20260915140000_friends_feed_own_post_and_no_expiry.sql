-- Correction to 20260915130000's own-post exclusion + blanket 48h window,
-- after explicit follow-up clarifying the actual rule for the Friends feed:
--
--   * Ordinary (non-moment) posts have NO time expiry at all — the ONLY
--     things that remove one are the viewer reacting to it or pinging it
--     (both already handled client-side by fetchFriendsFeed's excludeReacted
--     / _skipPostIds, unchanged by this migration). "48h is for anon" — the
--     Anon TAB's own window (fetchAnonFeed/anonCutoff), which this function
--     was never involved in anyway now that visibility='anonymous' is
--     excluded here.
--   * EXCEPT your own post: previously excluded from your own Friends feed
--     entirely ("a Friends feed is specifically OTHER people's posts", per
--     this function's own prior design) — now explicitly included, shown
--     FIRST, and dropped after 24h. Moments keep their existing 24h window
--     regardless of author.
--
-- Ordering: (is mine) DESC, created_at DESC — own post(s) first, then
-- everyone else by recency. The client shuffles the "not mine" portion on
-- top of this (see everyone_feed_screen.dart's Friends branch) for the
-- requested resurfacing behaviour; SQL only needs to guarantee the
-- own-post-first grouping survives that shuffle.
CREATE OR REPLACE FUNCTION public.friends_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS SETOF posts
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  with me as (select id from public.users where auth_id = auth.uid())
  select p.* from public.posts p
  where p.deleted_at is null
    and p.post_type is distinct from 'memory'
    and p.visibility in ('everyone', 'friends')
    and (
      case
        when p.post_type = 'moment' then p.created_at > now() - interval '24 hours'
        when p.user_id = (select id from me) then p.created_at > now() - interval '24 hours'
        else true
      end
    )
    and (
      -- Your own post (own regular posts now included, not just 'us').
      p.user_id = (select id from me)
      or
      (p.post_type = 'us' and (p.user_id = (select id from me)
                            or p.partner_user_id = (select id from me)))
      or
      exists (select 1 from public.friendships f
              where f.status = 'accepted'
                and ((f.requester_id = (select id from me) and f.addressee_id = p.user_id)
                  or (f.addressee_id = (select id from me) and f.requester_id = p.user_id)))
      or
      (p.partner_user_id is not null and exists (
         select 1 from public.friendships f
          where f.status = 'accepted'
            and ((f.requester_id = (select id from me) and f.addressee_id = p.partner_user_id)
              or (f.addressee_id = (select id from me) and f.requester_id = p.partner_user_id))))
      or
      exists (select 1 from public.post_audiences pa
              join public.community_members cm on cm.community_id = pa.community_id
              where pa.post_id = p.id
                and pa.audience_kind = 'community'
                and cm.user_id = auth.uid())
    )
  order by (p.user_id = (select id from me)) desc, p.created_at desc
  limit p_limit offset p_offset;
$$;
