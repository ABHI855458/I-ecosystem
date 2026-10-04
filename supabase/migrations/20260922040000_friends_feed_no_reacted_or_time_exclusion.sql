-- FRIENDS_FEED — drop the self-post 24h cutoff.
--
-- Explicit ruling: "the friends feed shall have all the posts which shall
-- be visible to user... no posts shall go out of his feed as such reacted,
-- unreacted or on any time as-is... except his friends['] [posts]" — the
-- ONLY thing that should gate this feed is the existing visibility check
-- (friend / shared audience / self), never engagement state or age.
--
-- The reacted/pinged half of this is a CLIENT-side filter
-- (FeedService.fetchFriendsFeed's excludeReacted, now defaulted false —
-- see that file) and needed no server change. This migration is the other
-- half: friends_feed itself had
--
--   WHEN p.user_id = (SELECT id FROM me) THEN p.created_at > now() - 24h
--
-- which silently dropped the VIEWER'S OWN posts from their own friends
-- feed after a day — a time-based removal with no friendship relevance,
-- exactly what the ruling calls out. Removed.
--
-- The Moment branch (WHEN p.post_type = 'moment' THEN ... 24h) is
-- DELIBERATELY untouched: Moments are 24h-ephemeral as a cross-cutting
-- product property confirmed repeatedly elsewhere in this system (post
-- card doc, notify_moment_new_post_to_friends, etc.), not something
-- specific to this feed's own filtering — this ruling is about the
-- friends feed's OWN exclusions, not about redefining what a Moment is.
CREATE OR REPLACE FUNCTION public.friends_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS SETOF posts
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid())
  select p.* from public.posts p
  where p.deleted_at is null
    and p.post_type is distinct from 'memory'
    and p.visibility in ('everyone', 'friends')
    and (
      case
        when p.post_type = 'moment' then p.created_at > now() - interval '24 hours'
        else true
      end
    )
    and (
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
      or
      exists (select 1 from public.post_audiences pa
              join public.circle_members cm on cm.circle_id = pa.circle_id
              where pa.post_id = p.id
                and pa.audience_kind = 'circle'
                and cm.member_id = (select id from me))
    )
  order by (p.user_id = (select id from me)) desc, p.created_at desc
  limit p_limit offset p_offset;
$function$;
