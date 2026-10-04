-- The reaction fold double-counted the FIRST reactor.
--
-- Found by the Phase 0 verification test, not by reading the code: three
-- RealMoji inserts from only TWO distinct people reported
-- "3 people reacted to your post 👀" with reactor_count = 3.
--
-- CAUSE: the INSERT branch built data as
--     jsonb_build_object('reactor_count', 1, 'screen', ..., 'post_id', ...)
-- with no 'reactors' key. The UPDATE branch's dedupe guard asks
--     data->'reactors' ? p_actor
-- so the person who triggered the INSERT was never recorded as having
-- reacted. Reacting again (switch RealMoji, un-react then re-react — both
-- ordinary user actions, and post_realmoji_reactions takes plain INSERTs)
-- passed the guard and incremented the count a second time. Every
-- subsequent distinct reactor was deduped correctly; only the first was
-- ever wrong, which is exactly why it survived review.
--
-- FIX: seed 'reactors' with the first actor at INSERT time, so the map is
-- complete from the start and the existing guard covers everyone.
--
-- Note the count is still "distinct people who reacted", not "number of
-- reactions" — that is the intended reading of the copy ("3 people
-- reacted"), and the group/community/friend-post fan-outs in spec §3 will
-- reuse this same function, so the off-by-one would have propagated into
-- every batched type once Phase 2 wires them.
CREATE OR REPLACE FUNCTION public.fold_reaction_notification(p_owner uuid, p_post uuid, p_actor uuid, p_emoji text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_existing uuid;
  v_count    int;
BEGIN
  SELECT id, COALESCE((data->>'reactor_count')::int, 1)
    INTO v_existing, v_count
  FROM public.notifications
  WHERE recipient_id = p_owner
    AND type = 'reaction'
    AND post_id IS NOT DISTINCT FROM p_post
    AND push_sent_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing IS NULL THEN
    INSERT INTO public.notifications
      (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
    VALUES (p_owner, 'reaction', p_actor, p_post, 'minor',
            'Someone reacted to your post 👀', p_emoji,
            jsonb_build_object(
              'reactor_count', 1,
              -- THE FIX: the first reactor is recorded here, so the UPDATE
              -- branch's `data->'reactors' ? p_actor` guard can see them.
              'reactors', jsonb_build_object(p_actor::text, true),
              'screen', 'post',
              'post_id', p_post),
            'reaction_batch:' || p_post::text || ':' || extract(epoch from now())::bigint::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    RETURN;
  END IF;

  -- Don't double-count the same person reacting twice to the same post.
  IF EXISTS (
    SELECT 1 FROM public.notifications
    WHERE id = v_existing AND data->'reactors' ? p_actor::text
  ) THEN
    RETURN;
  END IF;

  v_count := v_count + 1;

  -- lock_notification_fields() pins title/body/data on UPDATE unless this
  -- flag is set; it exists to stop clients editing delivered copy, and
  -- this function is exactly the trusted writer it makes an exception for.
  PERFORM set_config('app.notif_trusted', 'on', true);

  UPDATE public.notifications
     SET title = v_count || ' people reacted to your post 👀',
         data  = COALESCE(data, '{}'::jsonb)
                 || jsonb_build_object('reactor_count', v_count)
                 || jsonb_build_object('reactors',
                      COALESCE(data->'reactors', '{}'::jsonb) || jsonb_build_object(p_actor::text, true))
   WHERE id = v_existing;

  PERFORM set_config('app.notif_trusted', 'off', true);
END;
$function$;
