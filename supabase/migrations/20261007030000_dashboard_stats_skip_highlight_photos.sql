-- A highlight photo is stored as a quiet post (posts.post_type =
-- 'highlight', see 20261007010000_personal_highlights.sql). The admin
-- dashboard's post totals counted every non-deleted posts row, so one
-- person pinning a 10-photo highlight would have read as "10 posts today".
-- posts_total / posts_today / the 14-day chart now skip those rows.
--
-- Left alone on purpose: active_7d (making a highlight IS activity) and
-- dashboard_feed (moderators should still see highlight photos).
--
-- Patched in place from the live definition — each fragment must be
-- present exactly once, or nothing is changed.
DO $$
DECLARE
  v_def  text;
  v_new  text;
  v_frag text;
  v_frags text[] := ARRAY[
    '''posts_total'', (SELECT count(*) FROM posts WHERE deleted_at IS NULL',
    '''posts_today'', (SELECT count(*) FROM posts WHERE deleted_at IS NULL',
    'WHERE p.deleted_at IS NULL AND p.created_at::date = g.d::date'
  ];
  v_repl text[] := ARRAY[
    '''posts_total'', (SELECT count(*) FROM posts WHERE deleted_at IS NULL AND post_type IS DISTINCT FROM ''highlight''',
    '''posts_today'', (SELECT count(*) FROM posts WHERE deleted_at IS NULL AND post_type IS DISTINCT FROM ''highlight''',
    'WHERE p.deleted_at IS NULL AND p.post_type IS DISTINCT FROM ''highlight'' AND p.created_at::date = g.d::date'
  ];
  i integer;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
   WHERE p.proname = 'dashboard_stats' AND p.pronamespace = 'public'::regnamespace;
  IF v_def IS NULL THEN RAISE EXCEPTION 'dashboard_stats not found'; END IF;
  IF v_def LIKE '%IS DISTINCT FROM ''highlight''%' THEN
    RAISE NOTICE 'dashboard_stats already patched';
    RETURN;
  END IF;
  v_new := v_def;
  FOR i IN 1..3 LOOP
    v_frag := v_frags[i];
    IF (length(v_new) - length(replace(v_new, v_frag, ''))) / length(v_frag) <> 1 THEN
      RAISE EXCEPTION 'dashboard_stats: fragment % not found exactly once', i;
    END IF;
    v_new := replace(v_new, v_frag, v_repl[i]);
  END LOOP;
  EXECUTE v_new;
END $$;
