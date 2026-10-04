-- Regenerates public.daily_prompts from the 2026-09-14 export.
-- Matches communities by name; skips any name not present.

INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Confess the most harmless thing you got away with', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What''s a small thing nobody knows about you?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What''s something you wish people understood about you?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What''s something you''ve never told anyone here?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Best hidden spot on campus, don''t gatekeep', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Biggest lie you''ve told to skip a class?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Hottest take about the canteen food?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Is the attendance policy actually fair? Go.', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Most overhyped fest event?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Most overrated course in your branch?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Most useless facility we''re paying for?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Settle it: which branch has it hardest?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What campus rule does literally everyone break?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What does everyone get wrong about your branch?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What''s a campus secret you''ll only say anonymously?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What''s a class everyone sleeps through?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What''s something our college pretends is great but isn''t?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What''s something you''ve never told anyone here?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('What''s the most overrated thing about our college?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Which branch thinks they''re superior but isn''t?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Which subject is a complete waste of time?', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Proof of what you were supposed to be doing right now.', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Show the exact spot you were sitting when you got your RVCE result.', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Something on this campus that shouldn''t still be there.', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('The most cursed thing in your bag.', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('The view from exactly where you''re sitting.', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Whatever is closest to your left hand.', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Your battery percentage + what you''re doing about it.', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
VALUES ('Your screen right now. No cleanup.', NULL, 'photo', 'everyone', true);
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the last thing you called home about.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '1st Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you brought from home that you haven''t used once.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '1st Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The first friend you made here. Just their hands or shoes.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '1st Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The senior advice that turned out to be a lie.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '1st Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The thing on campus you still can''t find.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '1st Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'What your hostel/desk looked like on day one vs. today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '1st Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your first-week self vs. now — one photo that shows the difference.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '1st Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your timetable, annotated with how you actually feel.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '1st Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the thing you finally learnt where everything is.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '2nd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show what you spend your free hour on now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '2nd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you own now that first-year you wouldn''t recognise.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '2nd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you were scared of in first year that''s routine now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '2nd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The first-year advice you''d actually give.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '2nd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The habit you picked up this year.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '2nd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your current desk vs. your first-year desk. One photo.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '2nd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your timetable — show the gap you actually live in.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '2nd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the tab you keep reopening.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '3rd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show what''s keeping you up lately.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '3rd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show where you work when it gets serious.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '3rd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The project that''s eating this semester.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '3rd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The thing you''re doing purely for placements.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '3rd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your calendar this week. Unedited.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '3rd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your prep setup, whatever stage it''s at.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '3rd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your resume on screen. Any version.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '3rd Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the place you''ve eaten at the most times.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '4th Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show what''s already packed.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '4th Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your desk in its final-year state.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '4th Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you''ve carried since first year.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '4th Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The spot on campus you''ll miss. Go stand there.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '4th Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The thing you still haven''t done here.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '4th Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your last-ever timetable.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '4th Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your project/thesis, whatever it looks like right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = '4th Year';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A structure on campus you have opinions about.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Aero';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show a machine you''re not fully sure how to use.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Aero';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you made with your hands this semester.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Aero';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The most over-engineered thing on campus.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Aero';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The workshop scar story — show the scar.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Aero';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your calculator. Yes, that one.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Aero';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your drawing sheet. Be honest about the smudges.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Aero';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your safety shoes after one lab.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Aero';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show a wire/board/device you''re building.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AI & ML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the project you abandoned.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AI & ML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The number of unread notifications on your dev tools.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AI & ML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The wildest bug you''ve hit this week.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AI & ML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your GitHub contribution graph. No excuses.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AI & ML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your most-used keyboard shortcut, demonstrated.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AI & ML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your rubber duck (or whatever you talk to).', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AI & ML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your terminal. Whatever''s on it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AI & ML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Screenshot the last thing you Googled about a lab.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AIML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your setup. Cable chaos included.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AIML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you wrote that you don''t understand anymore.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AIML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The error message that''s been up the longest.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AIML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The line of code you''re weirdly proud of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AIML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your code at 2am vs. your code at 2pm — one photo, you pick which.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AIML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your current tab situation.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AIML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your laptop stickers. Full frontal.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'AIML';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show a physical book you actually own.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Anime';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show where you watch/read on campus.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Anime';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your shelf, however chaotic.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Anime';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The recommendation that ruined you.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Anime';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The scene you rewind every time.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Anime';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your comfort rewatch, paused on your favourite frame.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Anime';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your current watch/read. Frame or cover.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Anime';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your watchlist, honestly long.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Anime';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A bruise with a story.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Badminton';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the teammate you''d pass to every time. Face or not.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Badminton';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your grip — bat, racquet, ball, whatever.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Badminton';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The ground/court, empty or full, right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Badminton';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The scoreboard from today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Badminton';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your kit bag, unfiltered.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Badminton';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your shoes after today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Badminton';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your warm-up spot.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Badminton';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A bruise with a story.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Basketball';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the teammate you''d pass to every time. Face or not.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Basketball';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your grip — bat, racquet, ball, whatever.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Basketball';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The ground/court, empty or full, right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Basketball';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The scoreboard from today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Basketball';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your kit bag, unfiltered.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Basketball';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your shoes after today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Basketball';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your warm-up spot.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Basketball';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A part you replaced yourself.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Bikers';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Engine bay / chain / whatever you''re most proud of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Bikers';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show something you fixed with the wrong tool.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Bikers';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your odometer.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Bikers';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The best road you''ve found near Bengaluru.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Bikers';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The dirtiest part of it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Bikers';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your helmet, wherever it''s sitting.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Bikers';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your machine. Any angle, right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Bikers';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the machine you had to be trained on twice.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Biotech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your gloves at the end of a session.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Biotech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something growing that shouldn''t be.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Biotech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The plate/slide you''re waiting on.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Biotech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Whatever''s in front of you on the bench.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Biotech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your goggles, wherever they''re sitting.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Biotech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your lab coat. Be honest about the stains.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Biotech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your lab notebook''s messiest entry.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Biotech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A structure on campus you have opinions about.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Chem';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show a machine you''re not fully sure how to use.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Chem';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you made with your hands this semester.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Chem';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The most over-engineered thing on campus.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Chem';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The workshop scar story — show the scar.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Chem';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your calculator. Yes, that one.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Chem';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your drawing sheet. Be honest about the smudges.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Chem';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your safety shoes after one lab.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Chem';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A structure on campus you have opinions about.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Civil';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show a machine you''re not fully sure how to use.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Civil';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you made with your hands this semester.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Civil';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The most over-engineered thing on campus.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Civil';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The workshop scar story — show the scar.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Civil';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your calculator. Yes, that one.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Civil';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your drawing sheet. Be honest about the smudges.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Civil';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your safety shoes after one lab.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Civil';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show a wire/board/device you''re building.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Coding / DSA';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the project you abandoned.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Coding / DSA';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The number of unread notifications on your dev tools.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Coding / DSA';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The wildest bug you''ve hit this week.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Coding / DSA';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your GitHub contribution graph. No excuses.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Coding / DSA';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your most-used keyboard shortcut, demonstrated.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Coding / DSA';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your rubber duck (or whatever you talk to).', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Coding / DSA';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your terminal. Whatever''s on it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Coding / DSA';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A bruise with a story.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Cricket';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the teammate you''d pass to every time. Face or not.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Cricket';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your grip — bat, racquet, ball, whatever.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Cricket';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The ground/court, empty or full, right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Cricket';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The scoreboard from today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Cricket';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your kit bag, unfiltered.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Cricket';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your shoes after today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Cricket';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your warm-up spot.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Cricket';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Screenshot the last thing you Googled about a lab.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'CSE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your setup. Cable chaos included.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'CSE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you wrote that you don''t understand anymore.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'CSE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The error message that''s been up the longest.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'CSE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The line of code you''re weirdly proud of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'CSE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your code at 2am vs. your code at 2pm — one photo, you pick which.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'CSE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your current tab situation.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'CSE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your laptop stickers. Full frontal.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'CSE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the corner of campus you rehearse in.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Dance';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your shoes mid-practice.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Dance';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something that hurt after a session.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Dance';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The mirror you practice in front of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Dance';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The move you''ve been failing at — one frozen frame.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Dance';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your costume from the last performance.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Dance';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your playlist for practice.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Dance';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your practice space, empty.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Dance';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your route''s worst 10 seconds.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you eat on the way.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The one thing that makes the commute worth it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The seat you fight for.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Traffic. Just traffic.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'What time you left home. Show the clock.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your bag''s full weight, visualized.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your view from the bus, right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your route''s worst 10 seconds.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar Commute';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you eat on the way.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar Commute';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The one thing that makes the commute worth it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar Commute';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The seat you fight for.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar Commute';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Traffic. Just traffic.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar Commute';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'What time you left home. Show the clock.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar Commute';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your bag''s full weight, visualized.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar Commute';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your view from the bus, right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Day Scholar Commute';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your component drawer or box.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ECE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your lab record''s worst page.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ECE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The circuit that worked once and never again.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ECE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The component you''ve burnt the most of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ECE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The soldering iron burn. Everyone has one.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ECE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your breadboard. Current state, wires and all.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ECE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your multimeter reading right now. Any reading.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ECE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your oscilloscope screen, whatever''s on it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ECE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your component drawer or box.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EEE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your lab record''s worst page.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EEE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The circuit that worked once and never again.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EEE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The component you''ve burnt the most of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EEE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The soldering iron burn. Everyone has one.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EEE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your breadboard. Current state, wires and all.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EEE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your multimeter reading right now. Any reading.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EEE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your oscilloscope screen, whatever''s on it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EEE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your component drawer or box.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EIE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your lab record''s worst page.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EIE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The circuit that worked once and never again.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EIE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The component you''ve burnt the most of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EIE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The soldering iron burn. Everyone has one.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EIE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your breadboard. Current state, wires and all.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EIE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your multimeter reading right now. Any reading.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EIE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your oscilloscope screen, whatever''s on it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'EIE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Chai/coffee in your hand.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Foodies';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show ₹50 worth of food near campus.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Foodies';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the place you go when mess food loses.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Foodies';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The canteen''s best-kept secret.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Foodies';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The snack in your bag right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Foodies';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'What you''re eating. Right now. No staging.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Foodies';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your midnight food setup.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Foodies';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your order, exactly as it always is.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Foodies';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A bruise with a story.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Football';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the teammate you''d pass to every time. Face or not.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Football';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your grip — bat, racquet, ball, whatever.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Football';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The ground/court, empty or full, right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Football';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The scoreboard from today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Football';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your kit bag, unfiltered.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Football';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your shoes after today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Football';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your warm-up spot.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Football';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your first-ever profile picture on any game.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (Mobile)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your hands mid-game.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (Mobile)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your rank. Own it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (Mobile)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The game you keep uninstalling and reinstalling.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (Mobile)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The teammate who carries you (their screen name).', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (Mobile)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your current game''s screen, paused.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (Mobile)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your longest session''s clock.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (Mobile)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your setup — phone, PC, whatever.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (Mobile)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your first-ever profile picture on any game.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (PC)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your hands mid-game.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (PC)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your rank. Own it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (PC)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The game you keep uninstalling and reinstalling.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (PC)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The teammate who carries you (their screen name).', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (PC)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your current game''s screen, paused.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (PC)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your longest session''s clock.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (PC)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your setup — phone, PC, whatever.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gaming (PC)';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'OVERRRATED COLLEGE PLACE', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'General';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the weight you''re on today. Not the max, today''s.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gym / Lifting';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your gym at its most crowded hour.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gym / Lifting';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you can do now that you couldn''t in June.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gym / Lifting';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The machine you avoid.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gym / Lifting';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The shoes you lift in.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gym / Lifting';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your 6am alarm screenshot.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gym / Lifting';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your post-workout meal.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gym / Lifting';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your water bottle situation.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Gym / Lifting';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show what 2am in this building sounds like — one photo that captures it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something that''s been borrowed and never returned.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The jugaad you''re most proud of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The mess food tonight. Rate it in the caption.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The wall above your bed.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'What''s in your bucket.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your room right now. No warning, no cleaning.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your roommate''s side vs. your side.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show what 2am in this building sounds like — one photo that captures it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel Life';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something that''s been borrowed and never returned.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel Life';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The jugaad you''re most proud of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel Life';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The mess food tonight. Rate it in the caption.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel Life';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The wall above your bed.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel Life';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'What''s in your bucket.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel Life';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your room right now. No warning, no cleaning.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel Life';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your roommate''s side vs. your side.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Hostel Life';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show something here that''s badly queued.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'IEM';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the process on campus you''d optimise first.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'IEM';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your notes from the last group project meeting.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'IEM';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The chart you''re weirdly proud of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'IEM';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The deadline on your wall or screen.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'IEM';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The spreadsheet you''re in right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'IEM';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your calculator or laptop, whichever you use more.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'IEM';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your team''s actual workload split, visualized however you want.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'IEM';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Screenshot the last thing you Googled about a lab.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ISE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your setup. Cable chaos included.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ISE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you wrote that you don''t understand anymore.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ISE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The error message that''s been up the longest.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ISE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The line of code you''re weirdly proud of.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ISE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your code at 2am vs. your code at 2pm — one photo, you pick which.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ISE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your current tab situation.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ISE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your laptop stickers. Full frontal.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'ISE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show what you''re eating at this hour.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Late Night Club';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show who else is still awake.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Late Night Club';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The tab you''re on at 2am.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Late Night Club';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The view out your window right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Late Night Club';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'What''s keeping you up. One photo.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Late Night Club';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your clock. Just the clock.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Late Night Club';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your screen brightness right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Late Night Club';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your third coffee of the night.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Late Night Club';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A structure on campus you have opinions about.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Mech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show a machine you''re not fully sure how to use.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Mech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something you made with your hands this semester.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Mech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The most over-engineered thing on campus.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Mech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The workshop scar story — show the scar.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Mech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your calculator. Yes, that one.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Mech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your drawing sheet. Be honest about the smudges.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Mech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your safety shoes after one lab.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Mech';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the group chat''s current running joke.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Memes';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your camera roll''s screenshot folder.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Memes';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something here that looks staged but isn''t.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Memes';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something on campus that''s already a meme.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Memes';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The last meme you saved. No curating.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Memes';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The meme you''ve reused too many times.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Memes';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your gallery''s oldest saved meme.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Memes';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your most-sent reaction image.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Memes';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show a physical book you actually own.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Movies & Series';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show where you watch/read on campus.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Movies & Series';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your shelf, however chaotic.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Movies & Series';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The recommendation that ruined you.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Movies & Series';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The scene you rewind every time.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Movies & Series';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your comfort rewatch, paused on your favourite frame.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Movies & Series';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your current watch/read. Frame or cover.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Movies & Series';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your watchlist, honestly long.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Movies & Series';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'hows your day', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'music ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A chord/riff you''re stuck on — photo of your hand on it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'music ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show where you go to play without being heard.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'music ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your most-played song''s album art and defend it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'music ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'What''s playing right now. Screenshot it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'music ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your headphones. The real condition.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'music ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your instrument where it''s currently sitting.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'music ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your practice corner.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'music ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your Spotify wrapped regret.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'music ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Feeding spot.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Pets & Strays';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show an animal doing something absurd.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Pets & Strays';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show who''s sleeping where they shouldn''t.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Pets & Strays';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The campus dog you''re loyal to.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Pets & Strays';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The cat that owns this building.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Pets & Strays';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The one that recognizes you.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Pets & Strays';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your pet at home — the photo in your gallery.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Pets & Strays';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your phone''s animal photo count.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Pets & Strays';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A photo you took that nobody liked but you love.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Photography';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show something ordinary made to look expensive.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Photography';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your gear, however humble.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Photography';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The best light on campus right now. Go find it.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Photography';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The same spot you always shoot, shot again.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Photography';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your camera roll''s most recent photo. No choosing.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Photography';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your editing screen mid-edit.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Photography';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your worst photo from a good day.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Photography';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show me your notes from the last prep session.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Placements & Prep';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show what you''re building.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Placements & Prep';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your 3am work session.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Placements & Prep';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The company sticker on your laptop.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Placements & Prep';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The whiteboard/notebook where the idea started.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Placements & Prep';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your LinkedIn photo vs. your actual face right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Placements & Prep';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your rejection count. Just the number.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Placements & Prep';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your resume''s current version number.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Placements & Prep';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the notice board nobody reads.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'RVCE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show what the parking looks like at this hour.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'RVCE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Something here that''s been broken the entire time you''ve been on campus.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'RVCE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The building you still take a wrong turn in.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'RVCE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The one bench everyone fights for.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'RVCE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The queue you''re standing in right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'RVCE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The spot on campus you''d defend in an argument.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'RVCE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Whatever the weather is doing right now, from where you are.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'RVCE';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'SHOW YOUR FAVIOURITE SPORT AS SUCH', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'sports ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'A bruise with a story.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'sports ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show the teammate you''d pass to every time. Face or not.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'sports ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your grip — bat, racquet, ball, whatever.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'sports ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The ground/court, empty or full, right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'sports ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The scoreboard from today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'sports ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your kit bag, unfiltered.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'sports ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your shoes after today.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'sports ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your warm-up spot.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'sports ';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show me your notes from the last prep session.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Startups';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show what you''re building.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Startups';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your 3am work session.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Startups';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The company sticker on your laptop.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Startups';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The whiteboard/notebook where the idea started.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Startups';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your LinkedIn photo vs. your actual face right now.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Startups';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your rejection count. Just the number.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Startups';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your resume''s current version number.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Startups';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show sunrise from wherever you were.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Trekking & Outdoors';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Show your shoes'' condition.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Trekking & Outdoors';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The bag you pack.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Trekking & Outdoors';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The blister/scrape/scar.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Trekking & Outdoors';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'The view you''d go back for.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Trekking & Outdoors';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your favourite spot within 100km.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Trekking & Outdoors';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your last trek''s summit photo.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Trekking & Outdoors';
INSERT INTO public.daily_prompts (prompt_text, community_id, prompt_kind, feed_scope, active)
SELECT 'Your water bottle at the end.', id, 'photo', 'everyone', true
  FROM public.communities WHERE name = 'Trekking & Outdoors';
