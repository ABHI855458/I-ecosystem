-- ---------------------------------------------------------------------------
-- get_thread_handles() threw on EVERY call.
--
--   ERROR 42702: column reference "user_id" is ambiguous
--   ... It could refer to either a PL/pgSQL variable or a table column.
--   QUERY: INSERT INTO post_thread_handles(post_id, user_id, handle) ...
--
-- RETURNS TABLE(user_id uuid, handle text) declares OUT variables named
-- user_id and handle, and the ON CONFLICT (post_id, user_id) target inside
-- the loop then can't tell the OUT variable from the column. The function
-- raised before returning a single row.
--
-- AnonIdentityService.handlesFor swallows the error into an empty map and
-- CommentService.fetchRecentAnon falls back to the literal string
-- 'someone', so every comment on every anonymous post rendered as
-- "someone" — exactly the reported symptom. Reproduced live before this
-- change by calling the RPC directly.
--
-- Fix is `#variable_conflict use_column`: bare identifiers inside the body
-- resolve to the table's columns, which is what every reference here wants.
-- The signature is unchanged, so the client keeps reading r['user_id'].
-- ---------------------------------------------------------------------------

create or replace function public.get_thread_handles(p_post uuid, p_user_ids uuid[])
returns table (user_id uuid, handle text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_uid uuid;
begin
  if not exists (select 1 from posts where id = p_post and deleted_at is null) then
    return;
  end if;

  foreach v_uid in array p_user_ids loop
    insert into post_thread_handles(post_id, user_id, handle)
    values (p_post, v_uid, gen_handle())
    on conflict (post_id, user_id) do nothing;
  end loop;

  return query
    select pth.user_id, pth.handle
      from post_thread_handles pth
     where pth.post_id = p_post
       and pth.user_id = any(p_user_ids);
end;
$function$;
