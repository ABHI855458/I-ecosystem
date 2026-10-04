-- Security audit fixes. Applied live as `fix_moderator_predicates_null_bypass`
-- and `lock_group_streaks_archive`.
--
-- 1) AUTH BYPASS in every moderator-gated function (HIGH).
--
-- The moderator predicates returned NULL, not false, for a non-moderator,
-- and every PL/pgSQL gate is written as:
--
--     IF NOT public.is_admin_or_global_mod() THEN
--       RAISE EXCEPTION 'not authorised';
--     END IF;
--
-- `NOT NULL` is NULL, which is not TRUE, so the branch is never taken and
-- execution falls through into the privileged body.
--
-- Root cause is three-valued logic, not a typo in any one gate:
-- current_moderator_role() returns NULL when the caller has no `moderators`
-- row, and `NULL IN ('admin','global_moderator')` is NULL, as is
-- `NULL = 'admin'`.
--
-- Verified as a signed-in NON-moderator, before the fix:
--     is_admin_or_global_mod()              -> NULL
--     broadcast_to_campus('AUDIT PROBE')    -> SUCCEEDED
-- i.e. any signed-in user could publish a campus-wide announcement and
-- notify every account, and could read every dashboard_* feed.
--
-- Fixed at the SOURCE (COALESCE(..., false) in the four predicates) rather
-- than in ~20 call sites: it corrects every existing gate at once and
-- cannot be forgotten the next time someone writes a new one.
--
-- Verified after, with real Supabase-shaped JWT claims (sub + email):
--     admin  abisheksdpatel@gmail.com  -> predicate true,  dashboard_feed OK
--     ordinary student                 -> predicate false, broadcast blocked
--
-- RLS policies using these helpers were NOT exploitable: a NULL in a USING
-- clause filters the row out, so it already behaved as false. Only the
-- PL/pgSQL `IF NOT ...` gates were affected.
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ SELECT COALESCE(current_moderator_role() = 'admin', false); $function$;

CREATE OR REPLACE FUNCTION public.is_admin_or_global_mod()
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT COALESCE(current_moderator_role() IN ('admin', 'global_moderator'), false);
$function$;

CREATE OR REPLACE FUNCTION public.is_community_moderator_for(target_community uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    current_moderator_role() = 'community_moderator'
      AND current_moderator_community_id() = target_community, false);
$function$;

CREATE OR REPLACE FUNCTION public.can_moderate_community(target_community uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    is_admin_or_global_mod() OR is_community_moderator_for(target_community), false);
$function$;

-- 2) Unprotected archive table (LOW, but real).
--
-- `group_streaks_archive_20260914` is a dated one-off backup from a streak
-- migration, living in `public` (so PostgREST exposes it) with NO row level
-- security. Verified: an ordinary signed-in user could read all 5 rows, 4 of
-- them other people's — group_id + user_id + streaks + last_dip_on, which
-- leaks group membership and per-user activity dates.
--
-- RLS on with NO policy = deny-all for anon/authenticated; service_role and
-- the owner keep access, so the rows survive for recovery.
ALTER TABLE public.group_streaks_archive_20260914 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.group_streaks_archive_20260914 FROM anon, authenticated;
