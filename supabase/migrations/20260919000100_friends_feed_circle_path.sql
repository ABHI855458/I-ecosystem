-- friends_feed gains a circle-audience qualifying path, alongside the
-- existing friend / us-partner / community paths. Same OR-based structure,
-- and dedup is inherent: the WHERE is a single OR over one `posts` row, so a
-- post qualifying through several paths (friend AND circle member) is still
-- returned exactly once.
CREATE OR REPLACE FUNCTION public.friends_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS SETOF posts
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
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
      -- Circle audience. Reads circle_members as owner (SECURITY DEFINER),
      -- which the viewer themselves can never read — the post simply appears,
      -- with nothing revealing why.
      exists (select 1 from public.post_audiences pa
              join public.circle_members cm on cm.circle_id = pa.circle_id
              where pa.post_id = p.id
                and pa.audience_kind = 'circle'
                and cm.member_id = (select id from me))
    )
  order by (p.user_id = (select id from me)) desc, p.created_at desc
  limit p_limit offset p_offset;
$function$;
