-- Single SECURITY DEFINER chokepoint the dashboard's Remove/Dismiss actions
-- call through, instead of a raw `.update()` from the anon-key client —
-- `notifications` has no INSERT policy for anyone (every existing writer is
-- a SECURITY DEFINER trigger: notify_ping, notify_reaction, ...), so the
-- reporter-notification half of this couldn't happen from client code no
-- matter what RLS policy got added to `reports` itself. This does both the
-- content removal (when applicable) and the reporter notification
-- atomically, and re-checks the same authorization rep_select_moderator
-- already grants, since SECURITY DEFINER bypasses RLS entirely.
create or replace function public.resolve_report(p_report_id uuid, p_outcome text)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record;
  rep record;
  v_ok boolean;
begin
  if p_outcome not in ('removed', 'dismissed') then
    raise exception 'Invalid outcome.';
  end if;

  select * into r from public.reports where id = p_report_id;
  if r.id is null then
    raise exception 'Report not found.';
  end if;

  select
    public.is_admin_or_global_mod()
    or (r.post_id is not null and exists (
      select 1 from public.posts p
       where p.id = r.post_id and p.community_id is not null and public.can_moderate_community(p.community_id)
    ))
    or (r.community_post_id is not null and exists (
      select 1 from public.community_posts cp
       where cp.id = r.community_post_id and public.can_moderate_community(cp.community_id)
    ))
  into v_ok;

  if not v_ok then
    raise exception 'Not authorized to resolve this report.';
  end if;

  if p_outcome = 'removed' then
    if r.post_id is not null then
      update public.posts set deleted_at = now() where id = r.post_id and deleted_at is null;
    elsif r.comment_id is not null then
      update public.comments set deleted_at = now() where id = r.comment_id and deleted_at is null;
    elsif r.community_post_id is not null then
      update public.community_posts set deleted_at = now() where id = r.community_post_id and deleted_at is null;
    end if;

    -- Removal is content-level, not report-row-level: every OTHER pending
    -- report pointing at this same piece of content is resolved too, not
    -- just the row the moderator happened to click.
    for rep in
      select * from public.reports
       where status = 'pending'
         and ((r.post_id is not null and post_id = r.post_id)
           or (r.comment_id is not null and comment_id = r.comment_id)
           or (r.community_post_id is not null and community_post_id = r.community_post_id))
    loop
      update public.reports set status = 'removed', resolved_at = now() where id = rep.id;
      insert into public.notifications (recipient_id, type, tier, title, body, dedupe_key)
      select u.id, 'report_resolved', 'minor', 'Your report was reviewed',
             'The content you reported has been removed.',
             'report_resolved:' || rep.id::text
        from public.users u where u.auth_id = rep.reporter_id
      on conflict (type, dedupe_key) where dedupe_key is not null do nothing;
    end loop;
  else
    update public.reports set status = 'dismissed', resolved_at = now() where id = p_report_id;
    insert into public.notifications (recipient_id, type, tier, title, body, dedupe_key)
    select u.id, 'report_resolved', 'minor', 'Your report was reviewed',
           'We reviewed your report and didn''t find a violation.',
           'report_resolved:' || p_report_id::text
      from public.users u where u.auth_id = r.reporter_id
    on conflict (type, dedupe_key) where dedupe_key is not null do nothing;
  end if;
end;
$function$;

grant execute on function public.resolve_report(uuid, text) to authenticated;
