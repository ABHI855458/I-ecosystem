-- Circles are your own audience lists, so you can add ANYONE — no shared
-- community required (by product request: the "you need a shared community"
-- refusal was irrelevant and confusing). Still refused: yourself, a deleted
-- account, and anyone blocked either way.
create or replace function public.circle_member_is_eligible(p_circle_id uuid, p_member_id uuid)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select exists (
    select 1
      from public.circles c
      join public.users cu on cu.id = c.creator_id
      join public.users mu on mu.id = p_member_id
     where c.id = p_circle_id
       and mu.deleted_at is null
       and mu.id <> cu.id
       and not public.is_blocked_user(cu.auth_id, mu.id)
  );
$function$;
