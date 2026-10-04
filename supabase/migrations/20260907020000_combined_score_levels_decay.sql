-- ---------------------------------------------------------------------------
-- COMBINED SCORE + 7 LEVELS + 20-DAY DECAY
--
-- Merges the two existing halves (users.glow_score = "anon", users.ping_score
-- = "ping") into one total that every surface reads, adds the 7-level ladder,
-- and adds the tiered 20-day decay.
--
-- The two halves STAY as separate columns on purpose: decay applies a
-- different percentage to each ("-15% ping / -20% anon" etc.), so the split
-- has to survive even though nothing displays it any more.
-- ---------------------------------------------------------------------------

-- ── 1. Level ladder ────────────────────────────────────────────────────────
-- Final names: Ghost / Rookie / Contender / Elite / Ace / Dominator / Legend.
-- IMMUTABLE so it can back a generated column.
create or replace function public.level_for_score(p_score integer)
returns integer
language sql
immutable
as $$
  select case
    when coalesce(p_score, 0) >= 6000 then 7  -- Legend
    when coalesce(p_score, 0) >= 3000 then 6  -- Dominator
    when coalesce(p_score, 0) >= 1500 then 5  -- Ace
    when coalesce(p_score, 0) >=  700 then 4  -- Elite
    when coalesce(p_score, 0) >=  300 then 3  -- Contender
    when coalesce(p_score, 0) >=  100 then 2  -- Rookie
    else 1                                    -- Ghost
  end;
$$;

-- ── 2. total_score + level as GENERATED columns ────────────────────────────
-- Generated, not plain columns that a trigger keeps in sync: a stored total
-- physically cannot drift from the two halves it is made of, and the level
-- re-evaluates itself the instant decay changes a score — which is exactly
-- the "a user CAN drop a level" requirement, with no second write to forget.
alter table public.users
  add column if not exists total_score integer
    generated always as (coalesce(glow_score, 0) + coalesce(ping_score, 0)) stored;

alter table public.users
  add column if not exists level integer
    generated always as (
      public.level_for_score(coalesce(glow_score, 0) + coalesce(ping_score, 0))
    ) stored;

-- ── 3. Decay + daily-activity bookkeeping ──────────────────────────────────
alter table public.users
  add column if not exists last_decay_at timestamptz not null default now();

alter table public.users
  add column if not exists last_open_at date;

alter table public.users
  add column if not exists daily_streak integer not null default 0;

alter table public.users
  add column if not exists daily_streak_last date;

create index if not exists users_total_score_idx on public.users (total_score desc);
create index if not exists users_last_decay_at_idx on public.users (last_decay_at);

comment on column public.users.total_score is
  'Generated: glow_score + ping_score. The ONE score every surface shows.';
comment on column public.users.level is
  'Generated from total_score via level_for_score(). 1=Ghost .. 7=Legend.';
comment on column public.users.daily_streak is
  'Consecutive days with an anon post OR a ping sent. Server-side; replaces '
  'the shared_preferences StreakService, which seeded a fake 5-day streak.';
