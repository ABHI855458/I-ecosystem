-- One reaction per person per post — the newest one wins.
--
-- RealmojiService.reactWithSaved INSERTs a fresh post_realmoji_reactions row
-- on every tap, and a double-tap emoji lands in `reactions` (a separate
-- table), so reacting twice left BOTH on the post. Explicit request: "the
-- newest reaction real emoji shall be saved not both".
--
-- Enforced server-side (BEFORE INSERT triggers) rather than only in the
-- client, so every card/feed path gets it without each one remembering to
-- delete first. SECURITY DEFINER because the delete of the older row must
-- succeed whatever RLS the caller has on the other table.

create or replace function public.replace_prior_realmoji_reaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.post_id is not null then
    delete from post_realmoji_reactions
     where user_id = new.user_id and post_id = new.post_id;
    delete from reactions
     where user_id = new.user_id and post_id = new.post_id;
  elsif new.group_post_id is not null then
    delete from post_realmoji_reactions
     where user_id = new.user_id and group_post_id = new.group_post_id;
    delete from reactions
     where user_id = new.user_id and group_post_id = new.group_post_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_replace_prior_realmoji_reaction on public.post_realmoji_reactions;
create trigger trg_replace_prior_realmoji_reaction
  before insert on public.post_realmoji_reactions
  for each row execute function public.replace_prior_realmoji_reaction();

-- An emoji reaction (reactions table, upserted on (post,user,type)) replaces
-- any RealMoji the same person left on the same post. BEFORE INSERT fires on
-- the upsert's conflict/UPDATE path too, so re-picking an emoji still clears
-- a RealMoji placed in between.
create or replace function public.replace_prior_emoji_reaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.post_id is not null then
    delete from post_realmoji_reactions
     where user_id = new.user_id and post_id = new.post_id;
  elsif new.group_post_id is not null then
    delete from post_realmoji_reactions
     where user_id = new.user_id and group_post_id = new.group_post_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_replace_prior_emoji_reaction on public.reactions;
create trigger trg_replace_prior_emoji_reaction
  before insert on public.reactions
  for each row execute function public.replace_prior_emoji_reaction();

-- Backfill: collapse existing duplicates to the newest reaction.
-- 1) Several RealMoji by one person on one post -> keep the newest.
delete from post_realmoji_reactions r
 using post_realmoji_reactions newer
 where newer.user_id = r.user_id
   and coalesce(newer.post_id, newer.group_post_id)
       = coalesce(r.post_id, r.group_post_id)
   and (newer.created_at, newer.id) > (r.created_at, r.id);

-- 2) An emoji AND a RealMoji by one person on one post -> keep whichever is
--    newer. reactions.created_at is a zoneless UTC timestamp.
delete from reactions e
 using post_realmoji_reactions m
 where m.user_id = e.user_id
   and coalesce(m.post_id, m.group_post_id)
       = coalesce(e.post_id, e.group_post_id)
   and m.created_at >= (e.created_at at time zone 'UTC');

delete from post_realmoji_reactions m
 using reactions e
 where m.user_id = e.user_id
   and coalesce(m.post_id, m.group_post_id)
       = coalesce(e.post_id, e.group_post_id)
   and (e.created_at at time zone 'UTC') > m.created_at;
