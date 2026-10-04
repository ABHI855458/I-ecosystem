-- No daily ping cap any more — explicit request: "don't limit 5 pings per
-- day, let it be any, but once pinged you cannot ping the same person
-- again".
--
-- enforce_ping_limit raised 'Ping limit reached (5 per 24h).' on the 6th
-- distinct ping thread a sender started in 24h. It now allows any number.
-- The per-person rule is untouched and is what stops spamming one person:
-- send_ping refuses PING_ALREADY_OPEN while your previous ping to that same
-- person is still pending and unexpired.
create or replace function public.enforce_ping_limit()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  return new;
end;
$$;
