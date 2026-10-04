-- Ping prompts that keep changing (product request: "keep changing and
-- shuffling as the user keeps pinging, he'll be bored of seeing the same
-- ones again and again").
--
-- Before: one fixed daily set for everyone (rotating_ping_prompts was a pure
-- function of the date), cached 30 min on the device, and per-post sets
-- stable for the whole day. Same six prompts, all day.
--
-- Now every person has their own shuffled DECK per prompt pool. Each time
-- the ping sheet asks for prompts it deals the NEXT cards from that deck,
-- so consecutive opens show new prompts. Nothing repeats until the whole
-- pool has been dealt; then the deck reshuffles into a new order.
-- Time-window prompts (morning / lunch / golden hour / night / friday) are
-- still mixed in while their window is open.

create table if not exists public.ping_prompt_decks (
  user_id uuid not null references public.users(id) on delete cascade,
  pool    text not null,
  cycle   int  not null default 0,
  pos     int  not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, pool)
);
alter table public.ping_prompt_decks enable row level security;
revoke all on public.ping_prompt_decks from anon, authenticated;

-- Deal p_n prompts from the caller's deck for (scope, categories).
create or replace function public.deal_ping_prompts(
  p_scope text,
  p_categories text[] default null,
  p_n int default 6
)
returns table(id uuid, prompt_text text, card_color text, prompt_kind text)
language plpgsql volatile security definer
set search_path = public, pg_temp
as $$
declare
  v_me    uuid := public.current_user_id();
  v_pool  text := p_scope || coalesce(':' || array_to_string(p_categories, ','), '');
  v_total int;
  v_cycle int;
  v_pos   int;
  v_taken uuid[] := '{}';
  v_need  int;
begin
  select count(*) into v_total
    from public.ping_sheet_prompts sp
   where sp.scope = p_scope and sp.active and sp.community_id is null
     and sp.time_window is null
     and (p_categories is null or sp.category = any(p_categories));
  if v_total = 0 or p_n <= 0 then return; end if;

  -- Signed-out / no user row: just a fresh random hand.
  if v_me is null then
    return query
    select sp.id, sp.prompt_text, sp.card_color, sp.prompt_kind
      from public.ping_sheet_prompts sp
     where sp.scope = p_scope and sp.active and sp.community_id is null
       and sp.time_window is null
       and (p_categories is null or sp.category = any(p_categories))
     order by random() limit p_n;
    return;
  end if;

  insert into public.ping_prompt_decks(user_id, pool, cycle, pos)
  values (v_me, v_pool, (random() * 1000000)::int, 0)
  on conflict (user_id, pool) do nothing;

  select d.cycle, d.pos into v_cycle, v_pos
    from public.ping_prompt_decks d
   where d.user_id = v_me and d.pool = v_pool
   for update;

  if v_pos >= v_total then
    v_cycle := v_cycle + 1;
    v_pos := 0;
  end if;

  -- The rest of the current deck…
  select coalesce(array_agg(x.id order by x.rk), '{}') into v_taken
    from (
      select sp.id, row_number() over (order by md5(v_me::text || ':' || v_cycle || ':' || sp.id::text)) - 1 as rk
        from public.ping_sheet_prompts sp
       where sp.scope = p_scope and sp.active and sp.community_id is null
         and sp.time_window is null
         and (p_categories is null or sp.category = any(p_categories))
    ) x
   where x.rk >= v_pos and x.rk < v_pos + p_n;
  v_pos := v_pos + coalesce(array_length(v_taken, 1), 0);

  -- …and if it ran out, reshuffle and keep dealing (never the same card
  -- twice in one hand).
  v_need := least(p_n, v_total) - coalesce(array_length(v_taken, 1), 0);
  if v_need > 0 then
    v_cycle := v_cycle + 1;
    v_pos := 0;
    select v_taken || coalesce(array_agg(x.id order by x.rk), '{}') into v_taken
      from (
        select sp.id, row_number() over (order by md5(v_me::text || ':' || v_cycle || ':' || sp.id::text)) - 1 as rk
          from public.ping_sheet_prompts sp
         where sp.scope = p_scope and sp.active and sp.community_id is null
           and sp.time_window is null
           and (p_categories is null or sp.category = any(p_categories))
           and not (sp.id = any(v_taken))
      ) x
     where x.rk < v_need;
    v_pos := v_need;
  end if;

  update public.ping_prompt_decks
     set cycle = v_cycle, pos = v_pos, updated_at = now()
   where user_id = v_me and pool = v_pool;

  return query
  select sp.id, sp.prompt_text, sp.card_color, sp.prompt_kind
    from unnest(v_taken) with ordinality t(pid, ord)
    join public.ping_sheet_prompts sp on sp.id = t.pid
   order by t.ord;
