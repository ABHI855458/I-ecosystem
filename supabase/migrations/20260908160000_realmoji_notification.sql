-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Reaction notifications fire on the table the app actually uses      ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- notify_reaction sits on `reactions` — the older emoji table, 8 rows. The
-- app's real reaction path is `post_realmoji_reactions`, 20 rows, with no
-- trigger at all. So "reaction" appeared in the wired list while most
-- reactions notified nobody.
--
-- The legacy trigger is LEFT IN PLACE: `reactions` still has rows and a
-- couple of surfaces still read it, so removing its notification would be a
-- second, separate behaviour change. This adds the missing half.
--
-- Column names differ between the two tables — `reactions.emoji` vs
-- `post_realmoji_reactions.emoji_type` — which is why this can't simply
-- reuse the same function.

CREATE OR REPLACE FUNCTION public.notify_realmoji_reaction()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_owner      uuid;
  v_actor_name text;
  v_anon       boolean := false;
BEGIN
  IF NEW.post_id IS NOT NULL THEN
    SELECT user_id, (visibility = 'anonymous')
      INTO v_owner, v_anon
      FROM public.posts WHERE id = NEW.post_id;
  ELSIF NEW.group_post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.group_posts WHERE id = NEW.group_post_id;
  END IF;

  -- No owner, or reacting to your own post: nothing to say.
  IF v_owner IS NULL OR v_owner = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name
    FROM public.users WHERE id = NEW.user_id;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, dedupe_key)
  VALUES (
    v_owner,
    'reaction',
    -- The REACTOR is never anonymous — only a post's author can be. So
    -- naming them to the post's owner leaks nothing, and it is what makes
    -- the notification useful.
    NEW.user_id,
    NEW.post_id,
    'standard',
    v_actor_name || ' reacted to your post',
    -- On an anonymous post the owner already knows it is theirs; the body
    -- says nothing about the post's content either way.
    CASE WHEN v_anon THEN 'on your anonymous post' ELSE NEW.emoji_type::text END,
    'realmoji:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_realmoji_reaction ON public.post_realmoji_reactions;
CREATE TRIGGER trg_notify_realmoji_reaction
  AFTER INSERT ON public.post_realmoji_reactions
  FOR EACH ROW EXECUTE FUNCTION public.notify_realmoji_reaction();
