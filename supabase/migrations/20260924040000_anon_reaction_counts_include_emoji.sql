-- anon_reaction_counts previously counted ONLY post_realmoji_reactions
-- (photo/face reactions). RealmojiTray's new "+" mode (plain-emoji reactions,
-- no capture) writes to the generic `reactions` table instead
-- (ReactionService.setEmojiReaction, type='emoji') — see that table's own
-- doc. Those rows were never counted here, so a plain-emoji tap silently
-- vanished from the on-photo stack and the reaction breakdown: it saved,
-- but nothing ever showed it back.
--
-- This view now UNIONs both sources for an anonymous post, mapping each
-- plain-emoji glyph onto the RealmojiType wire label it already matches
-- 1:1 (RealmojiTray._emojis is deliberately drawn from the same 12 glyphs
-- RealmojiType uses — see that file's own doc), then re-groups so a post
-- reacted to via both paths with the "same" emoji still reads as one count,
-- not two rows. Callers (RealmojiService.fetchAnonCounts) are unchanged —
-- same (post_id, emoji_type, count) shape.
CREATE OR REPLACE VIEW public.anon_reaction_counts AS
SELECT post_id, emoji_type, count(*)::bigint AS count
FROM (
  SELECT r.post_id, r.emoji_type
    FROM post_realmoji_reactions r
    JOIN posts p ON p.id = r.post_id
   WHERE p.visibility = 'anonymous'

  UNION ALL

  SELECT r.post_id,
         (CASE r.emoji
           WHEN '👍' THEN 'like'
           WHEN '❤️' THEN 'love'
           WHEN '😂' THEN 'joy'
           WHEN '😮' THEN 'surprise'
           WHEN '🔥' THEN 'fire'
           WHEN '😍' THEN 'heart_eyes'
           WHEN '😎' THEN 'cool'
           WHEN '😭' THEN 'cry'
           WHEN '👏' THEN 'clap'
           WHEN '😉' THEN 'wink'
           WHEN '🥳' THEN 'party'
           WHEN '💯' THEN 'hundred'
           ELSE NULL
         END)::emoji_type_enum AS emoji_type
    FROM reactions r
    JOIN posts p ON p.id = r.post_id
   WHERE p.visibility = 'anonymous'
     AND r.type = 'emoji'
) combined
WHERE emoji_type IS NOT NULL
GROUP BY post_id, emoji_type;
