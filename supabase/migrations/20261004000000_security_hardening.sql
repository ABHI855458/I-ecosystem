-- ============================================================================
-- Security hardening (explicit request + approval, 2026-10-04: "go thoroughly
-- through the app — nowhere shall a hacker get in"; plan approved: "first
-- tell me and then execute").
--
-- 1. De-anonymisation / privacy-leak helpers lose direct EXECUTE. Verified
--    unused by every RLS policy, view, SECURITY INVOKER function and the app;
--    SECURITY DEFINER callers still run them as the owner.
-- 2. Duo QR carries a per-person secret code (user_duo_codes); the scan only
--    connects when it matches. Group-QR befriending moves inside
--    join_group_by_code (behind its code check); add_mutual_friends is no
--    longer callable from the app.
-- 3. No SECURITY DEFINER function in public is executable without login
--    (anon / PUBLIC); authenticated keeps exactly what it had.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

-- ------------------------------------------------ 1. privacy-leak helpers
REVOKE ALL ON FUNCTION public.owns_anon_post(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.in_friends_circle(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_blocked(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.shares_community(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.shares_real_community(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.is_member(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pin_slot_unlocks_at(uuid, smallint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.album_is_accepted_and_friend_of_either(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------- 2. Duo
CREATE TABLE IF NOT EXISTS public.user_duo_codes (
  user_id    uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  code       text NOT NULL DEFAULT replace(gen_random_uuid()::text, '-', ''),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_duo_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_duo_codes FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_my_duo_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id(); v_code text;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  INSERT INTO public.user_duo_codes (user_id) VALUES (v_me)
  ON CONFLICT (user_id) DO NOTHING;
  SELECT code INTO v_code FROM public.user_duo_codes WHERE user_id = v_me;
  RETURN v_code;
END;
$function$;

DROP FUNCTION IF EXISTS public.duo_connect_by_scan(uuid);

CREATE OR REPLACE FUNCTION public.duo_connect_by_scan(p_other uuid, p_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me uuid := public.current_user_id();
  v_a uuid;
  v_b uuid;
  v_id uuid;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF p_other IS NULL OR p_other = v_me THEN
    RAISE EXCEPTION 'Cannot Duo with yourself.';
  END IF;
  -- Proof the scanner saw the other person's own QR, not just their id.
  IF p_code IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.user_duo_codes WHERE user_id = p_other AND code = p_code
  ) THEN
    RAISE EXCEPTION 'Invalid Duo code.';
  END IF;
  IF public.is_blocked_user(auth.uid(), p_other) THEN
    RAISE EXCEPTION 'Cannot Duo with this user.';
  END IF;

  v_a := LEAST(v_me, p_other);
  v_b := GREATEST(v_me, p_other);

  SELECT id INTO v_id FROM public.us_albums
   WHERE user_a = v_a AND user_b = v_b
   ORDER BY created_at DESC LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO public.us_albums (user_a, user_b, created_by, status, responded_at)
    VALUES (v_a, v_b, v_me, 'accepted', now())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.us_albums
       SET status = 'accepted',
           responded_at = COALESCE(responded_at, now()),
           delete_requested_by = NULL,
           delete_requested_at = NULL
     WHERE id = v_id AND status <> 'accepted';
  END IF;

  PERFORM public.seed_default_circles(v_me);
  PERFORM public.seed_default_circles(p_other);
  INSERT INTO public.circle_members (circle_id, member_id)
  SELECT c.id, x.member
    FROM (VALUES (v_me, p_other), (p_other, v_me)) AS x(owner, member)
    JOIN public.circles c ON c.creator_id = x.owner AND c.kind = 'friends'
  ON CONFLICT (circle_id, member_id) DO NOTHING;

  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_duo_code() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.duo_connect_by_scan(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_duo_code() TO authenticated;
GRANT EXECUTE ON FUNCTION public.duo_connect_by_scan(uuid, text) TO authenticated;

-- Group QR join befriends members server-side, behind the code check.
CREATE OR REPLACE FUNCTION public.join_group_by_code(p_group_id uuid, p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_user_id();
  v_added int;
  v_other uuid;
begin
  if v_me is null then
    raise exception 'Not signed in';
  end if;
  if not exists (
    select 1 from public.group_join_codes
    where group_id = p_group_id and code = p_code
  ) then
    raise exception 'Invalid group code';
  end if;
  insert into public.group_members (group_id, user_id, role)
  values (p_group_id, v_me, 'member')
  on conflict (group_id, user_id) do nothing;
  get diagnostics v_added = row_count;
  delete from public.group_invites where group_id = p_group_id and invitee_id = v_me;

  if v_added > 0 then
    perform public.seed_default_circles(v_me);
    for v_other in
      select gm.user_id from public.group_members gm
       where gm.group_id = p_group_id and gm.user_id <> v_me
    loop
      continue when public.is_blocked_user(auth.uid(), v_other);
      perform public.seed_default_circles(v_other);
      insert into public.circle_members (circle_id, member_id)
      select c.id, x.member
        from (values (v_me, v_other), (v_other, v_me)) as x(owner, member)
        join public.circles c on c.creator_id = x.owner and c.kind = 'friends'
      on conflict (circle_id, member_id) do nothing;
    end loop;
  end if;

  return v_added > 0;
end $function$;

REVOKE ALL ON FUNCTION public.add_mutual_friends(uuid) FROM PUBLIC, anon, authenticated;

-- ------------------------------------------------------ 3. no-login access
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_had
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prosecdef
       AND has_function_privilege('anon', p.oid, 'EXECUTE')
  LOOP
    IF r.auth_had THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
    END IF;
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
  END LOOP;
END $$;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon;

COMMIT;
