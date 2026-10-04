-- A like on a ping photo reaches the person who sent that photo right away
-- (user request 2026-09-29: "the like button shall reach the sender who sent
-- the ping photo"). ping_reply_liked is tier 'minor', and minor pushes were
-- only allowed in the wake/snack/lunch windows — a like at 19:36 IST sat until
-- 07:30 the next morning and then got folded into the wake digest. It now
-- goes out immediately, the same exemption ping_answered already has. Spam is
-- bounded by the notification's dedupe key (one per reactor per reply).
CREATE OR REPLACE FUNCTION public.push_allowed(p_tier text, p_type text, p_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_type IN ('ping_answered', 'ping_reply_liked') THEN TRUE
    WHEN p_tier = 'major'    THEN w <> 'quiet'
    WHEN p_tier = 'standard' THEN w IN ('wake_digest','pre_class','snack_peak','lunch_peak','day_end','evening','last_call')
    ELSE                          w IN ('wake_digest','snack_peak','lunch_peak')
  END
  FROM (SELECT public.notification_window(p_at) AS w) s;
$function$;
