-- daily_prompts.community_id has no FK to communities(id) — same missing-FK
-- shape as community_members before 20260904120000_dashboard_sections.sql
-- fixed it. Blocks a PostgREST `communities(name)` embed with PGRST200
-- ("no relationship found"), which is exactly what DailyPromptService
-- (lib/services/daily_prompt_service.dart, the app's prompt-bar rotation)
-- needs to resolve a prompt's community name. No orphaned community_id
-- values exist live, so this adds cleanly.
alter table daily_prompts
  add constraint daily_prompts_community_id_fkey
  foreign key (community_id) references communities(id);
