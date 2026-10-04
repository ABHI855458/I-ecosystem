-- Exact-match exception for the Play Store review account, which cannot hold
-- a college address but must be able to sign in for review. Equality, not
-- LIKE: no wildcard, no domain opened up. The @rvce.edu.in / @rvu.edu.in
-- rules are unchanged for every other address.
CREATE OR REPLACE FUNCTION public.enforce_college_email_domain()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_required boolean := true;
begin
  select coalesce((value #>> '{}')::boolean, true) into v_required
  from public.app_config where key = 'require_college_email_domain';

  if v_required
     and lower(new.email) <> 'playstore-review@useiapp.online'
     and lower(new.email) not like '%@rvce.edu.in'
     and lower(new.email) not like '%@rvu.edu.in'
  then
    raise exception 'Signups are currently restricted to @rvce.edu.in or @rvu.edu.in email addresses';
  end if;
  return new;
end;
$function$;
