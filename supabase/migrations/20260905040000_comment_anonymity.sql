-- Explicit bug: the comment composer's "Comment anonymously" toggle
-- (_isAnon in post_card_shared.dart) only ever changed the composer's OWN
-- preview avatar/hint text — CommentService.post() never received the flag
-- at all, so every comment landed with the real user_id and rendered with
-- the real name/photo regardless of what the toggle showed. Anyone who
-- used it believed they'd commented anonymously; they hadn't.
alter table public.comments add column if not exists is_anonymous boolean not null default false;
