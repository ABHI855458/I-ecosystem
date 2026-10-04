-- Curiosity copy everywhere: push titles stop naming the actor.
--
-- Rewrites each function's own source in place rather than retyping ten
-- bodies, so nothing but the title literal can change. actor_id stays on
-- the row, so the in-app list can still reveal identity under the existing
-- pin rules — only the PUSH text goes anonymous.
--
-- notify_comment and notify_moment_contribution already said "Someone" and
-- are left alone. notify_pair_streak_milestone is deliberately EXCLUDED:
-- "You + Rahul hit 7 days" is a mutual streak between two people who by
-- definition already know each other, and "You + someone" destroys the
-- message rather than creating curiosity.

DO $mig$
DECLARE
  r record;
  v_src text;
  v_new text;
  pairs text[][] := ARRAY[
    ['notify_friend_accepted',
     'COALESCE(v_actor_name,''someone'') || '' accepted your friend request 🎉''',
     '''Someone accepted your friend request 🎉'''],
    ['notify_friend_request',
     'COALESCE(v_actor_name,''someone'') || '' wants to be friends''',
     '''Someone wants to be friends 👀'''],
    ['notify_reaction',
     'COALESCE(v_actor_name, ''someone'') || '' reacted to your post''',
     '''Someone reacted to your post 👀'''],
    ['notify_us_album_mutual',
     'COALESCE(v_actor_name,''someone'') || '' made a photo visible to both of you''',
     '''Someone made a photo visible to both of you 👀''']
  ];
  i int;
BEGIN
  FOR i IN 1 .. array_length(pairs, 1) LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = pairs[i][1];

    IF v_src IS NULL THEN
      RAISE EXCEPTION 'function % not found', pairs[i][1];
    END IF;

    v_new := replace(v_src, pairs[i][2], pairs[i][3]);

    IF v_new = v_src THEN
      RAISE EXCEPTION 'title literal not found in % — refusing to rewrite blindly', pairs[i][1];
    END IF;

    EXECUTE v_new;
  END LOOP;
END
$mig$;

-- group_streak_broken named the person who missed. That is exactly the
-- "don't name the non-responders" rule, so the clause is dropped entirely.
DO $mig2$
DECLARE v_src text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'notify_group_streak_broken';

  v_new := replace(v_src,
    'CASE WHEN v_missing IS NOT NULL THEN '' — '' || v_missing || '' didn''''t reply in time'' ELSE '''' END',
    ''' — someone didn''''t reply in time''');

  IF v_new = v_src THEN
    RAISE EXCEPTION 'streak-broken clause not found — refusing to rewrite blindly';
  END IF;

  EXECUTE v_new;
END
$mig2$;
