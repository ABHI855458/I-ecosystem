-- Ping prompts: instant, instinct, addictive (product request).
--
-- Audit of the live pools (107 prompts): every one was a PHOTO prompt, and
-- many asked for real effort — dig out a childhood photo, "before we met",
-- scroll back a year, "what home looks like", your best meal ever. Those
-- stall a reply. What gets answered in seconds: camera-roll pulls ("your
-- last photo"), front-cam-now dares, and 5-second text instincts.
--
-- So: retire the heavy ones (active=false, reversible) and add three kinds:
--   roll      camera-roll pulls, no skipping
--   instant   camera right now, no retakes
--   instinct  TEXT replies answerable in 5 seconds
-- The daily rotation (rotating_ping_prompts) mixes them automatically.

update public.ping_sheet_prompts set active = false
 where community_id is null and scope in ('everyone', 'group')
   and prompt_text in (
  -- Friends pool
  'The first photo of us together. Or the closest thing to it.',
  'A photo from before we met that I''d never guess was you.',
  'Your childhood photo with the most main-character energy.',
  'A place you want to take me. Show me the photo.',
  'The photo you''d send if you were telling me "I miss you" without saying it.',
  'A photo that explains your personality better than words.',
  'What does "home" look like for you? Show me.',
  'A picture from a day you felt really happy.',
  'Something you''d give me if I were there right now.',
  'A song you''d dedicate to me. Screenshot it.',
  'Your comfort spot. Where do you go when you need a break?',
  'A photo of something you''re proud of lately, however small.',
  'Your current mood as an object. I have to name the mood.',
  'Something that says "I''m fine" but isn''t. Or is. You decide.',
  'Scroll back exactly 1 year. Send whatever''s there, no skipping.',
  'A picture you took but never posted. Why not?',
  -- Group pool
  'School ID card energy. Let''s see it. 😭',
  'Your pre-RVCE era in one photo.',
  'A trip photo that deserves a sequel.',
  'Your first week at RVCE in one picture.',
  'A photo of a place in Bengaluru everyone should go to.',
  'A photo your parents took of you that you secretly love.',
  'Something you made: food, art, code, chaos.',
  'The best meal of your life, photographic evidence required.',
  'A photo that makes you nostalgic for no reason.',
  'Something you''re overthinking, shown as an object.',
  'Find a letter out in real life. Together, spell the group name.',
  'Snap an object. Next person finds something that rhymes with it.',
  'First person picks a shape (circle, triangle, square). Everyone finds one.',
  'Post something old. Next person posts something newer. Keep going.'
);

insert into public.ping_sheet_prompts (scope, category, prompt_kind, prompt_text) values
  -- ── Friends: camera-roll pulls ──
  ('everyone','roll','photo','Your camera roll''s last photo. No skipping, no deleting 👀'),
  ('everyone','roll','photo','Your 3rd most recent screenshot. Zero context.'),
  ('everyone','roll','photo','Your last selfie. Yes, the one you didn''t post.'),
  ('everyone','roll','photo','The 7th photo in your gallery right now. Go.'),
  ('everyone','roll','photo','Open your gallery, close your eyes, tap. Send it. No vetoes.'),
  ('everyone','roll','photo','Your most recent photo of food.'),
  ('everyone','roll','photo','The last photo you took of someone else. Who is it? 👀'),
  ('everyone','roll','photo','Your last blurry photo. We all have one.'),
  -- ── Friends: instant camera ──
  ('everyone','instant','photo','Front camera. Right now. No retakes 📸'),
  ('everyone','instant','photo','Whatever''s on your left. Snap it.'),
  ('everyone','instant','photo','Your face in 3 seconds. Go.'),
  ('everyone','instant','photo','Your battery % right now. Screenshot it 🔋'),
  ('everyone','instant','photo','Your screen time today. Screenshot. No hiding.'),
  ('everyone','instant','photo','The last thing you bought. Photo proof.'),
  ('everyone','instant','photo','Your most recent chat. Blur the name, show the vibe.'),
  -- ── Friends: 5-second instincts (text) ──
  ('everyone','instinct','text','First word that comes to mind when you see my name?'),
  ('everyone','instinct','text','Rate your day out of 10. No explaining.'),
  ('everyone','instinct','text','What are you doing right now? 5 words max.'),
  ('everyone','instinct','text','One emoji for your week. Just one.'),
  ('everyone','instinct','text','When did you last think about me? Be honest 👀'),
  ('everyone','instinct','text','Tea or coffee? Wrong answer ends this friendship ☕'),
  ('everyone','instinct','text','Last song you played. Just the name.'),
  ('everyone','instinct','text','Who did you last text before me? 👀'),
  ('everyone','instinct','text','Describe today using only a food.'),
  ('everyone','instinct','text','One thing you''re lowkey excited about?'),
  ('everyone','instinct','text','What''s the last thing that made you laugh?'),
  ('everyone','instinct','text','Sleep, food or scroll: what do you need right now?'),
  ('everyone','instinct','text','Say something nice about me. 3 words. Go.'),
  ('everyone','instinct','text','Your honest first impression of me. Now.'),
  -- ── Group: camera-roll pulls ──
  ('group','roll','photo','Everyone: camera roll''s last photo. No skipping 👀'),
  ('group','roll','photo','Everyone''s 3rd latest screenshot. Explain nothing.'),
  ('group','roll','photo','Close your eyes, tap your gallery, send it. No vetoes.'),
  ('group','roll','photo','Your last selfie. The group rates it 1–10.'),
  ('group','roll','photo','Last photo of food in your gallery. Group votes best.'),
  -- ── Group: instant camera ──
  ('group','instant','photo','Front cam, right now, no retakes. Worst one loses 📸'),
  ('group','instant','photo','Battery % screenshot. Lowest is the group''s problem 🔋'),
  ('group','instant','photo','Your exact view this second. Guess who''s where.'),
  ('group','instant','photo','Screen time screenshot. Highest buys chai ☕'),
  ('group','instant','photo','Whatever''s in your hand right now. Show it.'),
  -- ── Group: 5-second instincts (text) ──
  ('group','instinct','text','Rate your day 1–10. Lowest gets hyped by everyone.'),
  ('group','instinct','text','One emoji for your week. Go.'),
  ('group','instinct','text','Who in this group replies slowest? 👀'),
  ('group','instinct','text','What are you doing right now? 5 words.'),
  ('group','instinct','text','Most likely to be late today? Name them 😭'),
  ('group','instinct','text','Last song you played. The group judges.'),
  ('group','instinct','text','Who here would survive a zombie apocalypse? One name.'),
  ('group','instinct','text','Weekend plan in 3 words.'),
  ('group','instinct','text','Who in this group owes you something? 😤');
