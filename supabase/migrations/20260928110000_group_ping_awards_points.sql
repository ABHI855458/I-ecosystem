-- (Superseded — kept as a no-op record.) A first version of this file made
-- award_ping_sent_score pay 25 on a group ping's sender row, on the belief
-- that group pings earned nothing. They already DO: send_group_ping itself
-- credits 25 (ping_score + log_score_event 'ping_sent') once per send, so
-- that change double-counted (50). Restored to the original body below.
create or replace function public.award_ping_sent_score()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.group_id is not null then
    return new;
  end if;
  update public.users set ping_score = ping_score + 25 where id = new.sender_id;
  perform public.log_score_event(new.sender_id, 'ping_sent', 25);
  return new;
end;
$$;
