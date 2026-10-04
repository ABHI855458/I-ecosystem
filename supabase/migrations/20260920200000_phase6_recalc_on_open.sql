-- PHASE 6: "recalculated on app open + daily batch".
--
-- record_daily_open() is already called by main_shell.dart on every app
-- open, so it is the natural hook — no new client call, no new RPC to
-- remember to fire.
--
-- The recalc runs BEFORE the "already paid today" early return, deliberately.
-- A returning dormant user has last_open_at set to today by their FIRST open
-- of the day; every subsequent open that day hits the early return. Putting
-- the recalc after it would work by luck on the first open and then stop —
-- and the case that matters most (a dormant user coming back, needing the
-- push suppression lifted) must not depend on which open of the day it is.
CREATE OR REPLACE FUNCTION public.record_daily_open()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid;
  v_last date;
begin
  v_me := public.current_user_id();
  if v_me is null then return 0; end if;

  select last_open_at into v_last from public.users where id = v_me;

  -- Stamp the open first so the segment is computed from today's fact.
  if v_last is distinct from current_date then
    update public.users set last_open_at = current_date where id = v_me;
  end if;

  -- Lifecycle, every open. Cheap (single row) and idempotent.
  perform public.recalc_lifecycle(v_me);

  if v_last = current_date then
    return 0;                                -- already paid today
  end if;

  update public.users set ping_score = ping_score + 2 where id = v_me;
  perform public.log_score_event(v_me, 'daily_open', 2);
  return 2;
end;
$function$;
