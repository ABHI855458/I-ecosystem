-- Closes real gaps in ping_sheet_prompts' DEFAULT rows (community_id IS
-- NULL): 'anonymous' scope had ZERO text-kind prompts at all (32 photo, 0
-- text); 'everyone'/'ping_page' text sets were thin (5 each); 'group' had
-- only 8+8. Each batch is written in that scope's OWN established voice,
-- verified from the live rows already there before writing anything:
--   anonymous  -> warm/supportive blended with light confession-banter
--   everyone   -> "about you, to the room" personal questions
--   ping_page  -> intimate "you and me" 1:1 framing
--   group      -> group-dynamics banter (text) / "show me the group" (photo)
--
-- Checked against the ENTIRE existing prompt library before writing this
-- file -- 468 daily_prompts + 3155 ping_prompts + 496 ping_sheet_prompts,
-- every scope and community -- and against each other. Zero exact-text
-- collisions, case/whitespace-insensitive.
--
-- sort_order starts at 100 for every scope/kind pair here, safely past
-- every existing max (highest found: 44).

DO $$
BEGIN
  -- anonymous/text: 20 new rows
  INSERT INTO public.ping_sheet_prompts (scope, prompt_text, card_color, active, sort_order, community_id, prompt_kind) VALUES
    ('anonymous', 'What''s a secret you''re only saying because it''s anonymous?', '', true, 100, NULL, 'text'),
    ('anonymous', 'What''s something you needed to hear today?', '', true, 101, NULL, 'text'),
    ('anonymous', 'Say the thing you''ve been holding in all week.', '', true, 102, NULL, 'text'),
    ('anonymous', 'What''s weighing on you that nobody else knows?', '', true, 103, NULL, 'text'),
    ('anonymous', 'Who do you wish knew how you actually feel?', '', true, 104, NULL, 'text'),
    ('anonymous', 'What''s the bravest thing you did today, quietly?', '', true, 105, NULL, 'text'),
    ('anonymous', 'What''s something you''re proud of that no one noticed?', '', true, 106, NULL, 'text'),
    ('anonymous', 'What''s a rule on this campus you secretly break?', '', true, 107, NULL, 'text'),
    ('anonymous', 'What''s the loneliest part of your week been?', '', true, 108, NULL, 'text'),
    ('anonymous', 'What''s something you''d only admit at 2am?', '', true, 109, NULL, 'text'),
    ('anonymous', 'What''s a comparison you keep making that hurts you?', '', true, 110, NULL, 'text'),
    ('anonymous', 'What''s something you forgave yourself for, finally?', '', true, 111, NULL, 'text'),
    ('anonymous', 'What''s the one thing you wish someone would ask you?', '', true, 112, NULL, 'text'),
    ('anonymous', 'What''s a fear you''ve never said out loud?', '', true, 113, NULL, 'text'),
    ('anonymous', 'What''s something good that happened you haven''t told anyone?', '', true, 114, NULL, 'text'),
    ('anonymous', 'What''s a lie you''re tired of keeping up?', '', true, 115, NULL, 'text'),
    ('anonymous', 'Who on this campus would be surprised you feel this way?', '', true, 116, NULL, 'text'),
    ('anonymous', 'What''s something you needed to let go of this week?', '', true, 117, NULL, 'text'),
    ('anonymous', 'What''s a version of you that only exists anonymously?', '', true, 118, NULL, 'text'),
    ('anonymous', 'What''s the kindest thing you did today, unnoticed?', '', true, 119, NULL, 'text');

  -- everyone/text: 20 new rows
  INSERT INTO public.ping_sheet_prompts (scope, prompt_text, card_color, active, sort_order, community_id, prompt_kind) VALUES
    ('everyone', 'What''s a habit of yours that nobody''s called out yet?', '', true, 100, NULL, 'text'),
    ('everyone', 'What''s something people assume about you that''s wrong?', '', true, 101, NULL, 'text'),
    ('everyone', 'What''s the most RVCE thing that''s happened to you?', '', true, 102, NULL, 'text'),
    ('everyone', 'What''s a rumor about you that''s actually true?', '', true, 103, NULL, 'text'),
    ('everyone', 'What''s something you''d never admit unless asked directly?', '', true, 104, NULL, 'text'),
    ('everyone', 'What''s the real reason you picked your branch?', '', true, 105, NULL, 'text'),
    ('everyone', 'What''s a version of you people here haven''t seen?', '', true, 106, NULL, 'text'),
    ('everyone', 'What''s something you''ve changed your mind about lately?', '', true, 107, NULL, 'text'),
    ('everyone', 'What''s the most honest review you''d give this semester?', '', true, 108, NULL, 'text'),
    ('everyone', 'What''s a moment here you''d replay if you could?', '', true, 109, NULL, 'text'),
    ('everyone', 'What''s something small that made your week better?', '', true, 110, NULL, 'text'),
    ('everyone', 'What''s a class you''d defend even though everyone hates it?', '', true, 111, NULL, 'text'),
    ('everyone', 'What''s the one thing you''d want people to know about you?', '', true, 112, NULL, 'text'),
    ('everyone', 'What''s a decision here you don''t regret at all?', '', true, 113, NULL, 'text'),
    ('everyone', 'What''s something you''re better at than people think?', '', true, 114, NULL, 'text'),
    ('everyone', 'What''s a place on campus that''s secretly yours?', '', true, 115, NULL, 'text'),
    ('everyone', 'What''s the last thing that genuinely surprised you here?', '', true, 116, NULL, 'text'),
    ('everyone', 'What''s a habit you picked up since joining college?', '', true, 117, NULL, 'text'),
    ('everyone', 'What''s something you''d tell your first-year self?', '', true, 118, NULL, 'text'),
    ('everyone', 'What''s the realest thing about you right now?', '', true, 119, NULL, 'text');

  -- ping_page/text: 20 new rows
  INSERT INTO public.ping_sheet_prompts (scope, prompt_text, card_color, active, sort_order, community_id, prompt_kind) VALUES
    ('ping_page', 'What''s something you''ve wanted to ask me but haven''t?', '', true, 100, NULL, 'text'),
    ('ping_page', 'What''s the last thing you remembered about me randomly?', '', true, 101, NULL, 'text'),
    ('ping_page', 'What do you actually think happens next with us?', '', true, 102, NULL, 'text'),
    ('ping_page', 'What''s a moment with me you still think about?', '', true, 103, NULL, 'text'),
    ('ping_page', 'What''s something you''d change about how we talk?', '', true, 104, NULL, 'text'),
    ('ping_page', 'What''s the truth you''d only tell me, not anyone else?', '', true, 105, NULL, 'text'),
    ('ping_page', 'What made you think of me today?', '', true, 106, NULL, 'text'),
    ('ping_page', 'What''s something you like about me you''ve never said?', '', true, 107, NULL, 'text'),
    ('ping_page', 'What''s a conversation with me you wish we''d finish?', '', true, 108, NULL, 'text'),
    ('ping_page', 'What do you actually want to happen here?', '', true, 109, NULL, 'text'),
    ('ping_page', 'What''s the version of me you first assumed, before you knew me?', '', true, 110, NULL, 'text'),
    ('ping_page', 'What''s something you noticed about me that stuck?', '', true, 111, NULL, 'text'),
    ('ping_page', 'What would you ask me if I couldn''t get offended?', '', true, 112, NULL, 'text'),
    ('ping_page', 'What''s a memory with me you''d want to relive?', '', true, 113, NULL, 'text'),
    ('ping_page', 'What''s something you''ve never told me about that day?', '', true, 114, NULL, 'text'),
    ('ping_page', 'What do you actually think when my name pops up?', '', true, 115, NULL, 'text'),
    ('ping_page', 'What''s the one thing you want me to understand right now?', '', true, 116, NULL, 'text'),
    ('ping_page', 'What''s something you held back the last time we talked?', '', true, 117, NULL, 'text'),
    ('ping_page', 'What''s a question about me you''ve been sitting on?', '', true, 118, NULL, 'text'),
    ('ping_page', 'What do you want from this, honestly?', '', true, 119, NULL, 'text');

  -- group/text: 10 new rows
  INSERT INTO public.ping_sheet_prompts (scope, prompt_text, card_color, active, sort_order, community_id, prompt_kind) VALUES
    ('group', 'Who actually replies fastest in this group?', '', true, 100, NULL, 'text'),
    ('group', 'Who''s ghosting the group chat right now?', '', true, 101, NULL, 'text'),
    ('group', 'What''s this group''s unspoken rule?', '', true, 102, NULL, 'text'),
    ('group', 'Who started the last argument in here?', '', true, 103, NULL, 'text'),
    ('group', 'Who''s the one holding this group together?', '', true, 104, NULL, 'text'),
    ('group', 'What''s the group''s worst shared decision so far?', '', true, 105, NULL, 'text'),
    ('group', 'Who owes this group an apology?', '', true, 106, NULL, 'text'),
    ('group', 'What''s the one thing this group can''t agree on?', '', true, 107, NULL, 'text'),
    ('group', 'Who''s the quietest one who says the most when they talk?', '', true, 108, NULL, 'text'),
    ('group', 'What''s this group''s reputation, honestly?', '', true, 109, NULL, 'text');

  -- group/photo: 10 new rows
  INSERT INTO public.ping_sheet_prompts (scope, prompt_text, card_color, active, sort_order, community_id, prompt_kind) VALUES
    ('group', 'Show me the group mid-argument, if there is one', '', true, 100, NULL, 'photo'),
    ('group', 'Show me who showed up late today', '', true, 101, NULL, 'photo'),
    ('group', 'Show me the group''s current chaos', '', true, 102, NULL, 'photo'),
    ('group', 'Show me whoever''s on their phone right now', '', true, 103, NULL, 'photo'),
    ('group', 'Show me the snacks everyone''s fighting over', '', true, 104, NULL, 'photo'),
    ('group', 'Show me the seat nobody wants to sit in', '', true, 105, NULL, 'photo'),
    ('group', 'Show me what''s actually being discussed right now', '', true, 106, NULL, 'photo'),
    ('group', 'Show me the group''s most unflattering angle', '', true, 107, NULL, 'photo'),
    ('group', 'Show me who''s carrying this conversation', '', true, 108, NULL, 'photo'),
    ('group', 'Show me the group photo nobody''s posted yet', '', true, 109, NULL, 'photo');

END $$;