-- RealMoji reactions notified NOBODY. Fixed by ADDING a trigger to
-- post_realmoji_reactions — deliberately NOT by "repointing" the existing
-- one off `reactions`, which the notification spec's §5 asks for.
--
-- WHY THE SPEC'S FRAMING IS WRONG HERE: §5 calls `reactions` "the legacy
-- table (8 rows)" and post_realmoji_reactions "the actual live path",
-- implying one replaced the other. Both are live, and they back two
-- different features:
--
--   reactions                 <- reaction_service.dart (ordinary emoji
--                                reactions; upserts at :459/:501/:525)
--   post_realmoji_reactions   <- realmoji_service.dart:236 (RealMoji —
--                                reacting with your actual face)
--
-- Moving the trigger would have silently killed notifications for every
-- ordinary emoji reaction in order to fix RealMoji. Both now notify.
--
-- Reuses fold_reaction_notification() rather than inserting directly, so
-- RealMoji inherits the same batching the emoji path already has: one
-- notification per post that counts reactors up ("3 people reacted to your
-- post 👀") instead of one row per reaction, with same-reactor dedupe.
-- That also satisfies the spec's own §6 anonymity rule for free — the
-- folded copy is "Someone reacted"/"N people reacted" and never names the
-- reactor, so a RealMoji on an anonymous post cannot leak identity.
--
-- KNOWN GAP, LEFT FOR PHASE 2: spec §2 assigns RealMoji the STANDARD tier
-- and §3 wants "{name} reacted {emoji} to your post". fold_reaction_
-- notification writes 'minor' with anonymous copy. Matching the spec's tier
-- and copy table is Phase 2 work (the full catalog), and doing it here
-- would half-apply that phase while leaving the emoji path inconsistent.
-- Phase 0's job is that the event notifies at all — it now does.
CREATE OR REPLACE FUNCTION public.notify_realmoji_reaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_owner uuid;
BEGIN
  IF NEW.post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.posts WHERE id = NEW.post_id;
  ELSIF NEW.group_post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.group_posts WHERE id = NEW.group_post_id;
  END IF;

  -- No owner (deleted post), or you reacting to yourself: nothing to send.
  IF v_owner IS NULL OR v_owner = NEW.user_id THEN RETURN NEW; END IF;

  -- emoji_type is an ENUM here, not the plain text column `reactions` uses;
  -- the cast is the only real difference between this and notify_reaction.
  PERFORM public.fold_reaction_notification(
    v_owner, NEW.post_id, NEW.user_id, NEW.emoji_type::text
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_realmoji_reaction ON public.post_realmoji_reactions;
CREATE TRIGGER trg_notify_realmoji_reaction
AFTER INSERT ON public.post_realmoji_reactions
FOR EACH ROW EXECUTE FUNCTION public.notify_realmoji_reaction();
