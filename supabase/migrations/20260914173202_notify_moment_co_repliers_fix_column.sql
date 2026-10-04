-- moment_replies has no deleted_at column (columns are id, moment_post_id,
-- user_id, photo_url, created_at, is_anonymous) — the previous version's
-- `mr.deleted_at IS NULL` predicate aborted every reply insert.
CREATE OR REPLACE FUNCTION public.notify_moment_contribution()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_owner uuid;
  v_anon  boolean := COALESCE(NEW.is_anonymous, false);
BEGIN
  SELECT user_id INTO v_owner FROM public.posts WHERE id = NEW.moment_post_id;

  IF v_owner IS NOT NULL AND v_owner <> NEW.user_id THEN
    INSERT INTO public.notifications
      (recipient_id, type, actor_id, post_id, tier, title, data, dedupe_key)
    VALUES (v_owner, 'moment_contribution',
            CASE WHEN v_anon THEN NULL ELSE NEW.user_id END,
            NEW.moment_post_id, 'standard',
            'Someone added to your Moment 👀',
            jsonb_build_object('screen','moment','post_id', NEW.moment_post_id),
            'moment_contribution:' || NEW.id::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END IF;

  -- Everyone who already replied: replying makes you a participant, and a
  -- participant should hear the thread move. Excludes the new replier and
  -- the owner (covered above); DISTINCT collapses someone who replied more
  -- than once.
  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, data, dedupe_key)
  SELECT DISTINCT mr.user_id, 'moment_contribution',
         CASE WHEN v_anon THEN NULL ELSE NEW.user_id END,
         NEW.moment_post_id, 'standard',
         'Someone else added to a Moment you replied to 👀',
         jsonb_build_object('screen','moment','post_id', NEW.moment_post_id),
         'moment_coreply:' || NEW.id::text || ':' || mr.user_id::text
  FROM public.moment_replies mr
  WHERE mr.moment_post_id = NEW.moment_post_id
    AND mr.id <> NEW.id
    AND mr.user_id <> NEW.user_id
    AND mr.user_id IS DISTINCT FROM v_owner
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$$;
