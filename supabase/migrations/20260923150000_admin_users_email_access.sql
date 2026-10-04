-- ROOT CAUSE of "permission denied for table users" on the dashboard's
-- Users page (reported by a global moderator, logged in, ADMIN badge
-- showing — this is NOT an authorization gap, the admin check itself is
-- fine).
--
-- users.email has column-level SELECT REVOKEd from `authenticated` (every
-- other column Users.jsx selects — id, auth_id, name, anon_name,
-- department, glow_score, streak, posted_today, created_at — still has
-- it). Postgres reports "permission denied for table X" at the TABLE
-- level even when only ONE referenced column lacks privilege, which is
-- why the error didn't name `email` specifically. RLS was never the
-- blocker: `users_select`'s qual is a bare `true`.
--
-- The email revoke itself is almost certainly deliberate privacy
-- hardening — it stops any ordinary authenticated app client from reading
-- another student's raw email via a crafted PostgREST call. That's
-- correct and is NOT reverted here. The dashboard's Users page has a
-- legitimate admin need to see it, and the page's own on-screen text
-- already states the intended architecture: "Admin access is granted via
-- the Team page (the real, RLS-enforced permission system), not a
-- per-user flag on this table." A column GRANT can't be conditional on
-- the caller being an admin — it's role-wide — so the correct channel is
-- a SECURITY DEFINER function gated on is_admin_or_global_mod(), which
-- already exists and is exactly what current_moderator_role()/the Team
-- page's own admin check already uses.
--
-- Moderators.jsx (`/team`) has the SAME latent bug in its own
-- users-by-email lookup (used to attach name/photo to a moderator row) —
-- just not yet noticed, since it only runs once the moderators list is
-- non-empty. Fixed here too, same pattern.

CREATE OR REPLACE FUNCTION public.admin_list_users(p_search text DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  auth_id uuid,
  email text,
  name text,
  anon_name text,
  department text,
  glow_score integer,
  -- streak -> daily_streak: `users.streak` is a dead legacy column that
  -- always reads 0 (confirmed elsewhere in this project — the real,
  -- running personal streak lives in daily_streak). Swapped here so the
  -- admin list shows the number that actually moves, rather than
  -- reproducing a known-wrong read in a brand-new function.
  daily_streak integer,
  posted_today boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT u.id, u.auth_id, u.email, u.name, u.anon_name, u.department,
         u.glow_score, u.daily_streak, u.posted_today, u.created_at
  FROM public.users u
  WHERE public.is_admin_or_global_mod()
    AND (
      p_search IS NULL OR btrim(p_search) = '' OR
      u.email ILIKE '%' || p_search || '%' OR
      u.name ILIKE '%' || p_search || '%' OR
      u.anon_name ILIKE '%' || p_search || '%'
    )
  ORDER BY u.created_at DESC;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_list_users(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_users_by_email(p_emails text[])
RETURNS TABLE(email text, name text, profile_photo_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT u.email, u.name, u.profile_photo_url
  FROM public.users u
  WHERE public.is_admin_or_global_mod()
    AND u.email = ANY(p_emails);
$function$;

GRANT EXECUTE ON FUNCTION public.admin_users_by_email(text[]) TO authenticated;
