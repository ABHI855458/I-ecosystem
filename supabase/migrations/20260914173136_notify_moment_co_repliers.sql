-- A Moment reply now also notifies everyone who ALREADY replied to it, not
-- just the Moment's owner.
--
-- Explicit request: "if a user replies to other users reply and then if
-- some other user again replies to the moment which isn't his but he had
-- replied, then he shall also get notification that people have replied".
-- Replying makes you a participant in that thread; the owner was the only
-- participant being told it had moved.
--
-- Curiosity copy, same as everywhere else: never names the replier.

CREATE OR REPLACE FUNCTION public.notify_moment_contribution()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_owner uuid;
  v_anon  boolean := COALESCE(NEW.is_anonymous, false);
BEGIN
  SELECT user_id INTO v_owner FROM public.posts WHERE id = NEW.moment_post_id;

  -- 1. The owner, unless they are the one replying.
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

  -- 2. Everyone who replied to this Moment BEFORE this reply. Excludes the
  --    new replier and the owner (covered above), and de-duplicates a
  --    person who replied several times via DISTINCT — the dedupe_key is
  --    per (reply, recipient) so one new reply can only ever produce one
  --    notification per participant.
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
    AND mr.deleted_at IS NULL
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$$;
