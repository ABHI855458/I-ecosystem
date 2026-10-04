-- Group ping likes: count updates live (explicit request, 2026-09-28 — "in
-- group pings if two people like, the count on the ping shall increase").
--
-- The count itself was always right (get_group_wall / ping_inbox /
-- toggle_ping_reply_reaction all count(*) ping_reply_reactions). What never
-- happened was a refresh: ping_reply_reactions RLS only returns the caller's
-- OWN rows (deliberately — reactor identity is never handed out), so the app
-- cannot subscribe to other people's likes. Denormalising the count onto
-- ping_replies — already in the supabase_realtime publication and already
-- watched by PingPage — turns every like/unlike into a reply-row UPDATE the
-- replier's (and wall members') realtime channel delivers. Count only, no
-- identity.

ALTER TABLE public.ping_replies
  ADD COLUMN IF NOT EXISTS like_count integer NOT NULL DEFAULT 0;

UPDATE public.ping_replies r
   SET like_count = x.c
  FROM (SELECT reply_id, count(*)::int AS c
          FROM public.ping_reply_reactions GROUP BY reply_id) x
 WHERE x.reply_id = r.id AND r.like_count IS DISTINCT FROM x.c;

CREATE OR REPLACE FUNCTION public.sync_ping_reply_like_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_reply uuid := COALESCE(NEW.reply_id, OLD.reply_id);
BEGIN
  UPDATE public.ping_replies
     SET like_count = (SELECT count(*)::int FROM public.ping_reply_reactions
                        WHERE reply_id = v_reply)
   WHERE id = v_reply;
  RETURN NULL;
END; $function$;
REVOKE ALL ON FUNCTION public.sync_ping_reply_like_count() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sync_ping_reply_like_count ON public.ping_reply_reactions;
CREATE TRIGGER trg_sync_ping_reply_like_count
  AFTER INSERT OR DELETE ON public.ping_reply_reactions
  FOR EACH ROW EXECUTE FUNCTION public.sync_ping_reply_like_count();
