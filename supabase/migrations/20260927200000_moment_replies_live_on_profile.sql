-- Moment replies belong to the person who made them, not only to the Moment.
--
-- Explicit request: "if any user replies to the moment it shall appear in
-- his moment section in profile, and he can remove it from his profile,
-- which doesn't affect any other moments — and if the main sender removes
-- the moment, the others shall not be removed".
--
-- 1. hidden_from_profile: the replier's own "remove from my profile". A
--    per-row flag on THEIR reply, so it touches nothing else — the reply
--    still shows inside the Moment, and no other contribution changes.
--    moment_replies_update_own already lets only the replier set it.
-- 2. moment_post_id ON DELETE SET NULL (was CASCADE): a hard delete of the
--    parent Moment (e.g. its author's account being purged) no longer wipes
--    every contributor's photo. The normal "remove moment" path is a soft
--    delete (posts.deleted_at) and never touched replies; the profile now
--    reads replies from this table (FeedService.fetchContributedMoments),
--    so they stay listed either way.

alter table public.moment_replies
  add column if not exists hidden_from_profile boolean not null default false;

alter table public.moment_replies alter column moment_post_id drop not null;

alter table public.moment_replies
  drop constraint if exists moment_replies_moment_post_id_fkey;
alter table public.moment_replies
  add constraint moment_replies_moment_post_id_fkey
  foreign key (moment_post_id) references public.posts(id) on delete set null;