end $$;
revoke all on function public.deal_ping_prompts(text, text[], int) from public, anon, authenticated;

-- Same name/shape as before so every caller keeps working; now deals from
-- the caller's own deck instead of returning the day's fixed set.
create or replace function public.rotating_ping_prompts(p_scope text, p_at timestamptz default now())
returns table(id uuid, prompt_text text, card_color text, prompt_kind text)
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_pool  text := case when p_scope in ('everyone','ping_page') then 'everyone' else p_scope end;
  v_local timestamp := p_at at time zone 'Asia/Kolkata';
  v_limit int;
  v_extra int;
begin
  select coalesce(value, 6) into v_limit from public.app_settings where key = 'ping_prompt_limit';
  v_limit := coalesce(v_limit, 6);

  -- One time-window card while its window is open (random pick, so it
  -- varies too).
  return query
  select sp.id, sp.prompt_text, sp.card_color, sp.prompt_kind
    from public.ping_sheet_prompts sp
   where sp.community_id is null and sp.active and sp.scope = v_pool
     and sp.time_window is not null
     and public.prompt_time_window_active(sp.time_window, v_local)
   order by random()
   limit 1;
  get diagnostics v_extra = row_count;

  return query
  select * from public.deal_ping_prompts(v_pool, null, v_limit - v_extra);
end;
$function$;

create or replace function public.ping_prompts_for_scope(p_scope text)
returns table(id uuid, prompt_text text, card_color text, prompt_kind text)
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_limit int;
begin
  if p_scope in ('everyone','ping_page','group') then
    return query select * from public.rotating_ping_prompts(p_scope);
    if found then return; end if;
  end if;

  select coalesce(value, 6) into v_limit from public.app_settings where key = 'ping_prompt_limit';
  v_limit := coalesce(v_limit, 6);

  return query select * from public.deal_ping_prompts(p_scope, null, v_limit);
  if found then return; end if;

  return query select * from public.deal_ping_prompts('everyone', null, v_limit);
end;
$function$;

create or replace function public.ping_prompts_for_post(p_post_id uuid)
returns table(id uuid, prompt_text text, tier text, prompt_kind text)
language plpgsql volatile security definer
set search_path = public, pg_temp
as $function$
declare
  v_author uuid; v_vis text; v_prompt uuid; v_type text;
  v_limit int; v_tier1 int; v_us int := 0;
begin
  select coalesce(value, 6) into v_limit from public.app_settings where key = 'ping_prompt_limit';
  v_limit := coalesce(v_limit, 6);

  select p.user_id, p.visibility, p.prompt_id, p.post_type
    into v_author, v_vis, v_prompt, v_type
    from public.posts p
   where p.id = p_post_id and p.deleted_at is null;

  if v_author is null then return; end if;

  if v_vis is distinct from 'anonymous' then
    -- Duo posts lead with two Duo-specific cards, then post-reactive ones,
    -- then two from the caller's general deck — all dealt, so every open
    -- of a post shows new ones.
    if v_type = 'us' then
      return query
      select d.id, d.prompt_text, 'post'::text, d.prompt_kind
        from public.deal_ping_prompts('friends_post', array['us'], 2) d;
      get diagnostics v_us = row_count;
    end if;

    return query
    select d.id, d.prompt_text, 'post'::text, d.prompt_kind
      from public.deal_ping_prompts('friends_post', array['post'],
                                    greatest(v_limit - 2 - v_us, 1)) d;

    return query
    select d.id, d.prompt_text, 'daily'::text, d.prompt_kind
      from public.deal_ping_prompts('everyone', null, 2) d;
    return;
  end if;

  if v_prompt is not null then
    select count(*) into v_tier1
      from public.ping_prompts pp
     where pp.daily_prompt_id = v_prompt and pp.active;

    if coalesce(v_tier1, 0) >= 3 then
      return query
      select pp.id, pp.prompt_text, 'prompt'::text, pp.prompt_kind
        from public.ping_prompts pp
       where pp.daily_prompt_id = v_prompt and pp.active
       order by random()
       limit v_limit;
      return;
    end if;
  end if;

  return query
  select d.id, d.prompt_text, 'default'::text, d.prompt_kind
    from public.deal_ping_prompts('anonymous', null, v_limit) d;
end;
$function$;

revoke all on function public.rotating_ping_prompts(text, timestamptz) from public, anon;
revoke all on function public.ping_prompts_for_scope(text) from public, anon;
revoke all on function public.ping_prompts_for_post(uuid) from public, anon;
grant execute on function public.rotating_ping_prompts(text, timestamptz) to authenticated;
grant execute on function public.ping_prompts_for_scope(text) to authenticated;
grant execute on function public.ping_prompts_for_post(uuid) to authenticated;
