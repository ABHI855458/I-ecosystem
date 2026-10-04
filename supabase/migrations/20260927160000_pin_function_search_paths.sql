-- Advisor function_search_path_mutable (20 functions): none had a fixed
-- search_path, so a role able to create objects earlier on the path could
-- shadow the tables/functions they reference. Pinned to the same path the
-- rest of the schema uses; `extensions` included so nothing that resolves
-- an extension function by bare name breaks (audit 2026-09-27: none does).
alter function public.active_anon_name(text,text,integer)            set search_path = public, extensions, pg_temp;
alter function public.community_level_name(integer)                  set search_path = public, extensions, pg_temp;
alter function public.community_level_number(integer)                set search_path = public, extensions, pg_temp;
alter function public.community_next_level_name(integer)             set search_path = public, extensions, pg_temp;
alter function public.community_next_level_xp(integer)               set search_path = public, extensions, pg_temp;
alter function public.current_week_start()                           set search_path = public, extensions, pg_temp;
alter function public.derive_branch(text)                            set search_path = public, extensions, pg_temp;
alter function public.effective_community_streak(integer,date)       set search_path = public, extensions, pg_temp;
alter function public.fmt_cooldown_remaining(timestamp with time zone) set search_path = public, extensions, pg_temp;
alter function public.gen_handle()                                   set search_path = public, extensions, pg_temp;
alter function public.gen_user_code()                                set search_path = public, extensions, pg_temp;
alter function public.level_floor(integer)                           set search_path = public, extensions, pg_temp;
alter function public.level_for_score(integer)                       set search_path = public, extensions, pg_temp;
alter function public.level_name(integer)                            set search_path = public, extensions, pg_temp;
alter function public.pin_cooldown()                                 set search_path = public, extensions, pg_temp;
alter function public.report_target_label(public.reports)            set search_path = public, extensions, pg_temp;
alter function public.set_anon_expiry()                              set search_path = public, extensions, pg_temp;
alter function public.set_pin_expiry()                               set search_path = public, extensions, pg_temp;
alter function public.set_ping_replied()                             set search_path = public, extensions, pg_temp;
alter function public.touch_app_config_updated_at()                  set search_path = public, extensions, pg_temp;
