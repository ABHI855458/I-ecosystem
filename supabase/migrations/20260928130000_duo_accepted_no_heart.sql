-- Duo accepted notification: drop the 💞 from "X said yes 💞" (explicit
-- request: "accepting the us album invite the notification has a heart
-- symbol, remove it"). Body unchanged. Also strips it from rows already
-- sent so the inbox reads consistently.

CREATE OR REPLACE FUNCTION public.notify_us_album_accepted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_accepter uuid; v_name text;
BEGIN
  IF NOT (NEW.status = 'accepted' AND OLD.status IS DISTINCT FROM 'accepted') THEN RETURN NEW; END IF;
  v_accepter := CASE WHEN NEW.created_by = NEW.user_a THEN NEW.user_b ELSE NEW.user_a END;
  IF v_accepter IS NULL OR v_accepter = NEW.created_by THEN RETURN NEW; END IF;
  SELECT COALESCE(name, anon_name, 'someone') INTO v_name FROM public.users WHERE id = v_accepter;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.created_by, 'us_album_accepted', v_accepter, 'major',
          v_name || ' said yes',
          'Your Duo is live — drop the first photo',
          jsonb_build_object('screen','us_album','album_id', NEW.id),
          'us_album_accepted:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;

-- lock_notification_fields() silently reverts every column but read_at
-- unless this transaction-local flag is set.
SELECT set_config('app.notif_trusted', 'on', true);
UPDATE public.notifications
   SET title = regexp_replace(title, '\s*💞\s*$', '')
 WHERE type = 'us_album_accepted' AND title LIKE '%💞%';
