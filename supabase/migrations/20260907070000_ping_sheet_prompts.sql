-- ---------------------------------------------------------------------------
-- ping_sheet_prompts — the prompts in the PING SHEET's picker, editable from
-- the dashboard.
--
-- Not a reuse of `ping_prompts`: that table means something else entirely —
-- the up-to-5 ping-BACK replies hanging off one daily_prompts row
-- (daily_prompt_id NOT NULL, enforce_max_4_ping_prompts trigger). These are
-- standalone, scoped by WHICH SHEET they appear in, and uncapped.
--
-- Two scopes, matching PingContext in ping_prompt_sheet.dart exactly:
--   'everyone'  -> the Friends-feed / profile / ping-page sheet
--   'anonymous' -> the anon feed's ping sheet
-- The app shows one or the other, never both, which is what "separately"
-- requires.
--
-- The app keeps its hardcoded lists as an offline fallback, so an empty
-- table or a failed fetch degrades to today's behaviour rather than an
-- empty picker.
-- ---------------------------------------------------------------------------

create table if not exists public.ping_sheet_prompts (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('everyone', 'anonymous')),
  prompt_text text not null check (length(btrim(prompt_text)) between 1 and 120),
  -- Card tint, as the app's own _Prompt.cardColor hex (0xFF...). Null lets
  -- the client pick from its palette, so the dashboard never has to set one.
  card_color text,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists ping_sheet_prompts_scope_idx
  on public.ping_sheet_prompts (scope, active, sort_order);

alter table public.ping_sheet_prompts enable row level security;

-- Everyone signed in reads the ACTIVE ones (same shape as dp_read).
drop policy if exists ping_sheet_prompts_read on public.ping_sheet_prompts;
create policy ping_sheet_prompts_read
  on public.ping_sheet_prompts for select
  using (active);

-- Moderators manage them. These are global (no community scoping), so the
-- gate is is_admin_or_global_mod() — same rule daily_prompts uses for its
-- own community_id IS NULL rows.
drop policy if exists ping_sheet_prompts_insert_moderator on public.ping_sheet_prompts;
create policy ping_sheet_prompts_insert_moderator
  on public.ping_sheet_prompts for insert
  with check (public.is_admin_or_global_mod());

drop policy if exists ping_sheet_prompts_update_moderator on public.ping_sheet_prompts;
create policy ping_sheet_prompts_update_moderator
  on public.ping_sheet_prompts for update
  using (public.is_admin_or_global_mod());

drop policy if exists ping_sheet_prompts_delete_moderator on public.ping_sheet_prompts;
create policy ping_sheet_prompts_delete_moderator
  on public.ping_sheet_prompts for delete
  using (public.is_admin_or_global_mod());

-- Moderators need to see inactive rows too, or the dashboard can't unhide
-- what it just hid.
drop policy if exists ping_sheet_prompts_read_moderator on public.ping_sheet_prompts;
create policy ping_sheet_prompts_read_moderator
  on public.ping_sheet_prompts for select
  using (public.is_admin_or_global_mod());
