-- ---------------------------------------------------------------------------
-- Ping-back window: 24h -> 5 days. Explicit request: "the ping back button
-- shall [be available] upto 5 days".
--
-- ping_back_anonymous() re-checks the window server-side (the client-side
-- 24h checks throughout ping_page.dart/ping_screen.dart/ping_service.dart
-- were UI-only guards, never enforcement) — this is the actual gate. Without
-- updating it, widening the client copy alone would have shown a live
-- "Ping them back" button for days 2-5 that then failed with "Ping-back
-- window closed" on tap.
-- ---------------------------------------------------------------------------

create or replace function public.ping_back_anonymous(
  p_ping_id uuid,
  p_prompt text,
  p_anonymous boolean default true
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid;
  v_target uuid;
begin
  v_me := public.current_user_id();
  select p.sender_id into v_target
    from public.pings p
   where p.id = p_ping_id
     and p.receiver_id = v_me
     and exists (
       select 1 from public.ping_replies r
        where r.ping_id = p.id and r.replier_id = v_me
          and r.deleted_at is null
          and r.created_at > now() - interval '5 days'
     );
  if v_target is null then
    raise exception 'Ping-back window closed.';
  end if;
  return public.send_ping(v_target, p_prompt, p_anonymous, 3);
end;
$function$;
