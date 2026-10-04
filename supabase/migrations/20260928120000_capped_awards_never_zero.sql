-- Score cards showed "+0" after a few posts in a day.
--
-- award_capped (used by group posts 25, Duo photos 20, Moment replies 20)
-- paid NOTHING once a person had 5 of that action today (IST), so the
-- reward card after the 6th post read +0 — reported as "some score cards
-- are showing zero points ... give some points there", and it hit exactly
-- the people posting the most.
--
-- Now: the first 5 per type per day still pay full points; every one after
-- that pays a flat 5 instead of 0. Keeps the anti-farming shape (full
-- points can't be farmed) without a dead "+0" card.
create or replace function public.award_capped(p_user uuid, p_type text, p_points integer)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_pts integer := p_points;
begin
  if p_user is null then return; end if;
  if (select count(*) from public.score_events e
       where e.user_id = p_user and e.event_type = p_type
         and e.created_at >= ((now() at time zone 'Asia/Kolkata')::date::timestamp at time zone 'Asia/Kolkata')) >= 5 then
    v_pts := least(p_points, 5);
  end if;
  update public.users set glow_score = glow_score + v_pts where id = p_user;
  perform public.log_score_event(p_user, p_type, v_pts);
end
$$;
