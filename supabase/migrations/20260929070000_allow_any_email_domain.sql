-- Signup no longer requires an @rvce.edu.in/@rvu.edu.in email (user request
-- 2026-09-29: "remove the compulsory of rvce mail ... for normal mail the
-- otp is sent"). enforce_college_email_domain() already reads this flag
-- (safe-by-default: on) specifically so it could be turned off without a
-- code or trigger change — see that function's own doc
-- (20260907010000_branch_and_config.sql). Flipping it here is the whole fix
-- server-side; the OTP send path itself (Supabase Auth) was never
-- domain-gated, only this trigger was.
update public.app_config
   set value = 'false'::jsonb
 where key = 'require_college_email_domain';
