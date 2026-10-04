-- Group QR for EVERY group, private ones included.
--
-- Until now the banner QR was public-groups-only because its payload was the
-- bare group id and joining went through the self_join_public_group RLS
-- policy. Every real group is private, so the QR never showed ("there shall
-- be qr to join the group ... in each group's banner, it's missing").
--
-- A group id is not a secret (feed cards and rosters expose it), so a private
-- group can't be joinable by id alone. Instead each group gets a random join
-- code that ONLY its members can read; the QR carries id + code, and
-- join_group_by_code checks both. The code lives in its own table (no client
-- grants at all) rather than a groups column, because groups rows are
-- readable by friends-of-members and community members, who must not see it.

create table if not exists public.group_join_codes (
  group_id   uuid primary key references public.groups(id) on delete cascade,
  code       text not null default replace(gen_random_uuid()::text, '-', ''),
  created_at timestamptz not null default now()
);

alter table public.group_join_codes enable row level security;
revoke all on public.group_join_codes from anon, authenticated;

-- Members only. Mints the code on first request.
create or replace function public.get_group_join_code(p_group_id uuid)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_me uuid := public.current_user_id();
  v_code text;
begin
  if v_me is null or not public.is_group_member(p_group_id, v_me) then
    raise exception 'Not a member of this group';
  end if;
  insert into public.group_join_codes (group_id) values (p_group_id)
  on conflict (group_id) do nothing;
  select code into v_code from public.group_join_codes where group_id = p_group_id;
  return v_code;
end $$;

-- Joins the caller as a plain member if the code matches. Returns true when
-- this call added the membership, false if already a member. A pending
-- invite for the same group is cleared, same as respond_group_invite.
create or replace function public.join_group_by_code(p_group_id uuid, p_code text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_me uuid := public.current_user_id();
  v_added int;
begin
  if v_me is null then
    raise exception 'Not signed in';
  end if;
  if not exists (
    select 1 from public.group_join_codes
    where group_id = p_group_id and code = p_code
  ) then
    raise exception 'Invalid group code';
  end if;
  insert into public.group_members (group_id, user_id, role)
  values (p_group_id, v_me, 'member')
  on conflict (group_id, user_id) do nothing;
  get diagnostics v_added = row_count;
  delete from public.group_invites where group_id = p_group_id and invitee_id = v_me;
  return v_added > 0;
end $$;

revoke all on function public.get_group_join_code(uuid) from public, anon;
revoke all on function public.join_group_by_code(uuid, text) from public, anon;
grant execute on function public.get_group_join_code(uuid) to authenticated;
grant execute on function public.join_group_by_code(uuid, text) to authenticated;
