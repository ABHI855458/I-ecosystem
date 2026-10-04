-- friends_feed() had no time-window filter and no visibility filter at
-- all, unlike every other feed path in this app:
--   * fetchEveryoneFeed (client) applies momentCutoff (24h) / postCutoff
--     (48h) and restricts to visibility IN ('everyone','friends').
--   * fetchAnonFeed (client) applies anonCutoff (48h) and requires
--     visibility = 'anonymous', reading through posts_feed so identity
--     stays masked.
--   * friends_feed (this function) — neither. A friend's post, Moment or
--     not, stayed in the Friends feed forever.
--
-- Two real bugs, not one:
--   1. Reported directly: "the ended moments shall not be visible in the
--      feed as well the anon posts after 48 hrs they shall be removed" —
--      this function is the only feed path with no expiry logic at all.
--   2. Found while fixing #1: this function returns raw `posts.*`
--      (real user_id, not the anon-masking posts_feed view) and never
--      excludes visibility = 'anonymous'. A friend's anonymous post was
--      reaching their friends' feeds with their REAL IDENTITY attached —
--      exactly what the anon system exists to prevent. Excluding
--      'anonymous' here (anon posts belong to the Anon tab only, same
--      scope fetchEveryoneFeed already enforces) fixes both at once.
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
      case when p.post_type = 'moment'
        then p.created_at > now() - interval '24 hours'
        else p.created_at > now() - interval '48 hours'
      end
    )
    and (
      p.post_type = 'us'
      or (p.user_id <> (select id from me)
          and p.partner_user_id is distinct from (select id from me))
    )
    and (
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
  order by p.created_at desc
  limit p_limit offset p_offset;
$$;
