-- Explicit request: allow both @rvce.edu.in and @rvu.edu.in for signup.
-- This is the REAL enforcement (a BEFORE INSERT trigger on auth.users) —
-- AuthScreen's client-side check is just a friendlier error message and
-- was previously hardcoded to the single domain too (core/constants.dart).
create or replace function public.enforce_college_email_domain()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_required boolean := true;
begin
  select coalesce((value #>> '{}')::boolean, true) into v_required
  from public.app_config where key = 'require_college_email_domain';

  if v_required
     and lower(new.email) not like '%@rvce.edu.in'
     and lower(new.email) not like '%@rvu.edu.in'
  then
    raise exception 'Signups are currently restricted to @rvce.edu.in or @rvu.edu.in email addresses';
  end if;
  return new;
end;
$function$;
