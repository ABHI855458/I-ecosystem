-- 70 dedicated General post-prompts (10 per window x 7 windows), each with
-- 6 paired ping-prompts (3 photo + 3 text, pool='linked') so Tier 1 of
-- ping_prompts_for_post genuinely activates -- its own threshold is >=3
-- active rows per daily_prompt_id, and EVERY existing daily_prompt in the
-- whole system had zero rows meeting that bar before this (confirmed
-- live): the resolver code existed but nothing had ever populated it.
--
-- Checked against the entire existing prompt library (468 daily_prompts +
-- 3155 ping_prompts, all communities, all windows) and against each other
-- before writing this file -- zero exact-text collisions,
-- case/whitespace-insensitive. Does not retroactively touch anything that
-- already existed.
--
-- This is content, not a schema change -- generated body follows.

-- 70 dedicated General post-prompts (10 per window x 7 windows), each with
-- 6 paired ping-prompts (3 photo + 3 text, pool='linked') so Tier 1 of
-- ping_prompts_for_post genuinely activates (its own threshold is >=3 active
-- rows per daily_prompt_id -- every existing daily_prompt in this system had
-- ZERO rows meeting that bar before this, confirmed live: the resolver code
-- existed but nothing had ever actually populated it). weight=5, prompt_kind
-- alternation and the linked/daily_prompt_id pairing all match the small
-- amount of pre-existing 'linked' data found on inspection.
--
-- Checked against the ENTIRE existing prompt library before writing this file
-- (468 daily_prompts + 3155 ping_prompts, all communities, all windows) and
-- against each other -- zero exact-text collisions, case/whitespace-
-- insensitive. Does not retroactively deduplicate anything that already
-- existed before this migration.
DO $$
DECLARE
  v_general_id uuid;
  v_prompt_id uuid;
