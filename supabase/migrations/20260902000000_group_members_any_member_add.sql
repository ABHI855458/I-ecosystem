-- ============================================================================
-- group_members INSERT — widen from admin/creator-only to ANY existing member.
--
-- Manual-run block, same convention as 2026-08-22_three_tier_roles.sql.
-- ============================================================================
--
-- WHAT THIS CHANGES — and it IS a widening, stated plainly: before this, the
-- only INSERT paths were `admin_add_members` (an admin of the group, or the
-- group's own created_by) and `group_members_insert_first_admin` (the
-- creator's own first admin row, when the group has no members yet). A plain
-- member could not add anyone. After this, any member can pull someone into a
-- group they belong to.
--
-- ADDITIVE, NOT A REPLACEMENT — `admin_add_members` and
-- `group_members_insert_first_admin` are both left exactly as they are.
-- Postgres combines permissive policies with OR, so the new policy only ever
-- grants; it can't narrow either existing path. Concretely, admins keep the
-- one thing this new policy deliberately withholds: inserting a row with
-- role = 'admin'.
--
-- THE role = 'member' GUARDRAIL is the whole safety story here. Without it,
-- "any member can add people" would also mean "any member can mint a new
-- admin" — and admins can remove members, delete any post, rename and delete
-- the group. Adding a peer is a social act; granting admin is a privilege
-- escalation, and this policy is not the place for it.
--
-- is_group_member/2 (membership, any role) already exists and is what
-- `group_members_select` itself uses — the same predicate, so anyone who can
-- SEE a group's roster can now also add to it. No new helper needed.
-- ============================================================================

CREATE POLICY "member_add_members" ON group_members FOR INSERT WITH CHECK (
  role = 'member'
  AND is_group_member(group_id, (SELECT id FROM users WHERE auth_id = auth.uid()))
);
