-- Ping prompts had only two scopes, 'everyone' and 'anonymous'. The GROUP
-- feed's ping and the PING PAGE's own composer both passed no post id, so
-- both silently fell through to the 'everyone' set — a moderator editing
-- the friends-feed prompts was also, invisibly, editing the group and ping
-- page ones, and neither could be set on its own.
-- Explicit request: "for friends feed ping prompts and for group feed ping
-- prompts can be set and as well ping prompts for ping page can be set and
-- can be effectively seen, and the dashboard has complete control over it".
--
-- Two new scopes, each independently editable from the dashboard. Both
-- FALL BACK to 'everyone' when a moderator hasn't authored a set yet (see
-- ping_prompts_for_scope), so adding these cannot empty a picker that works
-- today — the app's own hardcoded list stays the last resort below that.
ALTER TABLE public.ping_sheet_prompts
  DROP CONSTRAINT IF EXISTS ping_sheet_prompts_scope_check;
ALTER TABLE public.ping_sheet_prompts
  ADD CONSTRAINT ping_sheet_prompts_scope_check
  CHECK (scope = ANY (ARRAY['everyone'::text, 'anonymous'::text, 'group'::text, 'ping_page'::text]));

-- Seed each new scope from the current 'everyone' set, so the dashboard
-- opens on a real, editable list rather than an empty one that silently
-- falls back.
INSERT INTO public.ping_sheet_prompts (scope, prompt_text, card_color, active, sort_order)
SELECT 'group', sp.prompt_text, sp.card_color, sp.active, sp.sort_order
  FROM public.ping_sheet_prompts sp
 WHERE sp.scope = 'everyone' AND sp.community_id IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.ping_sheet_prompts x WHERE x.scope = 'group');

INSERT INTO public.ping_sheet_prompts (scope, prompt_text, card_color, active, sort_order)
SELECT 'ping_page', sp.prompt_text, sp.card_color, sp.active, sp.sort_order
  FROM public.ping_sheet_prompts sp
 WHERE sp.scope = 'everyone' AND sp.community_id IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.ping_sheet_prompts x WHERE x.scope = 'ping_page');

-- The scope-only lookup, for every ping surface that has no post to key
-- off: the group feed, the group wall and the ping page.
--
-- Falls back to the 'everyone' set when the requested scope has no active
-- prompts, so an unconfigured scope degrades to today's behaviour instead
-- of to an empty picker.
CREATE OR REPLACE FUNCTION public.ping_prompts_for_scope(p_scope text)
 RETURNS TABLE(id uuid, prompt_text text, card_color text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_limit int;
BEGIN
  SELECT COALESCE(value, 6) INTO v_limit FROM public.app_settings WHERE key = 'ping_prompt_limit';
  v_limit := COALESCE(v_limit, 6);

  RETURN QUERY
  SELECT sp.id, sp.prompt_text, sp.card_color
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL AND sp.active AND sp.scope = p_scope
   ORDER BY sp.sort_order NULLS LAST, sp.created_at
   LIMIT v_limit;
  IF FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT sp.id, sp.prompt_text, sp.card_color
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL AND sp.active AND sp.scope = 'everyone'
   ORDER BY sp.sort_order NULLS LAST, sp.created_at
   LIMIT v_limit;
END;
$function$;
