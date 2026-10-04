-- A. BULK REACTIONS -------------------------------------------------------
-- "if any body reacts as such, send it in bulk like three people reacted".
--
-- Rather than a new batching timer, this reuses the batching that already
-- exists: a reaction is minor tier, and push_allowed() only lets minor
-- through in wake_digest / snack_peak / lunch_peak. So reactions already
-- sit unsent for hours. Collapsing them is therefore just: while a
-- reaction notification for this (recipient, post) is still UNSENT, fold
-- the new reaction into it and re-title with the count. Once it has been
-- pushed, the next reaction opens a fresh row, so a later batch still
-- notifies.
--
-- The count lives in data->>'reactor_count' rather than being recomputed
-- from post_reactions, so a retracted reaction can't make the number go
-- backwards after the push already said "3 people".

CREATE OR REPLACE FUNCTION public.fold_reaction_notification(
  p_owner uuid, p_post uuid, p_actor uuid, p_emoji text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
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
            jsonb_build_object('reactor_count', 1, 'screen', 'post', 'post_id', p_post),
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
$$;

CREATE OR REPLACE FUNCTION public.notify_reaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_owner uuid;
BEGIN
  IF NEW.post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.posts WHERE id = NEW.post_id;
  ELSIF NEW.group_post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.group_posts WHERE id = NEW.group_post_id;
  END IF;

  IF v_owner IS NULL OR v_owner = NEW.user_id THEN RETURN NEW; END IF;

  PERFORM public.fold_reaction_notification(v_owner, NEW.post_id, NEW.user_id, NEW.emoji);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_realmoji_reaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_owner uuid; v_emoji text;
BEGIN
  IF NEW.post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.posts WHERE id = NEW.post_id;
  ELSIF NEW.group_post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.group_posts WHERE id = NEW.group_post_id;
  END IF;

  IF v_owner IS NULL OR v_owner = NEW.user_id THEN RETURN NEW; END IF;

  v_emoji := NULLIF(NEW.emoji_type::text, '');
  PERFORM public.fold_reaction_notification(v_owner, NEW.post_id, NEW.user_id, v_emoji);
  RETURN NEW;
END;
$$;

-- B. PINNED VIEWER --------------------------------------------------------
-- "if pinned people viewed your anon or friends post then also notify".
-- Fires only when the VIEWER is someone the post OWNER has pinned, so it
-- can never be used to discover who pinned you — it is the owner's own pin
-- list being reported back to them. Still unnamed, per the curiosity rule.

CREATE OR REPLACE FUNCTION public.notify_pinned_post_view()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_owner uuid; v_vis text;
BEGIN
  SELECT user_id, visibility INTO v_owner, v_vis
  FROM public.posts WHERE id = NEW.post_id AND deleted_at IS NULL;

  IF v_owner IS NULL OR v_owner = NEW.viewer_id THEN RETURN NEW; END IF;

  -- Owner must have pinned the viewer. is_pinned_by(owner, viewer).
  IF NOT COALESCE(public.is_pinned_by(v_owner, NEW.viewer_id), false) THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  VALUES (v_owner, 'pinned_post_view', NEW.viewer_id, NEW.post_id, 'standard',
          'Someone you pinned just saw your post 👀',
          CASE WHEN v_vis = 'anonymous' THEN 'on your anonymous post' ELSE NULL END,
          jsonb_build_object('screen','post','post_id', NEW.post_id),
          'pinned_post_view:' || NEW.post_id::text || ':' || NEW.viewer_id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$$;

ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type = ANY (ARRAY[
    'reaction','ping','friend_request','friend_accepted','branch_view',
    'us_album_mutual','report_resolved','report_filed','announcement',
    'ping_answered','us_album_invite','comment','moment_contribution',
    'group_added','group_post','group_dip','community_post','friend_post',
    'streak_risk_red','streak_risk_blue','streak_milestone_blue',
    'group_streak_ping','group_streak_risk','group_streak_broken',
    'level_up','level_progress','leaderboard_movement',
    'ping_unanswered','group_ping_waiting','group_ping_replied',
    'pinned_post_view'
  ]));

DROP TRIGGER IF EXISTS trg_notify_pinned_post_view ON public.post_views;
CREATE TRIGGER trg_notify_pinned_post_view
  AFTER INSERT ON public.post_views
  FOR EACH ROW EXECUTE FUNCTION public.notify_pinned_post_view();
