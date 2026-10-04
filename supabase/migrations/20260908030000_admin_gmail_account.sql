-- Abhishek's primary login becomes a dashboard admin.
--
-- abisheksdpatel@gmail.com already has both an auth account and an app
-- profile (users.id=726dc111…, the account signed in on the phone) — only the
-- moderators row was missing, so the dashboard didn't recognise it.
--
-- is_protected=true: same standing as the existing .edu admin, so neither can
-- be removed by the other or by an institutional account.
INSERT INTO public.moderators (email, role, is_protected)
VALUES ('abisheksdpatel@gmail.com', 'admin', true)
ON CONFLICT (email) DO UPDATE SET role = 'admin', is_protected = true;
