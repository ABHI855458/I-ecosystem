import 'dart:math';

// ---------------------------------------------------------------------------
// AnonNameGenerator — a random, presentable anon-persona name, e.g.
// "silent_falcon" or "quiet_comet42".
//
// User request 2026-09-29: "the system gives automatic anon names ... no
// need to type in the profile page, they can however change it as such,
// give different names not same for everyone". OnboardingScreen used to
// hand a brand-new user an EMPTY "Anonymous name" field and require them to
// type something before they could continue; it now pre-fills this, and the
// field is still a normal, editable TextField, so nothing about "they can
// change it" is lost.
//
// `users.anon_name` has a UNIQUE constraint (users_anon_name_key) — callers
// MUST still check availability before writing one of these (same pattern
// OnboardingScreen already uses for username), this class only picks a
// plausible candidate, it never touches the database.
// ---------------------------------------------------------------------------

class AnonNameGenerator {
  const AnonNameGenerator._();

  static final _random = Random();

  static const _adjectives = [
    'silent', 'quiet', 'hidden', 'shadow', 'lone', 'wild', 'swift', 'quick',
    'bold', 'calm', 'sly', 'sharp', 'bright', 'faded', 'misty', 'stray',
    'loose', 'rogue', 'drift', 'solo', 'masked', 'veiled', 'phantom',
    'ghost', 'secret', 'muted', 'blank', 'plain', 'nameless', 'faceless',
    'unseen', 'unknown', 'vague', 'odd', 'idle', 'still', 'soft', 'dark',
    'pale', 'cool',
  ];

  static const _nouns = [
    'falcon', 'comet', 'wolf', 'raven', 'fox', 'otter', 'hawk', 'owl',
    'lynx', 'panther', 'tiger', 'heron', 'sparrow', 'crow', 'viper',
    'cobra', 'shark', 'orca', 'dolphin', 'stag', 'elk', 'bison', 'moose',
    'bear', 'eagle', 'kestrel', 'martin', 'wren', 'finch', 'swift',
    'drifter', 'wanderer', 'ranger', 'rover', 'nomad', 'ember', 'spark',
    'flare', 'echo', 'shade',
  ];

  /// One random `adjective_noun` (or `adjective_noun##` about 40% of the
  /// time, for extra spread) — different on every call, and different
  /// across users: 40 x 40 word pairs, x up to 90 with the numeric suffix,
  /// is enough combinations that two people landing on the exact same one
  /// by chance is uncommon at a campus-app scale. [avoid] is the set of
  /// candidates already tried this session (e.g. ones the availability
  /// check just rejected), so a retry loop doesn't offer the same name
  /// twice in a row.
  static String generate({Set<String> avoid = const {}}) {
    for (var attempt = 0; attempt < 20; attempt++) {
      final adj = _adjectives[_random.nextInt(_adjectives.length)];
      final noun = _nouns[_random.nextInt(_nouns.length)];
      final withNumber = _random.nextInt(5) < 2;
      final suffix = withNumber ? _random.nextInt(90) + 10 : null;
      final name = suffix == null ? '${adj}_$noun' : '${adj}_$noun$suffix';
      if (!avoid.contains(name)) return name;
    }
    // Exhausted 20 tries against [avoid] (vanishingly unlikely) — a
    // timestamp-suffixed name is always unique, just uglier.
    return 'anon_${DateTime.now().millisecondsSinceEpoch % 100000}';
  }
}
