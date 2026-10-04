-- ping_back_anonymous had NO guard against being called twice for the same
-- original ping — it only checked "am I the receiver" and "did I reply
-- within 5 days," neither of which is consumed by a successful call. The
-- client's own tracking (_PingPageState.pingedBack) is a plain in-memory
-- Map, reset on every app restart or widget rebuild.
--
-- Live-verified pre-fix: sent a real ping-back, let its resulting outbound
-- ping close (status='closed'), then called ping_back_anonymous again on
-- the SAME original ping_id — it succeeded a second time, creating a
-- second distinct outbound ping/thread referencing the same original ping.
--
-- Fixed with a durable marker column plus SELECT ... FOR UPDATE to close
-- the concurrent-call race, and the marker is only set AFTER send_ping
-- succeeds — so a failed attempt (blocked, rate-limited, whatever) does
-- NOT burn the one-time ping-back opportunity; only an actual successful
-- send does.
ALTER TABLE public.pings ADD COLUMN IF NOT EXISTS pinged_back_at timestamptz;

CREATE OR REPLACE FUNCTION public.ping_back_anonymous(p_ping_id uuid, p_prompt text, p_anonymous boolean DEFAULT true)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid;
  v_target uuid;
  v_already boolean;
  v_thread uuid;
begin
  v_me := public.current_user_id();

  -- FOR UPDATE OF p locks this ping row for the rest of the transaction,
  -- so two concurrent ping-back calls on the same ping_id serialize rather
  -- than both reading "not yet used" and both proceeding.
  select p.sender_id, (p.pinged_back_at is not null)
    into v_target, v_already
    from public.pings p
   where p.id = p_ping_id
     and p.receiver_id = v_me
     and exists (
       select 1 from public.ping_replies r
        where r.ping_id = p.id and r.replier_id = v_me
          and r.deleted_at is null
          and r.created_at > now() - interval '5 days'
     )
   for update of p;

  if v_target is null then
    raise exception 'Ping-back window closed.';
  end if;
  if v_already then
    raise exception 'You already pinged back on this.';
  end if;

  v_thread := public.send_ping(v_target, p_prompt, p_anonymous, 3);

  update public.pings set pinged_back_at = now() where id = p_ping_id;

  return v_thread;
end;
$function$;
