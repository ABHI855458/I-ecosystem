-- ---------------------------------------------------------------------------
-- Username + dual anon-name identity.
--
-- CONFIRMED against the live DB (project uehqazxnodndutjvxemq) before writing:
-- public.users had no username, no anon_name_2 and no active-slot column;
-- anon_name is TEXT UNIQUE NOT NULL and name is NOT NULL. schema.sql is stale
-- and was not trusted for any of that.
--
-- Every column below is nullable or defaulted so CurrentUserService.resolveId()'s
-- lazy insert (current_user_service.dart) keeps working untouched.
--
-- anon_name keeps its existing UNIQUE NOT NULL and acts as slot 1. anon_name_2
-- deliberately gets NO uniqueness constraint: enforcing it across both slots
-- would need a trigger, and the shuffle only ever toggles between a user's own
-- two names, so global uniqueness on the second one buys nothing.
-- ---------------------------------------------------------------------------

alter table public.users
  add column if not exists username text,
  add column if not exists anon_name_2 text,
  add column if not exists active_anon_slot smallint not null default 1;

-- Case-insensitive uniqueness without a citext dependency (no such extension
-- is installed). Partial, so soft-deleted rows don't hold a name hostage.
create unique index if not exists users_username_lower_key
  on public.users (lower(username))
  where username is not null and deleted_at is null;

-- Length/charset must stay in lockstep with AppStrings.usernameMinLength /
-- usernameMaxLength in lib/core/constants.dart.
alter table public.users
  add constraint users_username_format
    check (username is null or username ~ '^[a-z0-9_]{3,15}$'),
  add constraint users_active_anon_slot_valid
    check (active_anon_slot in (1, 2)
           and (active_anon_slot = 1 or anon_name_2 is not null));
