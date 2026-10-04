-- Last title that still named the actor. The emoji is kept: it is a detail
-- about the reaction, not about who left it, so it adds to the curiosity
-- rather than resolving it.
CREATE OR REPLACE FUNCTION public.notify_realmoji_reaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE
  v_owner uuid;
  v_anon  boolean := false;
  v_emoji text;
BEGIN
  IF NEW.post_id IS NOT NULL THEN
    SELECT user_id, (visibility = 'anonymous') INTO v_owner, v_anon
      FROM public.posts WHERE id = NEW.post_id;
  ELSIF NEW.group_post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.group_posts WHERE id = NEW.group_post_id;
  END IF;

  IF v_owner IS NULL OR v_owner = NEW.user_id THEN
    RETURN NEW;
  END IF;

  v_emoji := NULLIF(NEW.emoji_type::text, '');

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, dedupe_key)
  VALUES (
    v_owner, 'reaction', NEW.user_id, NEW.post_id, 'standard',
    'Someone reacted ' || COALESCE(v_emoji || ' ', '') || 'to your post 👀',
    CASE WHEN v_anon THEN 'on your anonymous post' ELSE NULL END,
    'realmoji:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;
