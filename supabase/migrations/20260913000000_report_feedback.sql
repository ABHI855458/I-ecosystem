-- ============================================================================
-- Let the REPORTER see what they reported, and confirm it landed.
--
-- The OUTCOME half already exists and is NOT touched here: resolve_report()
-- (SECURITY DEFINER, moderator-gated) sets reports.status to
-- 'removed'/'dismissed' and inserts a 'report_resolved' notification to the
-- reporter. Statuses in play are 'pending' | 'removed' | 'dismissed'.
--
-- What was missing:
--   1. The reporter cannot read their OWN reports. `reports` has only
--      rep_ins (INSERT) and rep_select_moderator (SELECT, admins/community
--      moderators), so after tapping Report the person had no way to see
--      what they had reported or whether it was still pending. Fixed by
--      rep_select_own, which grants the reporter their own rows and nothing
--      else — rep_select_moderator is untouched and remains what gives
--      moderators the wider queue.
--   2. No acknowledgement at file time. The reporter heard nothing until a
--      moderator happened to act, which could be never.
--
-- The new notification carries NO information about the reported author (no
-- actor_id, no post_id, no name) — reporting must never become a way to
-- learn who posted something, least of all on an anonymous post. Same
-- discipline resolve_report() already follows.
--
-- notifications.type's CHECK is rebuilt from the LIVE list (verified via
-- pg_constraint, 2026-09-05) rather than from any migration file — it had
-- already drifted ahead of them with 'us_album_mutual' and 'report_resolved'.
--
-- NOTE: applied via `supabase db query --linked -f`, not `db push`.
-- ============================================================================

-- 1. Reporter reads own reports. reports.reporter_id holds the RAW auth uid
--    (see rep_ins's `reporter_id = auth.uid()`), NOT users.id — no auth_id
--    indirection here, unlike almost every other policy in this schema.
DROP POLICY IF EXISTS rep_select_own ON public.reports;
CREATE POLICY rep_select_own ON public.reports
  FOR SELECT TO authenticated
  USING (reporter_id = auth.uid());

-- 2. Widen notifications.type by exactly one value.
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('reaction', 'ping', 'friend_request', 'friend_accepted',
                  'branch_view', 'us_album_mutual',
                  'report_resolved', 'report_filed'));

-- Human label for what was reported, never naming who posted it.
CREATE OR REPLACE FUNCTION public.report_target_label(r public.reports)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN r.post_id IS NOT NULL           THEN 'post'
    WHEN r.community_post_id IS NOT NULL THEN 'community post'
    WHEN r.comment_id IS NOT NULL        THEN 'comment'
    WHEN r.ping_id IS NOT NULL           THEN 'ping'
    ELSE 'content'
  END;
$$;

-- 3. "Report received", on INSERT.
CREATE OR REPLACE FUNCTION public.notify_report_filed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_recipient uuid;
  v_label text;
BEGIN
  -- reports.reporter_id is a raw auth uid; notifications.recipient_id FKs to
  -- users.id. Resolving through users.auth_id is mandatory — comparing them
  -- directly matches nothing and the notification silently never appears.
  SELECT id INTO v_recipient FROM public.users WHERE auth_id = NEW.reporter_id;
  IF v_recipient IS NULL THEN
    RETURN NEW;
  END IF;

  v_label := public.report_target_label(NEW);

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  VALUES (
    v_recipient, 'report_filed',
    NULL,  -- never the reported author: reporting must not deanonymise
    NULL,  -- and never a post reference the reporter could reopen
    'minor',
    'Report received',
    'Thanks — we''re reviewing the ' || v_label || ' you reported.',
    jsonb_build_object('report_id', NEW.id, 'target', v_label,
                       'reason', COALESCE(NEW.reason, '')),
    'report_filed:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_report_filed() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_report_filed ON public.reports;
CREATE TRIGGER trg_notify_report_filed
  AFTER INSERT ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.notify_report_filed();

NOTIFY pgrst, 'reload schema';