BEGIN
  SELECT id INTO v_general_id FROM public.communities WHERE name = 'General' LIMIT 1;
  IF v_general_id IS NULL THEN
    RAISE EXCEPTION 'General community not found -- aborting';
  END IF;

  -- ===== pre_class =====
  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Your 8am attendance today — real or ghosted?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me your bedhead right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your ID card photo, no warning', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me exactly how late you are', true, v_prompt_id, 'linked', 'photo', 5),
    ('Did you actually attend or is this a rerun?', true, v_prompt_id, 'linked', 'text', 5),
    ('Be honest, did you sleep through the alarm?', true, v_prompt_id, 'linked', 'text', 5),
    ('What''s your excuse this time?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate your bedhead right now, no mirror check first.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the damage, unfiltered', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your hair right this second', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your reflection, anywhere', true, v_prompt_id, 'linked', 'photo', 5),
    ('On a scale of birds-nest, how bad is it?', true, v_prompt_id, 'linked', 'text', 5),
    ('Did you even try to fix it?', true, v_prompt_id, 'linked', 'text', 5),
    ('Comb or no comb today?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What did breakfast actually look like today?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me what''s left of it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the canteen line for breakfast', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your plate, guilt and all', true, v_prompt_id, 'linked', 'photo', 5),
    ('Did you skip it again?', true, v_prompt_id, 'linked', 'text', 5),
    ('What''s the real breakfast of champions here?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth waking up early for?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The state of your bag on a Monday morning.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me what''s actually inside', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the mystery item at the bottom', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me how many books you didn''t need', true, v_prompt_id, 'linked', 'photo', 5),
    ('How many textbooks are dead weight right now?', true, v_prompt_id, 'linked', 'text', 5),
    ('What''s the one thing you always forget?', true, v_prompt_id, 'linked', 'text', 5),
    ('Zipper holding on or not?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Which professor''s first class nobody survives awake?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the sleepiest row in class', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your notes mid-class, be honest', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the clock, how slow is it moving', true, v_prompt_id, 'linked', 'photo', 5),
    ('Who''s actually taking notes right now?', true, v_prompt_id, 'linked', 'text', 5),
    ('Front row or strategic back row today?', true, v_prompt_id, 'linked', 'text', 5),
    ('How many people dozed off already?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me exactly how late you are right now.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me your running-in shot', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the entrance you''re sprinting toward', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the time on your phone', true, v_prompt_id, 'linked', 'photo', 5),
    ('Walking fast or full sprint today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Is this a new record?', true, v_prompt_id, 'linked', 'text', 5),
    ('Did you make it or not?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Your commute view this morning, however boring.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the view, traffic and all', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your ride, bus, bike or on foot', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the queue at the gate', true, v_prompt_id, 'linked', 'photo', 5),
    ('Bus, bike, or on foot today?', true, v_prompt_id, 'linked', 'text', 5),
    ('How long did it actually take?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worst part of the commute today?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('First thing you actually saw walking into class.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it, whatever it was', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the empty seats up front', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me who beat you to class', true, v_prompt_id, 'linked', 'photo', 5),
    ('Was it as boring as expected?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anyone actually early today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Board already full or still blank?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate the parking chaos outside your block today.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the scene right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me how you squeezed your bike in', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the worst-parked vehicle', true, v_prompt_id, 'linked', 'photo', 5),
    ('Is it worse than yesterday?', true, v_prompt_id, 'linked', 'text', 5),
    ('Did you even find a spot?', true, v_prompt_id, 'linked', 'text', 5),
    ('Who''s blocking everyone in today?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What''s actually playing in your ears right now?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['pre_class'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me your lock screen right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the walk with the volume up', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your earphones, tangled or not', true, v_prompt_id, 'linked', 'photo', 5),
    ('What''s the song, no judgment?', true, v_prompt_id, 'linked', 'text', 5),
    ('Podcast or playlist this morning?', true, v_prompt_id, 'linked', 'text', 5),
    ('Loud enough to ignore everyone?', true, v_prompt_id, 'linked', 'text', 5);

  -- ===== snack =====
  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What''s in your hand right now, snack edition.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the snack, full reveal', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the wrapper evidence', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me it before it disappears', true, v_prompt_id, 'linked', 'photo', 5),
    ('Worth the price or not?', true, v_prompt_id, 'linked', 'text', 5),
    ('Shared or hoarded?', true, v_prompt_id, 'linked', 'text', 5),
    ('Would you buy it again?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The canteen queue at this hour — rate the chaos.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the line right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me how far back you are', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the front of the queue', true, v_prompt_id, 'linked', 'photo', 5),
    ('Worth the wait or not?', true, v_prompt_id, 'linked', 'text', 5),
    ('How long have you been standing there?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anyone cutting the line today?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Maggi or samosa — settle it once and for all.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me your actual pick', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the plate, no lying', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the counter right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Final answer, no switching sides.', true, v_prompt_id, 'linked', 'text', 5),
    ('Which one''s actually better here?', true, v_prompt_id, 'linked', 'text', 5),
    ('Both or loyal to one?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me who you''re bunking this class with.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the accomplice', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me where you''re hiding out', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the empty classroom you left behind', true, v_prompt_id, 'linked', 'photo', 5),
    ('Worth skipping for?', true, v_prompt_id, 'linked', 'text', 5),
    ('Is this becoming a habit?', true, v_prompt_id, 'linked', 'text', 5),
    ('Who''s the mastermind behind this?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Your notes from the class you just walked out of.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the notebook page', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me how much you actually wrote', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the doodles instead of notes', true, v_prompt_id, 'linked', 'photo', 5),
    ('Actual notes or just doodles?', true, v_prompt_id, 'linked', 'text', 5),
    ('Will you even read this later?', true, v_prompt_id, 'linked', 'text', 5),
    ('Borrowed from someone or original?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Worst vending machine choice on this campus?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the machine itself', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your regretful pick', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the empty slot everyone avoids', true, v_prompt_id, 'linked', 'photo', 5),
    ('Would you actually eat it again?', true, v_prompt_id, 'linked', 'text', 5),
    ('Still stocked or permanently empty?', true, v_prompt_id, 'linked', 'text', 5),
    ('Price worth the risk?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me the closest chai stall right now.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the stall, steam and all', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your cup, half-drunk or full', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the crowd around it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Strong or watered down today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth the walk to get there?', true, v_prompt_id, 'linked', 'text', 5),
    ('Regular or extra sugar?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What class are you supposed to be in right now?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me where you actually are instead', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the empty seat you''re missing', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your alibi', true, v_prompt_id, 'linked', 'photo', 5),
    ('Is anyone covering for you?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth missing it for this?', true, v_prompt_id, 'linked', 'text', 5),
    ('How''s the guilt level right now?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate today''s canteen menu, absolutely no mercy.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the menu board', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your plate, honest review', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the one dish nobody''s touching', true, v_prompt_id, 'linked', 'photo', 5),
    ('Best thing on offer today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worst thing on offer today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Would you eat here again tomorrow?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The one snack that''s always sold out by now.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['snack'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the empty shelf', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your backup choice instead', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me whoever got the last one', true, v_prompt_id, 'linked', 'photo', 5),
    ('Did you get to it in time?', true, v_prompt_id, 'linked', 'text', 5),
    ('What''s your backup plan?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth waking up earlier for it?', true, v_prompt_id, 'linked', 'text', 5);

  -- ===== lunch =====
  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Your lunch tray, completely unfiltered.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the full tray', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the one thing you''re avoiding on it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me it halfway finished', true, v_prompt_id, 'linked', 'photo', 5),
    ('Rate it out of 10, no rounding up.', true, v_prompt_id, 'linked', 'text', 5),
    ('Would you order this again?', true, v_prompt_id, 'linked', 'text', 5),
    ('Best or worst part of the plate?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Hottest take about the canteen food right now?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the dish in question', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your actual reaction to it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the receipt', true, v_prompt_id, 'linked', 'photo', 5),
    ('Overpriced or worth it?', true, v_prompt_id, 'linked', 'text', 5),
    ('Would you defend this take publicly?', true, v_prompt_id, 'linked', 'text', 5),
    ('Who''s going to disagree with you?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Who are you actually sitting with at lunch today?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the table, everyone included', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the seat you claimed', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the view from where you''re sitting', true, v_prompt_id, 'linked', 'photo', 5),
    ('Regular crew or random today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anyone missing from the usual group?', true, v_prompt_id, 'linked', 'text', 5),
    ('Loud table or quiet one today?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate your canteen bill for today, be honest.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the receipt itself', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what actually cost that much', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your wallet after this', true, v_prompt_id, 'linked', 'photo', 5),
    ('Worth every rupee or not?', true, v_prompt_id, 'linked', 'text', 5),
    ('Over budget again today?', true, v_prompt_id, 'linked', 'text', 5),
    ('What did you actually splurge on?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me the table you always end up at.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it, occupied or empty', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me who''s already sitting there', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the view from that exact spot', true, v_prompt_id, 'linked', 'photo', 5),
    ('Is it always this crowded?', true, v_prompt_id, 'linked', 'text', 5),
    ('Reserved unofficially by your group?', true, v_prompt_id, 'linked', 'text', 5),
    ('Best table on campus or not?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Worst thing you''ve seen someone microwave here.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the crime scene', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the smell''s source, if you dare', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the microwave queue right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Did the smell clear the room?', true, v_prompt_id, 'linked', 'text', 5),
    ('Would you ever try it yourself?', true, v_prompt_id, 'linked', 'text', 5),
    ('Who''s the repeat offender?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Most overrated course in your branch, no filter.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the textbook you resent', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your notes for it, or lack of', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the syllabus page you dread', true, v_prompt_id, 'linked', 'photo', 5),
    ('Would you drop it if you could?', true, v_prompt_id, 'linked', 'text', 5),
    ('Does anyone actually enjoy it?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth the credits or not?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The lunch queue right now, be completely honest.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me exactly how long it is', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your spot in line', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the front, how far away it looks', true, v_prompt_id, 'linked', 'photo', 5),
    ('Worth the wait today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Is it moving at all?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anyone skipping the line again?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What did you actually manage to finish eating?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the empty plate, if it exists', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what''s left uneaten', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the leftovers going to waste', true, v_prompt_id, 'linked', 'photo', 5),
    ('Clean plate club or not today?', true, v_prompt_id, 'linked', 'text', 5),
    ('What defeated you halfway through?', true, v_prompt_id, 'linked', 'text', 5),
    ('Packing the rest for later?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate the AC in whichever room you''re stuck in.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['lunch'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the room, sweating or freezing', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the thermostat, if there is one', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me everyone''s reaction to the temperature', true, v_prompt_id, 'linked', 'photo', 5),
    ('Too hot or too cold right now?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anyone brave enough to touch the AC remote?', true, v_prompt_id, 'linked', 'text', 5),
    ('Surviving or suffering in there?', true, v_prompt_id, 'linked', 'text', 5);

  -- ===== day_end =====
  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Your energy level right now, in one photo.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me exactly how you feel', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your face, no filter', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your posture right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Running on fumes or still fine?', true, v_prompt_id, 'linked', 'text', 5),
    ('What''s keeping you awake at this point?', true, v_prompt_id, 'linked', 'text', 5),
    ('Honest energy rating, 1 to dead.', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What''s still left in your bag from this morning?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the untouched items', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what you never even opened', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the bag, unpacked and honest', true, v_prompt_id, 'linked', 'photo', 5),
    ('Anything you carried around for nothing?', true, v_prompt_id, 'linked', 'text', 5),
    ('Did you use even half of it today?', true, v_prompt_id, 'linked', 'text', 5),
    ('What''s the deadest weight in there?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me your last class of the day, survived or not.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the room, empty or full', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the board at the end of class', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your seat as you''re leaving', true, v_prompt_id, 'linked', 'photo', 5),
    ('Did you actually stay awake for it?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worst class of the day, was it this one?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anyone else looking as done as you?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The walk from your last class — rate the distance.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the walk itself', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me how far you''ve got left', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your shoes after this', true, v_prompt_id, 'linked', 'photo', 5),
    ('Is it always this far?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth complaining about again?', true, v_prompt_id, 'linked', 'text', 5),
    ('Fastest route or the long way today?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Which subject drained you the most today?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the notebook that broke you', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your face after that class', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the textbook you''re avoiding now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Would you rewind and skip it if you could?', true, v_prompt_id, 'linked', 'text', 5),
    ('Did anyone actually follow along?', true, v_prompt_id, 'linked', 'text', 5),
    ('Homework from it yet, or spared today?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Whatever''s closest to your left hand right now.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it exactly as it is', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the mess around it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your hand next to it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Any idea how it got there?', true, v_prompt_id, 'linked', 'text', 5),
    ('Useful or completely random?', true, v_prompt_id, 'linked', 'text', 5),
    ('Has it been there all day?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What''s actually in your water bottle at this point?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the bottle, honest levels', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me if it''s still full or long empty', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what you refilled it with, if anything', true, v_prompt_id, 'linked', 'photo', 5),
    ('Water or something else entirely?', true, v_prompt_id, 'linked', 'text', 5),
    ('Refilled today or running on hope?', true, v_prompt_id, 'linked', 'text', 5),
    ('Empty since when, be honest?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate today''s classes, 1 to why-did-I-even-attend.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me proof you were actually there', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your notes as evidence', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your face reviewing the day', true, v_prompt_id, 'linked', 'photo', 5),
    ('Best class of the day, if any?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worst one, no contest?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth setting the alarm for tomorrow?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me your seat right now, wherever you are.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the exact spot', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the view from it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me who''s next to you', true, v_prompt_id, 'linked', 'photo', 5),
    ('Comfortable or making do?', true, v_prompt_id, 'linked', 'text', 5),
    ('How long have you been sitting here?', true, v_prompt_id, 'linked', 'text', 5),
    ('Planning on moving anytime soon?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The most useless thing you carried around all day.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['day_end'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the guilty item', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your bag giving it up', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me it, still unused', true, v_prompt_id, 'linked', 'photo', 5),
    ('Why did you even bring it?', true, v_prompt_id, 'linked', 'text', 5),
    ('Using it tomorrow or leaving it home?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth the extra weight?', true, v_prompt_id, 'linked', 'text', 5);

  -- ===== evening =====
  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me wherever you are right now, no context.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the exact spot, unexplained', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the view around you', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what you''re doing there', true, v_prompt_id, 'linked', 'photo', 5),
    ('Where even is this?', true, v_prompt_id, 'linked', 'text', 5),
    ('Planned or random detour?', true, v_prompt_id, 'linked', 'text', 5),
    ('How long are you staying here?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Gym, club, or straight to the room — pick one.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the choice you actually made', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the proof, wherever you ended up', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your gear, used or untouched', true, v_prompt_id, 'linked', 'photo', 5),
    ('Honest reason for skipping the others?', true, v_prompt_id, 'linked', 'text', 5),
    ('Same choice as yesterday?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth it or lazy option today?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What''s actually for dinner tonight, honestly?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the plate', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the mess in the kitchen', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the ingredients, if any', true, v_prompt_id, 'linked', 'photo', 5),
    ('Homemade, mess food, or ordered in?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth waiting for or rushed?', true, v_prompt_id, 'linked', 'text', 5),
    ('Rate it before you even taste it.', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate today''s workout, or the lack of one.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the proof, sweat or excuse', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the gym, empty or packed', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your gear, used or not', true, v_prompt_id, 'linked', 'photo', 5),
    ('Did you actually show up today?', true, v_prompt_id, 'linked', 'text', 5),
    ('What''s the excuse this time?', true, v_prompt_id, 'linked', 'text', 5),
    ('Sore tomorrow or nothing happened?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me your hostel room in its current state.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the full damage', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the corner you''re avoiding', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your roommate''s side too', true, v_prompt_id, 'linked', 'photo', 5),
    ('Cleaning it tonight or never?', true, v_prompt_id, 'linked', 'text', 5),
    ('Whose mess is whose at this point?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worst corner of the room right now?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Which club meeting are you skipping tonight?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me where you are instead', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your actual excuse', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the group chat you''re ignoring', true, v_prompt_id, 'linked', 'photo', 5),
    ('Real reason or convenient one?', true, v_prompt_id, 'linked', 'text', 5),
    ('Making it up next time?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anyone covering for you?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The most chaotic thing happening on campus right now.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it, live and unfiltered', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me who''s involved', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the aftermath, if any', true, v_prompt_id, 'linked', 'photo', 5),
    ('Worth getting involved in?', true, v_prompt_id, 'linked', 'text', 5),
    ('Who started this exactly?', true, v_prompt_id, 'linked', 'text', 5),
    ('Is this a regular occurrence?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Your screen right now, whatever tab is actually open.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the screen exactly as is', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the most embarrassing tab', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me how many tabs are open', true, v_prompt_id, 'linked', 'photo', 5),
    ('Productive or pure distraction?', true, v_prompt_id, 'linked', 'text', 5),
    ('How many tabs are actually necessary?', true, v_prompt_id, 'linked', 'text', 5),
    ('Would you want anyone else seeing this?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me the view from wherever you''re sitting.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it, unedited', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what''s directly in front of you', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the noise around you, somehow', true, v_prompt_id, 'linked', 'photo', 5),
    ('Peaceful or total chaos there?', true, v_prompt_id, 'linked', 'text', 5),
    ('Planning to move soon?', true, v_prompt_id, 'linked', 'text', 5),
    ('Best seat in the house or not?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate your commute home today, day scholars.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['evening'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the traffic, if any', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your ride, whatever it is', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the view out the window', true, v_prompt_id, 'linked', 'photo', 5),
    ('Faster or slower than usual?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worst part of the ride today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth leaving campus later next time?', true, v_prompt_id, 'linked', 'text', 5);

  -- ===== last_call =====
  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Who are you actually with right now?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the group, no warning', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the room you''re in', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me whatever you''re doing together', true, v_prompt_id, 'linked', 'photo', 5),
    ('Planned hangout or accidental one?', true, v_prompt_id, 'linked', 'text', 5),
    ('How did tonight even happen?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anyone missing who should be here?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate tonight''s hostel mess dinner, no mercy.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the tray, full damage', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what you actually finished', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the mess hall right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Would you eat it again tomorrow?', true, v_prompt_id, 'linked', 'text', 5),
    ('Best dish on the menu tonight?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worst dish, no contest?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me your study setup, real or completely fake.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the desk exactly as is', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the book that''s just for show', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what you''re actually doing instead', true, v_prompt_id, 'linked', 'photo', 5),
    ('Studying or pretending to?', true, v_prompt_id, 'linked', 'text', 5),
    ('How long did this setup last?', true, v_prompt_id, 'linked', 'text', 5),
    ('Real progress or just vibes?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The last message you sent, no context needed.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me your screen, brave enough?', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me who you''re texting', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the reply you''re waiting on', true, v_prompt_id, 'linked', 'photo', 5),
    ('Regret sending it yet?', true, v_prompt_id, 'linked', 'text', 5),
    ('Getting a reply anytime soon?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth the risk of showing this?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What''s actually playing right now, be honest.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me your screen or speaker', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me who else is listening', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the volume level', true, v_prompt_id, 'linked', 'photo', 5),
    ('Guilty pleasure or proud pick?', true, v_prompt_id, 'linked', 'text', 5),
    ('On repeat or random today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Would you admit this in public?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me your roommate''s side of the room right now.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it, full honesty', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the worst corner over there', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me if they''d approve of this photo', true, v_prompt_id, 'linked', 'photo', 5),
    ('Messier than your side or not?', true, v_prompt_id, 'linked', 'text', 5),
    ('Would they be okay with this photo?', true, v_prompt_id, 'linked', 'text', 5),
    ('Whose side wins tonight?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Worst excuse someone gave for skipping today?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me proof, if it exists', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the group chat evidence', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your own reaction to it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Did anyone actually believe it?', true, v_prompt_id, 'linked', 'text', 5),
    ('Better excuse than yours today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth calling them out on it?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate your productivity today, 1 to absolutely nothing.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the evidence, if any', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your to-do list, untouched or not', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what actually got done', true, v_prompt_id, 'linked', 'photo', 5),
    ('Anything crossed off the list today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Tomorrow''s the day it changes, right?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worst distraction of the day?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me whatever''s open on your desk right now.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the desk chaos, unfiltered', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the one thing that shouldn''t be there', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what you''re ignoring on it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Work, distraction, or both at once?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anything urgent actually happening there?', true, v_prompt_id, 'linked', 'text', 5),
    ('Since when has it looked like this?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The one assignment you''re pretending doesn''t exist.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['last_call'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it, still untouched', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the deadline, if you dare', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your current plan, if any', true, v_prompt_id, 'linked', 'photo', 5),
    ('Due when, exactly?', true, v_prompt_id, 'linked', 'text', 5),
    ('Starting tonight or tomorrow''s problem?', true, v_prompt_id, 'linked', 'text', 5),
    ('Anyone else in the same boat?', true, v_prompt_id, 'linked', 'text', 5);

  -- ===== wind_down =====
  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Your battery percentage plus what you''re doing.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the screen, percentage and all', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what''s draining it right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the charger, in reach or not', true, v_prompt_id, 'linked', 'photo', 5),
    ('Making it through the night or not?', true, v_prompt_id, 'linked', 'text', 5),
    ('Charging soon or running it to zero?', true, v_prompt_id, 'linked', 'text', 5),
    ('What''s actually using all that battery?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me your bed right now, mid-scroll.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it exactly as is', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what''s actually in your hand', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the mess around you', true, v_prompt_id, 'linked', 'photo', 5),
    ('How long have you been lying here?', true, v_prompt_id, 'linked', 'text', 5),
    ('Actually tired or just delaying sleep?', true, v_prompt_id, 'linked', 'text', 5),
    ('What are you scrolling through right now?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What are you actually doing instead of sleeping?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it, no judgment', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the screen keeping you up', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the time right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Worth staying up for?', true, v_prompt_id, 'linked', 'text', 5),
    ('Regretting it already?', true, v_prompt_id, 'linked', 'text', 5),
    ('When did you plan to actually stop?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Rate today, one word, no explaining further.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me a photo that sums it up', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your face right now, honest reaction', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the last thing that happened today', true, v_prompt_id, 'linked', 'photo', 5),
    ('Best part of today?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worst part, no sugarcoating?', true, v_prompt_id, 'linked', 'text', 5),
    ('Tomorrow better or worse, your guess?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('The last tab you have open before you sleep.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it exactly', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me how many tabs are still open', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the one you''ll forget about tomorrow', true, v_prompt_id, 'linked', 'photo', 5),
    ('Closing it tonight or leaving it for later?', true, v_prompt_id, 'linked', 'text', 5),
    ('Work or pure procrastination?', true, v_prompt_id, 'linked', 'text', 5),
    ('Would you want anyone seeing this?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me the ceiling you''re about to stare at.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it, exactly as it looks', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the room around it too', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me whatever''s stuck up there', true, v_prompt_id, 'linked', 'photo', 5),
    ('Anything interesting up there tonight?', true, v_prompt_id, 'linked', 'text', 5),
    ('How long until you actually fall asleep?', true, v_prompt_id, 'linked', 'text', 5),
    ('Same ceiling as every other night?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('What time did you actually plan to sleep tonight?', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the clock right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me proof you''re nowhere near sleep', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me what''s keeping you up instead', true, v_prompt_id, 'linked', 'photo', 5),
    ('Way past it already, aren''t you?', true, v_prompt_id, 'linked', 'text', 5),
    ('Tomorrow''s alarm, are you ready for it?', true, v_prompt_id, 'linked', 'text', 5),
    ('Who else is still up right now?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Your charger situation right now, be honest.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me it, tangled or missing', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the outlet you''re fighting for', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your phone''s battery right now', true, v_prompt_id, 'linked', 'photo', 5),
    ('Found it or still searching?', true, v_prompt_id, 'linked', 'text', 5),
    ('Shared charger drama tonight?', true, v_prompt_id, 'linked', 'text', 5),
    ('Making it to morning on this charge?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('Show me whatever woke you up scrolling again.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me the notification', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your screen, exactly as it is', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me the time you actually checked it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Worth losing sleep over?', true, v_prompt_id, 'linked', 'text', 5),
    ('Replying now or tomorrow?', true, v_prompt_id, 'linked', 'text', 5),
    ('How many times has this happened this week?', true, v_prompt_id, 'linked', 'text', 5);

  INSERT INTO public.daily_prompts
    (prompt_text, active, community_id, category, prompt_kind, weight, feed_scope, time_windows)
  VALUES ('One thing you''re dreading about tomorrow.', true, v_general_id, 'general', 'photo', 5, 'everyone', ARRAY['wind_down'])
  RETURNING id INTO v_prompt_id;

  INSERT INTO public.ping_prompts (prompt_text, active, daily_prompt_id, pool, prompt_kind, weight) VALUES
    ('Show me something that reminds you of it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your planner, if you even have one', true, v_prompt_id, 'linked', 'photo', 5),
    ('Show me your face just thinking about it', true, v_prompt_id, 'linked', 'photo', 5),
    ('Avoidable or definitely happening?', true, v_prompt_id, 'linked', 'text', 5),
    ('Prepared for it at all?', true, v_prompt_id, 'linked', 'text', 5),
    ('Worth losing sleep over tonight?', true, v_prompt_id, 'linked', 'text', 5);

END $$;