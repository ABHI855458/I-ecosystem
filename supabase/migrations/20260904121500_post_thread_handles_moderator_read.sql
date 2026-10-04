-- post_thread_handles' only SELECT policy (pth_read) restricts reads to
-- user_id = auth.uid(), so the moderator dashboard's Anon page cannot
-- resolve a post's anon pseudonym to render "avatar + caption" — every
-- lookup but the moderator's own returns empty under RLS. Add a permissive
-- moderator-read policy; this is read-only and does not touch pth_insert.
create policy pth_read_moderator on post_thread_handles
  for select
  using (is_admin_or_global_mod());
