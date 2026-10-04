-- Group-ping member streaks read 0 for most of every day.
--
-- resolve-group-ping-streaks ran at 18:05 UTC (23:35 IST) and only judges
-- days BEFORE today, so a reply on day D was counted at 23:35 on D+1.
-- group_ping_member_streak_map only shows a streak while
-- last_reply_on >= yesterday, so from 00:00 to 23:35 each day the streak
-- ring on members' DPs showed 0 even though the run was unbroken.
--
-- Run it at 00:05 IST instead: the day that just ended is judged five
-- minutes later, and last_reply_on = yesterday holds all day.
select cron.alter_job(
  (select jobid from cron.job where jobname = 'resolve-group-ping-streaks'),
  schedule => '35 18 * * *'
);
