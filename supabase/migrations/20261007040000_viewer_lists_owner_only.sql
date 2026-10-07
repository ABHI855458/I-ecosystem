-- Who may see WHO VIEWED a post (explicit request, 2026-10-07: "others
-- shall not see who have viewed ... only the post's owners — either the
-- posted person or group members or the Duo member — shall see the seen
-- pill on their post ... maintaining the seen pill in anon, don't disturb
-- it").
--
-- Until now both lists were open to anyone who could see the post:
--   * post_viewers          — gated only by post_engagement_visible(), i.e.
--                             "can you view this post";
--   * post_presence_people  — the same gate, and it returned REAL NAMES for
--                             everyone who had opened it (the feed's
--                             "here" pill).
-- So any friend could read the list of people who had looked at someone
-- else's post. Now, for a `posts` row:
--   * NOT anonymous  -> only its owners: the poster and, on a Duo post, the
--                       partner (posts.partner_user_id);
--   * anonymous      -> post_viewers unchanged (the Anon feed's seen pill);
--                       post_presence_people already answered only the
--                       poster for these, and still does.
-- Group posts are untouched: group_post_viewers and the group branch of
-- post_presence_people were members-only already.
--
-- Both functions are patched in place from their LIVE definitions (they
-- have drifted from their migrations before); each fragment must be found
-- exactly once or nothing changes.
DO $$
DECLARE
  v_def text;
  v_new text;
  v_old text;
  v_rep text;
BEGIN
  -- ── post_viewers ──────────────────────────────────────────────────────
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
   WHERE p.proname = 'post_viewers' AND p.pronamespace = 'public'::regnamespace;
  IF v_def IS NULL THEN RAISE EXCEPTION 'post_viewers not found'; END IF;

  IF v_def LIKE '%is_owner%' THEN
    RAISE NOTICE 'post_viewers already patched';
  ELSE
    v_new := v_def;

    v_old := E'    select (p.visibility = ''anonymous'') as is_anon\n'
          || E'      from public.posts p where p.id = p_post_id';
    v_rep := E'    select (p.visibility = ''anonymous'') as is_anon,\n'
          || E'           ((select id from me) = p.user_id\n'
          || E'             or (select id from me) = p.partner_user_id) as is_owner\n'
          || E'      from public.posts p where p.id = p_post_id';
    IF (length(v_new) - length(replace(v_new, v_old, ''))) / length(v_old) <> 1 THEN
      RAISE EXCEPTION 'post_viewers: post CTE not found exactly once';
    END IF;
    v_new := replace(v_new, v_old, v_rep);

    v_old := E'       and public.post_engagement_visible(p_post_id)\n  ),\n  r as (';
    v_rep := E'       and public.post_engagement_visible(p_post_id)\n'
          || E'       -- an anonymous post keeps its open seen list; any other\n'
          || E'       -- post shows it to its owners only\n'
          || E'       and coalesce((select is_anon or coalesce(is_owner, false) from post), false)\n'
          || E'  ),\n  r as (';
    IF (length(v_new) - length(replace(v_new, v_old, ''))) / length(v_old) <> 1 THEN
      RAISE EXCEPTION 'post_viewers: viewer gate not found exactly once';
    END IF;
    v_new := replace(v_new, v_old, v_rep);

    EXECUTE v_new;
  END IF;

  -- ── post_presence_people ──────────────────────────────────────────────
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
   WHERE p.proname = 'post_presence_people' AND p.pronamespace = 'public'::regnamespace;
  IF v_def IS NULL THEN RAISE EXCEPTION 'post_presence_people not found'; END IF;

  IF v_def LIKE '%in (p.user_id, p.partner_user_id)%' THEN
    RAISE NOTICE 'post_presence_people already patched';
  ELSE
    v_old := E'            and (p.visibility is distinct from ''anonymous'' or p.user_id = (select id from me))\n';
    v_rep := E'            -- owners only: the poster, or their Duo partner\n'
          || E'            and (select id from me) in (p.user_id, p.partner_user_id)\n';
    IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
      RAISE EXCEPTION 'post_presence_people: post gate not found exactly once';
    END IF;
    EXECUTE replace(v_def, v_old, v_rep);
  END IF;
END $$;
