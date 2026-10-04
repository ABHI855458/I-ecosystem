-- lock_notification_fields() is a BEFORE UPDATE guard that reverts every
-- column except read_at, so a client holding a session can mark a
-- notification read but can never rewrite its title, tier, actor or
-- push_sent_at. That is worth keeping exactly as strict as it is.
--
-- But it also blocks two legitimate SERVER-side writes this spec needs:
--   * notify_batched()'s counter (§5.4 — "incrementing a count rather than
--     inserting new rows" is by definition an UPDATE of title and data);
--   * the dispatcher stamping push_sent_at once FCM has accepted a push.
--
-- Rather than relaxing the guard for everyone, it now yields to a
-- transaction-local flag that only the server-side notification functions
-- set. Clients cannot set it: PostgREST exposes no way to set an arbitrary
-- GUC, the flag is is_local = true so it dies with the transaction, and
-- EXECUTE on every function that sets it is revoked from anon/authenticated
-- below (Postgres grants EXECUTE to PUBLIC by default — leaving that in
-- place would have let any signed-in client call notify_batched directly).

CREATE OR REPLACE FUNCTION public.lock_notification_fields()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path TO 'public','pg_temp' AS $$
BEGIN
  IF current_setting('app.notif_trusted', true) = 'on' THEN
    RETURN NEW;                       -- server-side path, see header
  END IF;
  NEW.recipient_id := OLD.recipient_id;
  NEW.type         := OLD.type;
  NEW.actor_id     := OLD.actor_id;
  NEW.post_id      := OLD.post_id;
  NEW.tier         := OLD.tier;
  NEW.title        := OLD.title;
  NEW.body         := OLD.body;
  NEW.data         := OLD.data;
  NEW.dedupe_key   := OLD.dedupe_key;
  NEW.created_at   := OLD.created_at;
  NEW.push_sent_at := OLD.push_sent_at;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_batched(
  p_recipient uuid, p_type text, p_tier text, p_dedupe text,
  p_one text, p_many text, p_data jsonb DEFAULT '{}'::jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
BEGIN
  IF p_recipient IS NULL THEN RETURN; END IF;

  PERFORM set_config('app.notif_trusted', 'on', true);   -- transaction-local

  INSERT INTO public.notifications
    (recipient_id, type, tier, title, data, dedupe_key)
  VALUES
    (p_recipient, p_type, p_tier, p_one,
     p_data || jsonb_build_object('count', 1), p_dedupe)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL
  DO UPDATE SET
    data = notifications.data || jsonb_build_object(
             'count', COALESCE((notifications.data->>'count')::int, 1) + 1),
    title = format(p_many, COALESCE((notifications.data->>'count')::int, 1) + 1),
    read_at    = NULL,
    created_at = now();

  PERFORM set_config('app.notif_trusted', 'off', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.notify_batched(uuid,text,text,text,text,text,jsonb)
  FROM PUBLIC, anon, authenticated;
