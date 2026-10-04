// App-wide product switches. Flip a flag to bring a feature back — the code
// behind each one is left intact.

/// Moments are hidden everywhere (feeds, profiles, create menus, composer).
/// The daily prompt is the one ritual now; answering it always posts a Dip.
const bool kMomentsEnabled = false;

/// Fast onboarding: Profile → Clubs → straight into the app (Dip). The
/// Circles / Pin people / Duo steps are no longer gates; one Duo invite is
/// asked for (skippable) after the person's first post instead.
const bool kFastOnboarding = true;
