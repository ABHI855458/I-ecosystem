-- ============================================================================
-- moment_replies — real storage for a Moment's photo replies.
--
-- Until now Moments had NO replies backend at all: LockedRepliesScreen took
-- its cards as a constructor param, every real call site passed
-- `replies: const []`, and "Add yours" only set a local SharedPreferences
-- flag (see locked_replies_screen.dart's own doc comment). Nobody could ever
-- see anybody else's contribution.
--
-- A Moment itself stays what it already is — a `posts` row with
-- post_type = 'moment' (20260829040000_moment_post_type.sql). This table only
-- adds the replies hanging off it. A reply is NEVER a `posts` row: it does not
-- appear in any feed, only inside its Moment.
--
-- The reveal rule (Moments spec §4a): a viewer sees nothing until they have
-- contributed their own photo. That is enforced SERVER-side here, not by the
-- client's blur — moment_replies_select only ever returns the caller's own
-- row, and all real reading goes through get_moment_replies(), whose
-- SECURITY DEFINER body applies the unlock. A client querying the table
-- directly therefore cannot bypass the lock.
--
-- NOTE: this project's live DB migration ledger is drifted from what
-- `supabase migration list` believes is applied — this file is applied
-- directly via `supabase db query --linked -f`, not `db push`, and will not
-- gain a remote ledger row either. Same convention as
-- 20260909000000_ping_reply_selfie.sql.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.moment_replies (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  moment_post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  photo_url      TEXT NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One contribution per person per Moment — re-posting replaces (the client
-- upserts on this constraint) rather than stacking duplicate cards.
CREATE UNIQUE INDEX IF NOT EXISTS moment_replies_one_per_user
  ON public.moment_replies (moment_post_id, user_id);
CREATE INDEX IF NOT EXISTS moment_replies_moment_idx
  ON public.moment_replies (moment_post_id);

ALTER TABLE public.moment_replies ENABLE ROW LEVEL SECURITY;

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- Deliberately own-rows-only for SELECT. This is NOT the read path: the
-- unlock lives in get_moment_replies() below. Keeping the table itself
-- closed is what stops a client from reading everyone's photos with a plain
-- PostgREST select before contributing.
--
-- auth.uid() is the raw Supabase Auth id; moment_replies.user_id FKs to
-- users.id. The auth_id indirection below is mandatory — comparing them
-- directly silently matches nothing (this schema's standing trap).

DROP POLICY IF EXISTS "moment_replies_select_own" ON public.moment_replies;
CREATE POLICY "moment_replies_select_own" ON public.moment_replies FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM public.users WHERE id = moment_replies.user_id)
);

DROP POLICY IF EXISTS "moment_replies_insert_own" ON public.moment_replies;
CREATE POLICY "moment_replies_insert_own" ON public.moment_replies FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM public.users WHERE id = moment_replies.user_id)
  AND EXISTS (
    SELECT 1 FROM public.posts p
    WHERE p.id = moment_replies.moment_post_id
      AND p.post_type = 'moment'
      AND p.deleted_at IS NULL
  )
);

DROP POLICY IF EXISTS "moment_replies_update_own" ON public.moment_replies;
CREATE POLICY "moment_replies_update_own" ON public.moment_replies FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM public.users WHERE id = moment_replies.user_id)
) WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM public.users WHERE id = moment_replies.user_id)
);

DROP POLICY IF EXISTS "moment_replies_delete_own" ON public.moment_replies;
CREATE POLICY "moment_replies_delete_own" ON public.moment_replies FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM public.users WHERE id = moment_replies.user_id)
);

-- ── get_moment_replies ──────────────────────────────────────────────────────
-- The unlock, modelled on get_group_wall (20260909000000_ping_reply_selfie.
-- sql): returns NOTHING until the caller has contributed. The Moment's own
-- author is always unlocked — it is their Moment, and their photo is the
-- first card the screen draws.
--
-- Empty result == "still locked", which is exactly LockedRepliesScreen's
-- locked state, so the client needs no separate permission call.

DROP FUNCTION IF EXISTS public.get_moment_replies(uuid);

CREATE FUNCTION public.get_moment_replies(p_post_id uuid)
 RETURNS TABLE(
   reply_id    uuid,
   user_id     uuid,
   name        text,
   avatar_url  text,
   photo_url   text,
   created_at  timestamptz,
   is_me       boolean
 )
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me     UUID;
  v_author UUID;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  IF v_me IS NULL THEN
    RETURN;
  END IF;

  SELECT p.user_id INTO v_author
    FROM public.posts p
   WHERE p.id = p_post_id
     AND p.post_type = 'moment'
     AND p.deleted_at IS NULL;
  IF v_author IS NULL THEN
    RETURN;
  END IF;

  -- Locked until you contribute. The author is exempt.
  IF v_me <> v_author AND NOT EXISTS (
    SELECT 1 FROM public.moment_replies r
     WHERE r.moment_post_id = p_post_id AND r.user_id = v_me
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT r.id, r.user_id, u.name, u.profile_photo_url,
         r.photo_url, r.created_at, (r.user_id = v_me)
    FROM public.moment_replies r
    JOIN public.users u ON u.id = r.user_id
   WHERE r.moment_post_id = p_post_id
   ORDER BY r.created_at ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_moment_replies(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_moment_replies(uuid) TO authenticated;

-- ── get_moment_reply_counts ─────────────────────────────────────────────────
-- Batch contributor counts for the Moment cards currently on screen, so the
-- feed labels "N contributors" without one query per card. Same batch-RPC
-- shape as get_thread_handles (20260905030000_thread_handles_batch_rpc.sql).
-- A count is not a reveal, so this is NOT gated on having contributed — the
-- card shows the count while its photos stay locked.

DROP FUNCTION IF EXISTS public.get_moment_reply_counts(uuid[]);

CREATE FUNCTION public.get_moment_reply_counts(p_post_ids uuid[])
 RETURNS TABLE(moment_post_id uuid, n integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT r.moment_post_id, COUNT(*)::int
    FROM public.moment_replies r
   WHERE r.moment_post_id = ANY(p_post_ids)
   GROUP BY r.moment_post_id;
$function$;

REVOKE ALL ON FUNCTION public.get_moment_reply_counts(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_moment_reply_counts(uuid[]) TO authenticated;

-- ── has_replied_to_moments ──────────────────────────────────────────────────
-- Which of these Moments the caller has contributed to — backs the profile's
-- "Contributed" Moments tab (FeedService.fetchContributedMoments, which used
-- to approximate contribution with a COMMENT).

DROP FUNCTION IF EXISTS public.my_contributed_moment_ids();

CREATE FUNCTION public.my_contributed_moment_ids()
 RETURNS TABLE(moment_post_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT r.moment_post_id
    FROM public.moment_replies r
    JOIN public.users u ON u.id = r.user_id
   WHERE u.auth_id = auth.uid()
   ORDER BY r.created_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.my_contributed_moment_ids() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_contributed_moment_ids() TO authenticated;
