-- Ping prompts: the user's own library, rotated daily (2026-09-27).
--
-- User ask: these prompts appear in the Friends feed and the Ping page
-- (headings "Friends" -> 1:1, "Groups" -> group pings), "use friends for
-- both", "don't put everything at once, create a cycle ... everyday a new
-- set", and "in anon, per prompt is different, let it be there".
--
-- * One Friends pool (scope 'everyone') now serves BOTH the Friends feed ping
--   sheet and the Ping page composer ('ping_page' resolves to it). Groups get
--   their own pool (scope 'group').
-- * rotating_ping_prompts(): each IST day everyone sees the same set of
--   app_settings.ping_prompt_limit prompts (6), taken as a moving window over
--   a fixed shuffled order, so the whole pool cycles before anything repeats
--   (Friends 48 -> 8 days, Groups 42 -> 7 days). Categories are interleaved
--   by the shuffle, so each day's set is mixed.
-- * Time-drop prompts (morning / lunch / golden hour / night / Friday) and
--   the Late-night group prompts carry a time_window and are added on top of
--   the day's set only while their window is open (max 2 at once).
-- * Anonymous prompts are untouched (scope 'anonymous', and tier-1
--   per-question sets for anonymous posts).
-- * The previous generic rows in these three scopes are deactivated, not
--   deleted; their ids are kept in ping_sheet_prompts_retired_20260927.
-- * Two prompts were shortened to fit ping_sheet_prompts_len (80 chars):
--   the zoom-in guess prompt and the spell-the-group-name chain prompt.
-- * Left out on purpose: "Wildcard drops" (need blind-swap / 3-second camera /
--   stitching features that don't exist) and "Exam week" (no exam calendar).

ALTER TABLE public.ping_sheet_prompts ADD COLUMN IF NOT EXISTS category text;
ALTER TABLE public.ping_sheet_prompts ADD COLUMN IF NOT EXISTS time_window text;

CREATE TABLE IF NOT EXISTS public.ping_sheet_prompts_retired_20260927 AS
  SELECT id FROM public.ping_sheet_prompts
   WHERE community_id IS NULL AND active AND scope IN ('everyone','ping_page','group');
ALTER TABLE public.ping_sheet_prompts_retired_20260927 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ping_sheet_prompts_retired_20260927 FROM anon, authenticated;

UPDATE public.ping_sheet_prompts SET active = false
 WHERE id IN (SELECT id FROM public.ping_sheet_prompts_retired_20260927);

INSERT INTO public.ping_sheet_prompts (scope, prompt_text, prompt_kind, category, time_window, active, sort_order)
SELECT v.scope, v.txt, 'photo', v.cat, v.win, true, 0
FROM (VALUES
  -- 👯 Friends (1:1): Camera, live right now
  ('everyone','camera',NULL,$p$Show me what you're looking at right this second. No cleanup allowed.$p$),
  ('everyone','camera',NULL,$p$Your hands, right now. Whatever they're holding.$p$),
  ('everyone','camera',NULL,$p$The view from where you're sitting. I'll guess where you are.$p$),
  ('everyone','camera',NULL,$p$Your shoes right now. Rate your day through them.$p$),
  ('everyone','camera',NULL,$p$Point the camera at the last thing that made you laugh.$p$),
  ('everyone','camera',NULL,$p$Something within arm's reach that reminds you of me.$p$),
  ('everyone','camera',NULL,$p$Your face after reading this prompt. First take only. 📸$p$),
  ('everyone','camera',NULL,$p$The ugliest thing near you. Make it look beautiful.$p$),
  ('everyone','camera',NULL,$p$What's on your plate (or desk, or bed) right now?$p$),
  ('everyone','camera',NULL,$p$Your sky right now. Let's see if we're under the same clouds.$p$),
  ('everyone','camera',NULL,$p$Your worst selfie angle, on purpose. Loser buys chai.$p$),
  ('everyone','camera',NULL,$p$Something that says "I'm fine" but isn't. Or is. You decide.$p$),
  -- 👯 Friends (1:1): Album, dig it up
  ('everyone','album',NULL,$p$The first photo of us together. Or the closest thing to it.$p$),
  ('everyone','album',NULL,$p$A photo from before we met that I'd never guess was you.$p$),
  ('everyone','album',NULL,$p$Scroll back exactly 1 year. Send whatever's there, no skipping.$p$),
  ('everyone','album',NULL,$p$A picture you took but never posted. Why not?$p$),
  ('everyone','album',NULL,$p$Your most chaotic screenshot. No context.$p$),
  ('everyone','album',NULL,$p$A photo that explains your personality better than words.$p$),
  ('everyone','album',NULL,$p$The photo you'd send if you were telling me "I miss you" without saying it.$p$),
  ('everyone','album',NULL,$p$Your childhood photo with the most main-character energy.$p$),
  ('everyone','album',NULL,$p$A place you want to take me. Show me the photo.$p$),
  ('everyone','album',NULL,$p$The last photo you took at night.$p$),
  ('everyone','album',NULL,$p$A photo of food you'd fight someone over.$p$),
  ('everyone','album',NULL,$p$Your camera roll's 100th photo. Brave enough?$p$),
  -- 🎯 Friends (1:1): Guess games
  ('everyone','guess',NULL,$p$Zoom in so close I can't tell what it is. One guess to name it.$p$),
  ('everyone','guess',NULL,$p$Snap where you are without showing any landmarks. One guess to find you.$p$),
  ('everyone','guess',NULL,$p$A photo from your gallery. I guess the year you took it.$p$),
  ('everyone','guess',NULL,$p$Your current mood as an object. I have to name the mood.$p$),
  ('everyone','guess',NULL,$p$Something you bought recently. I guess the price. Closest wins.$p$),
  ('everyone','guess',NULL,$p$A photo of your feet somewhere. I guess the place.$p$),
  ('everyone','guess',NULL,$p$Take a photo of your playlist screen, song names blurred. I guess one.$p$),
  ('everyone','guess',NULL,$p$The snack you're craving right now, shown only by its wrapper corner.$p$),
  -- 🔁 Friends (1:1): Twin sync
  ('everyone','twin',NULL,$p$Both of us, snap our left hand. Now. 🤚$p$),
  ('everyone','twin',NULL,$p$Both of us, show the ceiling above us.$p$),
  ('everyone','twin',NULL,$p$Show your window view. Let's compare our worlds.$p$),
  ('everyone','twin',NULL,$p$Snap the closest thing that's red.$p$),
  ('everyone','twin',NULL,$p$Show what's in your pocket or bag right now.$p$),
  ('everyone','twin',NULL,$p$Your phone's lock screen. No changing it first.$p$),
  ('everyone','twin',NULL,$p$The last thing you drank. Photo proof.$p$),
  ('everyone','twin',NULL,$p$Point the camera at the floor. Whose is messier?$p$),
  -- 💌 Friends (1:1): Soft ones
  ('everyone','soft',NULL,$p$Show me something that made your day slightly better.$p$),
  ('everyone','soft',NULL,$p$A song you'd dedicate to me. Screenshot it.$p$),
  ('everyone','soft',NULL,$p$A photo that feels like a hug.$p$),
  ('everyone','soft',NULL,$p$Something you'd give me if I were there right now.$p$),
  ('everyone','soft',NULL,$p$A picture from a day you felt really happy.$p$),
  ('everyone','soft',NULL,$p$Your comfort spot. Where do you go when you need a break?$p$),
  ('everyone','soft',NULL,$p$A photo of something you're proud of lately, however small.$p$),
  ('everyone','soft',NULL,$p$What does "home" look like for you? Show me.$p$),
  -- ⏰ Friends: time drops
  ('everyone','time_drop','morning',$p$Your first view after waking up. No filter, no mercy.$p$),
  ('everyone','time_drop','golden',$p$Catch the light wherever you are.$p$),
  ('everyone','time_drop','night',$p$What's keeping you up tonight?$p$),
  ('everyone','time_drop','friday',$p$What does your weekend look like, starting now?$p$),

  -- 🫂 Groups: Camera, everyone at once
  ('group','camera',NULL,$p$Drop in 60s: everyone shows where they are right now. 📍$p$),
  ('group','camera',NULL,$p$Canteen check: what's everyone eating?$p$),
  ('group','camera',NULL,$p$Show your desk. Messiest one owes the group a snack.$p$),
  ('group','camera',NULL,$p$Your view from the classroom window, or wherever you're hiding instead.$p$),
  ('group','camera',NULL,$p$Hostel room vs day-scholar room. Show us.$p$),
  ('group','camera',NULL,$p$Everyone snap the same thing: your water bottle.$p$),
  ('group','camera',NULL,$p$Last one in the group to post has to pick tomorrow's prompt.$p$),
  ('group','camera',NULL,$p$The sky from wherever you are. Group sunset map. 🌅$p$),
  ('group','camera',NULL,$p$Show your current "studying" setup. Be honest.$p$),
  ('group','camera',NULL,$p$Group face-off: your best "I understood the lecture" face.$p$),
  ('group','camera',NULL,$p$Something blue near you. Go. Fastest wins bragging rights.$p$),
  ('group','camera',NULL,$p$Your walk to class, in one photo.$p$),
  -- 🫂 Groups: Album, the memory vault
  ('group','album',NULL,$p$The last group photo you have with anyone. Explain.$p$),
  ('group','album',NULL,$p$Your pre-RVCE era in one photo.$p$),
  ('group','album',NULL,$p$School ID card energy. Let's see it. 😭$p$),
  ('group','album',NULL,$p$A trip photo that deserves a sequel.$p$),
  ('group','album',NULL,$p$The photo in your gallery that would make this group scream.$p$),
  ('group','album',NULL,$p$Your first week at RVCE in one picture.$p$),
  ('group','album',NULL,$p$A photo of a place in Bengaluru everyone should go to.$p$),
  ('group','album',NULL,$p$Your most unhinged photo from 2024.$p$),
  ('group','album',NULL,$p$A photo your parents took of you that you secretly love.$p$),
  ('group','album',NULL,$p$Something you made: food, art, code, chaos.$p$),
  ('group','album',NULL,$p$The best meal of your life, photographic evidence required.$p$),
  ('group','album',NULL,$p$A photo that makes you nostalgic for no reason.$p$),
  -- 🔥 Groups: Chain reactions
  ('group','chain',NULL,$p$Post a photo. Next person has to match its color.$p$),
  ('group','chain',NULL,$p$Snap an object. Next person finds something that rhymes with it.$p$),
  ('group','chain',NULL,$p$Post a place. Next person posts where they'd rather be.$p$),
  ('group','chain',NULL,$p$First person picks a shape (circle, triangle, square). Everyone finds one.$p$),
  ('group','chain',NULL,$p$Find a letter out in real life. Together, spell the group name.$p$),
  ('group','chain',NULL,$p$Post something old. Next person posts something newer. Keep going.$p$),
  ('group','chain',NULL,$p$Pass the vibe: next person's photo has to match your energy.$p$),
  ('group','chain',NULL,$p$Post a food. Next person posts its perfect pairing.$p$),
  -- 🏫 Groups: Campus life (RVCE edition)
  ('group','campus',NULL,$p$The most random corner of campus you've found.$p$),
  ('group','campus',NULL,$p$Show the queue you're stuck in right now.$p$),
  ('group','campus',NULL,$p$Your lab coat or ID card, styled with main-character energy.$p$),
  ('group','campus',NULL,$p$The best spot on campus for a nap. Evidence required. 😴$p$),
  ('group','campus',NULL,$p$What the Mysore Road traffic looks like from your commute.$p$),
  ('group','campus',NULL,$p$Your notebook's messiest page from this week.$p$),
  ('group','campus',NULL,$p$Canteen item you'd defend with your life.$p$),
  ('group','campus',NULL,$p$The tree, bench, or wall that's secretly "your spot."$p$),
  ('group','campus',NULL,$p$Show the whiteboard after the professor left.$p$),
  ('group','campus',NULL,$p$Your walk from the gate to class. One photo only.$p$),
  -- 🌙 Groups: Late night (10pm+), only shown at night
  ('group','late_night','night',$p$What's the last thing you're looking at before sleep?$p$),
  ('group','late_night','night',$p$Show your 2am snack. No shame zone.$p$),
  ('group','late_night','night',$p$Your screen time right now. We don't judge. (We do a little.)$p$),
  ('group','late_night','night',$p$The light that's still on in your room.$p$),
  ('group','late_night','night',$p$What song is on repeat tonight? Screenshot.$p$),
  ('group','late_night','night',$p$Show the view outside your window at night. 🌃$p$),
  ('group','late_night','night',$p$Something you're overthinking, shown as an object.$p$),
  ('group','late_night','night',$p$Your "going to sleep in 5 mins" setup, 45 mins later.$p$),
  -- ⏰ Groups: time drops
  ('group','time_drop','morning',$p$Your first view after waking up. No filter, no mercy.$p$),
  ('group','time_drop','lunch',$p$Your plate right now. The group votes on the "chef's kiss."$p$),
  ('group','time_drop','golden',$p$Catch the light wherever you are.$p$),
  ('group','time_drop','night',$p$What's keeping you up tonight?$p$),
  ('group','time_drop','friday',$p$What does your weekend look like, starting now?$p$)
) AS v(scope, cat, win, txt);

-- Is a time window open at this IST local time?
CREATE OR REPLACE FUNCTION public.prompt_time_window_active(p_window text, p_local timestamp)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE p_window
    WHEN 'morning' THEN p_local::time >= '07:00' AND p_local::time < '09:00'
    WHEN 'lunch'   THEN p_local::time >= '12:00' AND p_local::time < '14:00'
    WHEN 'golden'  THEN p_local::time >= '17:00' AND p_local::time < '18:30'
    WHEN 'night'   THEN p_local::time >= '22:00' OR p_local::time < '04:00'
    WHEN 'friday'  THEN extract(isodow FROM p_local) = 5
    ELSE false END;
$function$;

-- Today's set for a scope: open-window extras first (max 2), then the day's
-- slice of the cycle. 'ping_page' shares the Friends ('everyone') pool.
CREATE OR REPLACE FUNCTION public.rotating_ping_prompts(p_scope text, p_at timestamptz DEFAULT now())
 RETURNS TABLE(id uuid, prompt_text text, card_color text, prompt_kind text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_pool  text := CASE WHEN p_scope IN ('everyone','ping_page') THEN 'everyone' ELSE p_scope END;
  v_local timestamp := p_at AT TIME ZONE 'Asia/Kolkata';
  v_limit int;
  v_n     int;
  v_start int;
BEGIN
  SELECT COALESCE(value, 6) INTO v_limit FROM public.app_settings WHERE key = 'ping_prompt_limit';
  v_limit := COALESCE(v_limit, 6);

  RETURN QUERY
  SELECT sp.id, sp.prompt_text, sp.card_color, sp.prompt_kind
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL AND sp.active AND sp.scope = v_pool
     AND sp.time_window IS NOT NULL
     AND public.prompt_time_window_active(sp.time_window, v_local)
   ORDER BY md5(sp.id::text || v_local::date::text)
   LIMIT 2;

  SELECT count(*) INTO v_n
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL AND sp.active AND sp.scope = v_pool AND sp.time_window IS NULL;
  IF v_n = 0 THEN RETURN; END IF;

  v_start := ((v_local::date - DATE '2026-01-01') * v_limit) % v_n;
  IF v_start < 0 THEN v_start := v_start + v_n; END IF;

  RETURN QUERY
  WITH pool AS (
    SELECT sp.id, sp.prompt_text, sp.card_color, sp.prompt_kind,
           (row_number() OVER (ORDER BY md5(sp.prompt_text)) - 1)::int AS pos
      FROM public.ping_sheet_prompts sp
     WHERE sp.community_id IS NULL AND sp.active AND sp.scope = v_pool AND sp.time_window IS NULL
  )
  SELECT pool.id, pool.prompt_text, pool.card_color, pool.prompt_kind
    FROM pool
   WHERE (((pool.pos - v_start) % v_n) + v_n) % v_n < LEAST(v_limit, v_n)
   ORDER BY md5(pool.prompt_text || v_local::date::text);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ping_prompts_for_scope(p_scope text)
 RETURNS TABLE(id uuid, prompt_text text, card_color text, prompt_kind text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_limit int;
BEGIN
  IF p_scope IN ('everyone','ping_page','group') THEN
    RETURN QUERY SELECT * FROM public.rotating_ping_prompts(p_scope);
    IF FOUND THEN RETURN; END IF;
  END IF;

  SELECT COALESCE(value, 6) INTO v_limit FROM public.app_settings WHERE key = 'ping_prompt_limit';
  v_limit := COALESCE(v_limit, 6);

  RETURN QUERY
  SELECT sp.id, sp.prompt_text, sp.card_color, sp.prompt_kind
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL AND sp.active AND sp.scope = p_scope
   ORDER BY random()
   LIMIT v_limit;
  IF FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT sp.id, sp.prompt_text, sp.card_color, sp.prompt_kind
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL AND sp.active AND sp.scope = 'everyone'
   ORDER BY random()
   LIMIT v_limit;
END;
$function$;

-- Friends-feed (non-anonymous) posts now always offer the day's Friends set.
-- Anonymous posts keep their per-question sets (tier 1) and anon defaults.
CREATE OR REPLACE FUNCTION public.ping_prompts_for_post(p_post_id uuid)
 RETURNS TABLE(id uuid, prompt_text text, tier text, prompt_kind text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_author uuid; v_vis text; v_prompt uuid;
  v_limit int; v_tier1 int;
BEGIN
  SELECT COALESCE(value, 6) INTO v_limit FROM public.app_settings WHERE key = 'ping_prompt_limit';
  v_limit := COALESCE(v_limit, 6);

  SELECT p.user_id, p.visibility, p.prompt_id
    INTO v_author, v_vis, v_prompt
    FROM public.posts p
   WHERE p.id = p_post_id AND p.deleted_at IS NULL;

  IF v_author IS NULL THEN RETURN; END IF;

  IF v_vis IS DISTINCT FROM 'anonymous' THEN
    RETURN QUERY
    SELECT r.id, r.prompt_text, 'daily'::text, r.prompt_kind
      FROM public.rotating_ping_prompts('everyone') r;
    RETURN;
  END IF;

  -- Anonymous: the prompt-bar question's own set, if it is a real set.
  IF v_prompt IS NOT NULL THEN
    SELECT count(*) INTO v_tier1
      FROM public.ping_prompts pp
     WHERE pp.daily_prompt_id = v_prompt AND pp.active;

    IF COALESCE(v_tier1, 0) >= 3 THEN
      RETURN QUERY
      SELECT pp.id, pp.prompt_text, 'prompt'::text, pp.prompt_kind
        FROM public.ping_prompts pp
       WHERE pp.daily_prompt_id = v_prompt AND pp.active
       ORDER BY random()
       LIMIT v_limit;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT sp.id, sp.prompt_text, 'default'::text, sp.prompt_kind
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL AND sp.active AND sp.scope = 'anonymous'
   ORDER BY random()
   LIMIT v_limit;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.rotating_ping_prompts(text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rotating_ping_prompts(text, timestamptz) TO authenticated;
