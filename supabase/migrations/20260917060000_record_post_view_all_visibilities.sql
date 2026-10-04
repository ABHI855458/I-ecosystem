-- record_post_view bailed out unless the post was anonymous, so post_views
-- only ever had anon rows. Two features read that table and were therefore
-- dead on every friends/everyone post:
--   - the "here" pill's pinned-viewer merge (PresenceService.fetchPresence)
--     — "if the pinned person has viewed the post it shall show, whether he
--     is here at the moment or not"
--   - the seen pill / post_viewers RPC on a profile
--
-- Views are now recorded for ANY visibility. The +5 glow_score award stays
-- anonymous-only on purpose: paying out per view on friends posts would
-- silently rewrite the score economy, which is not what this fix is for.
CREATE OR REPLACE FUNCTION public.record_post_view(p_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid;
  v_owner uuid;
  v_vis text;
  v_n int;
begin
  v_me := public.current_user_id();
  if v_me is null then
    return;
  end if;

  select user_id, visibility into v_owner, v_vis from public.posts where id = p_post_id;
  -- Own post, or gone: nothing to record. Visibility no longer gates this.
  if v_owner is null or v_owner = v_me then
    return;
  end if;

  insert into public.post_views (post_id, viewer_id)
  values (p_post_id, v_me)
  on conflict (post_id, viewer_id) do nothing;

  get diagnostics v_n = row_count;
  if v_n > 0 then
    update public.posts set view_count = coalesce(view_count, 0) + 1 where id = p_post_id;
    -- Score award unchanged: anonymous posts only.
    if v_vis = 'anonymous' then
      update public.users set glow_score = glow_score + 5 where id = v_owner;
    end if;
  end if;
end;
$function$;
