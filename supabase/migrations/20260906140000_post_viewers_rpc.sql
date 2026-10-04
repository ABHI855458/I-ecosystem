-- ---------------------------------------------------------------------------
-- post_viewers(post) — the real "seen by" list behind the anon card's seen
-- chip.
--
-- The chip's popover used to render kAnonViewerRoster, a hardcoded fixture
-- of invented names, and then (after the previous pass) just a count. There
-- was no way to render the truth from the client: post_views' only SELECT
-- policy is post_views_select_self, so a viewer can read their OWN view
-- rows and nothing else. This is the SECURITY DEFINER read that lifts that,
-- deliberately and narrowly.
--
-- Who may call it: anyone who can already see the post, via the existing
-- post_engagement_visible() gate — the same rule that decides who may read
-- its reactions. So this cannot be used to enumerate views on a post you
-- have no access to.
--
-- Note what this does and does not expose. The POST is anonymous; the
-- people who OPENED it never were — they are ordinary named accounts, and
-- naming them here says nothing about who wrote the post. The author's
-- identity still comes only from posts_feed, which masks user_id for
-- anonymous rows.
--
-- is_pinned is relative to the CALLER (pinned_people.user_id = me), and the
-- ordering puts pinned people first, then most recent — "the post having
-- the pinned people in the top".
-- ---------------------------------------------------------------------------

create or replace function public.post_viewers(p_post_id uuid)
returns table (
  user_id uuid,
  username text,
  name text,
  avatar_url text,
  is_pinned boolean,
  viewed_at timestamptz
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with me as (select id from public.users where auth_id = auth.uid())
  select
    u.id,
    u.username,
    u.name,
    u.profile_photo_url,
    exists (
      select 1
        from public.pinned_people pp
       where pp.user_id = (select id from me)
         and pp.pinned_user_id = u.id
    ) as is_pinned,
    pv.created_at
  from public.post_views pv
  join public.users u on u.id = pv.viewer_id
  where pv.post_id = p_post_id
    and public.post_engagement_visible(p_post_id)
  order by 5 desc, pv.created_at desc;
$$;

revoke all on function public.post_viewers(uuid) from public;
grant execute on function public.post_viewers(uuid) to authenticated;
