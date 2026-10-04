// ---------------------------------------------------------------------------
// ContentModerationService — a deliberately LENIENT pre-post check, run
// client-side before a post/comment is sent.
//
// Explicit product direction: "check before posting ... don't make it too
// strict, allow a few here and there." So this is NOT a profanity filter.
// Ordinary swearing ("damn", "shit", "fuck", "bitch" used as an
// intensifier) passes untouched — students talk like students, and a
// filter that trips on that gets worked around within a day and teaches
// people the app is broken.
//
// What it DOES block is the narrow set Google Play's Inappropriate Content
// policy actually enforces removals over, where a single post can put the
// whole listing at risk:
//   * hate speech / identity-based slurs
//   * sexually explicit content
//   * direct threats of violence toward a person
//   * targeted harassment ("kill yourself" and its variants)
//
// This is a first-pass gate, not a moderation system on its own — the
// report queue (ReportService + the dashboard's resolve_report flow) is
// still the real enforcement path for anything that gets through. Being
// client-side, it is trivially bypassable by a modified client; that is
// accepted, for the same reason: this exists to stop the honest mistake
// and the impulse post, not a determined bad actor.
// ---------------------------------------------------------------------------

class ModerationResult {
  const ModerationResult.allowed() : blocked = false, reason = null;

  const ModerationResult.blockedWith(String this.reason) : blocked = true;

  final bool blocked;

  /// User-facing, non-accusatory, and specific enough to act on — never
  /// echoes the matched term back at them.
  final String? reason;
}

class ContentModerationService {
  ContentModerationService._();
  static final instance = ContentModerationService._();

  /// Identity-based slurs. Deliberately not exhaustive — this is the
  /// highest-severity bucket and the one Play removals actually cite.
  static const _slurs = <String>[
    'nigger', 'nigga', 'faggot', 'fag', 'tranny', 'retard', 'retarded',
    'chink', 'spic', 'kike', 'wetback', 'gook', 'paki', 'raghead',
    'coon', 'dyke', 'shemale',
  ];

  /// Sexually explicit terms. Mild anatomical/relationship words are
  /// deliberately absent — only the explicit register lands here.
  static const _explicit = <String>[
    'porn', 'porno', 'pornhub', 'blowjob', 'handjob', 'creampie',
    'cumshot', 'deepthroat', 'gangbang', 'bukkake', 'rimjob',
    'nudes', 'sexting', 'camgirl', 'onlyfans',
  ];

  /// Direct threats / self-harm targeting. Matched as PHRASES, not single
  /// words — "kill" alone is everyday speech ("this exam is killing me").
  static const _threatPhrases = <String>[
    'kill yourself', 'kill urself', 'kys',
    'i will kill you', 'ill kill you', 'i will murder you',
    'you should die', 'go die', 'hang yourself',
    'i will rape', 'ill rape', 'rape you',
    'shoot up the', 'bomb the',
  ];

  /// Leetspeak / padding evasion: `n1gg3r`, `f  a  g`, `fuuuuck`. Applied
  /// before matching, never shown to the user.
  static String _normalize(String input) {
    var s = input.toLowerCase();
    const subs = {
      '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't',
      '@': 'a', r'$': 's', '!': 'i',
    };
    subs.forEach((from, to) => s = s.replaceAll(from, to));
    // Collapse 3+ repeats of a letter to one ("fuuuck" -> "fuck").
    s = s.replaceAll(RegExp(r'(.)\1{2,}'), r'$1');
    // Anything that isn't a letter or space becomes a space, so
    // "f.a.g" and "f-a-g" collapse the same way punctuation-padded text does.
    s = s.replaceAll(RegExp(r'[^a-z\s]'), ' ');
    return s;
  }

  /// Same as [_normalize] but with ALL whitespace stripped — catches
  /// letter-spaced evasion ("f a g g o t"). Used only for the slur bucket,
  /// where the false-positive risk of a spaceless scan is worth it.
  static String _despaced(String normalized) => normalized.replaceAll(RegExp(r'\s+'), '');

  /// Whole-word match, so "class"/"assignment"/"analysis" never trip a
  /// substring check (the classic Scunthorpe problem).
  static bool _containsWord(String haystack, String word) =>
      RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(haystack);

  /// The one entry point. Returns [ModerationResult.allowed] for the
  /// overwhelming majority of real posts, including sweary ones.
  ModerationResult check(String text) {
    if (text.trim().isEmpty) return const ModerationResult.allowed();

    final normalized = _normalize(text);
    final despaced = _despaced(normalized);

    for (final slur in _slurs) {
      if (_containsWord(normalized, slur) || despaced.contains(slur)) {
        return const ModerationResult.blockedWith(
          'This looks like it contains a slur. Rewrite it and try again — '
          'posts like this get accounts removed.',
        );
      }
    }

    for (final phrase in _threatPhrases) {
      if (normalized.contains(phrase)) {
        return const ModerationResult.blockedWith(
          'This reads as a threat toward someone. Rewrite it and try again.',
        );
      }
    }

    for (final term in _explicit) {
      if (_containsWord(normalized, term)) {
        return const ModerationResult.blockedWith(
          "This app doesn't allow sexually explicit posts. Rewrite it and try again.",
        );
      }
    }

    return const ModerationResult.allowed();
  }
}
