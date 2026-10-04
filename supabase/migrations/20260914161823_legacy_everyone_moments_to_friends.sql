-- Bring the 10 legacy campus-wide Moments in line with the current default.
--
-- Moments have had a pinned friends-only audience since composer_screen's
-- `_momentFriendsOnly = true` ("include friends, not everyone" — a Moment
-- used to default to 'everyone' with a Friends chip beside it, which made
-- the campus-wide scope the accidental choice). Every Moment created since
-- then is 'friends'; these 10 are from 2026-08-29..09-06, before the pin.
--
-- Left as-is they sit OUTSIDE the friend gate entirely: can_view_post()
-- returns TRUE early for any visibility that isn't 'friends', so a stranger
-- could read them regardless of friendship. This is a visibility-NARROWING
-- change only — nothing becomes visible to anyone who couldn't already see
-- it.
--
-- Scoped tightly on purpose:
--   post_type = 'moment'      -> ordinary 'everyone' posts are untouched
--   visibility = 'everyone'   -> the 4 'friends' and 2 'anonymous' Moments
--                                are untouched; anonymous in particular
--                                must NOT become 'friends', that would
--                                attach a real name to a persona post.

UPDATE public.posts
   SET visibility = 'friends'
 WHERE post_type = 'moment'
   AND visibility = 'everyone';
