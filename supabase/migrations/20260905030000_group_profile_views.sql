-- Group profile's own "N here" badge (group_profile_v2_screen.dart) was a
-- hardcoded `hereCount: 0` — no view-tracking existed for a group's
-- profile at all (profile_views is person-to-person only, no group_id).
-- Explicit request: profile context (group and personal) shows an
-- ALL-TIME viewer count; the feed's own 3h live-presence system
-- (PresenceService) is separate and stays untouched.
create table if not exists public.group_profile_views (
  id uuid primary key default gen_random_uuid(),
  viewer_id uuid not null references public.users(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists group_profile_views_group_idx on public.group_profile_views(group_id);

alter table public.group_profile_views enable row level security;

create policy group_profile_views_insert_self on public.group_profile_views
  for insert
  with check (viewer_id in (select id from public.users where auth_id = auth.uid()));

-- Members can read their own group's view rows (needed for the count
-- query below to run as a plain authenticated select rather than a
-- SECURITY DEFINER RPC — same "member-gated" trust boundary the rest of
-- this group's own data already has).
create policy group_profile_views_select_member on public.group_profile_views
  for select
  using (public.is_group_member(group_id, (select id from public.users where auth_id = auth.uid())));
