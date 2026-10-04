-- PART 2.8 — group scope gets prompts that are actually ABOUT a group.
--
-- All 46 existing global group-scope rows were byte-identical copies of the
-- Friends set (verified: unique_to_group = 0). A group ping is addressed to
-- the group as a unit, so the test each of these passes is: it makes no
-- sense sent to one person.
--
-- Old rows deactivated, not deleted — existing pings reference them.

UPDATE public.ping_sheet_prompts
   SET active = false
 WHERE scope = 'group' AND community_id IS NULL;

INSERT INTO public.ping_sheet_prompts (prompt_text, scope, community_id, prompt_kind, sort_order, active)
VALUES
  ('Show me who''s actually here right now',            'group', NULL, 'photo',  1, true),
  ('Who''s missing today?',                             'group', NULL, 'text',   2, true),
  ('Show me the table you''ve taken over',              'group', NULL, 'photo',  3, true),
  ('Who talks the most in this group?',                 'group', NULL, 'text',   4, true),
  ('Show me what''s in the middle of the group',        'group', NULL, 'photo',  5, true),
  ('What''s the running joke right now?',               'group', NULL, 'text',   6, true),
  ('Show me everyone''s shoes',                         'group', NULL, 'photo',  7, true),
  ('Who''s the one that''s always late?',               'group', NULL, 'text',   8, true),
  ('Show me the one person who''s not paying attention','group', NULL, 'photo',  9, true),
  ('What''s this group''s actual purpose?',             'group', NULL, 'text',  10, true),
  ('Show me what you''re all looking at',               'group', NULL, 'photo', 11, true),
  ('Who organised this?',                               'group', NULL, 'text',  12, true),
  ('Show me the group''s worst photo from today',       'group', NULL, 'photo', 13, true),
  ('What would this group do without one of you?',      'group', NULL, 'text',  14, true),
  ('Show me where you always sit',                      'group', NULL, 'photo', 15, true),
  ('Be honest — who''s the group''s weakest link?',     'group', NULL, 'text',  16, true);
