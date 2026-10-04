-- Friends-feed ping prompts that fit the POST they're sent from.
--
-- Before: every Friends post offered the same 6 daily prompts from the
-- general Friends pool ("The first photo of us together", "A place you want
-- to take me…") — written for starting a ping from scratch, not for
-- replying to someone's photo, so they read as random on a post.
--
-- Now a Friends post gets 4 prompts from a new 'friends_post' pool that
-- react to the post itself (a Duo post also draws from its own 'us'
-- category), plus 2 from the daily Friends set for variety. The pick is
-- stable per post and per day (no reshuffle each time the sheet opens) and
-- differs between posts.

alter table public.ping_sheet_prompts drop constraint ping_sheet_prompts_scope_check;
alter table public.ping_sheet_prompts add constraint ping_sheet_prompts_scope_check
  check (scope = any (array['everyone','anonymous','group','ping_page','friends_post']));

insert into public.ping_sheet_prompts (scope, category, prompt_kind, prompt_text) values
  -- any photo post: photo replies
  ('friends_post','post','photo','Recreate this pic. Your version, right now 📸'),
  ('friends_post','post','photo','Your face while looking at this. First take only'),
  ('friends_post','post','photo','Send the photo from your gallery that matches this energy'),
  ('friends_post','post','photo','Show me where you are while I''m staring at this'),
  ('friends_post','post','photo','Your closest match to this in your camera roll'),
  ('friends_post','post','photo','Proof your day is better than this 😤'),
  -- any photo post: text replies
  ('friends_post','post','text','Okay who took this photo? 👀'),
  ('friends_post','post','text','Where is this?? I need to go'),
  ('friends_post','post','text','Rate this pic out of 10. Honestly.'),
  ('friends_post','post','text','The story behind this. Spill.'),
  ('friends_post','post','text','This is so you 😭 explain'),
  ('friends_post','post','text','Why wasn''t I invited 😤'),
  ('friends_post','post','text','Caption this better than you did'),
  ('friends_post','post','text','What happened right after this was taken?'),
  -- Duo ('us') posts
  ('friends_post','us','text','You two again?? What''s the story 👀'),
  ('friends_post','us','text','Who''s the better photographer between you two?'),
  ('friends_post','us','text','Rate your duo out of 10. Be honest.'),
  ('friends_post','us','text','Take me next time. Where was this?'),
  ('friends_post','us','photo','Your duo pic from today. Your turn 📸'),
  ('friends_post','us','photo','Show me who you''d start a Duo with');

create or replace function public.ping_prompts_for_post(p_post_id uuid)
returns table(id uuid, prompt_text text, tier text, prompt_kind text)
language plpgsql stable security definer
set search_path = public, pg_temp
as $function$
declare
  v_author uuid; v_vis text; v_prompt uuid; v_type text;
  v_limit int; v_tier1 int;
  v_day text := ((now() at time zone 'Asia/Kolkata')::date)::text;
begin
  select coalesce(value, 6) into v_limit from public.app_settings where key = 'ping_prompt_limit';
  v_limit := coalesce(v_limit, 6);

  select p.user_id, p.visibility, p.prompt_id, p.post_type
    into v_author, v_vis, v_prompt, v_type
    from public.posts p
   where p.id = p_post_id and p.deleted_at is null;

  if v_author is null then return; end if;

  if v_vis is distinct from 'anonymous' then
    -- Post-reactive first (Duo posts lead with their own lines), then two
    -- from the daily Friends set.
    return query
    with ctx as (
      select sp.id, sp.prompt_text, sp.prompt_kind,
             row_number() over (
               order by (sp.category = 'us' and v_type = 'us') desc,
                        md5(sp.id::text || p_post_id::text || v_day)) as rn
        from public.ping_sheet_prompts sp
       where sp.scope = 'friends_post' and sp.active and sp.community_id is null
         and (sp.category = 'post' or (sp.category = 'us' and v_type = 'us'))
    )
    select ctx.id, ctx.prompt_text, 'post'::text, ctx.prompt_kind
      from ctx
     where ctx.rn <= greatest(v_limit - 2, 1)
     order by ctx.rn;

    return query
    select r.id, r.prompt_text, 'daily'::text, r.prompt_kind
      from public.rotating_ping_prompts('everyone') r
     limit 2;
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
       -- Stable per post per day (was random(): a different set on every
       -- open of the same post).
       order by md5(pp.id::text || p_post_id::text || v_day)
       limit v_limit;
      return;
    end if;
  end if;

  return query
  select sp.id, sp.prompt_text, 'default'::text, sp.prompt_kind
    from public.ping_sheet_prompts sp
   where sp.community_id is null and sp.active and sp.scope = 'anonymous'
   order by md5(sp.id::text || p_post_id::text || v_day)
   limit v_limit;
end;
$function$;
