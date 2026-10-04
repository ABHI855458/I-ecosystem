-- New-group-post notification to the OTHER members now reads as the same
-- "pick your side of the audience" ask a Duo photo makes — explicit request:
-- "the group post shall also go to other members to choose their audience".
-- The mechanism already existed (share_group_post + the inbox row's
-- audience button + Profile -> Requests); only the wording hid it, and the
-- push now opens the inbox (main_shell.dart) where that button is.
-- Body otherwise identical to the live definition.
create or replace function public.notify_group_post()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
DECLARE v_group text; v_name text;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN RETURN NEW; END IF;
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(NULLIF(btrim(u.name), ''), 'Someone') INTO v_name
    FROM public.users u WHERE u.id = NEW.user_id;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT gm.user_id, 'group_post', NEW.user_id, 'standard',
         v_name || ' posted in ' || v_group,
         'Pick who sees it on your side — your circles or communities',
         jsonb_build_object('screen','group','group_id', NEW.group_id,
                            'group_post_id', NEW.id, 'action', 'share'),
         'group_post:' || NEW.id::text || ':' || gm.user_id::text
    FROM public.group_members gm
   WHERE gm.group_id = NEW.group_id AND gm.user_id <> NEW.user_id
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;
