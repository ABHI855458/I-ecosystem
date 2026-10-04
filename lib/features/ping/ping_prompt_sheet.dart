import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../services/content_moderation_service.dart';
import '../../services/ping_prompt_service.dart';
import '../../services/score_gain_service.dart';
import '../../services/storage_service.dart';
import 'ping_reveal_screen.dart' show PingCameraScreen, PingCapture;
import 'score_reward_dropdown.dart';

/// What a caller does when the sheet sends. [photoUrl] is the already-
/// uploaded public URL of a photo the asker attached to the ping itself
/// (null for a text-only ask) — "when a person pings he shall also send a
/// photo". Callers pass it straight to PingService, which stores it on the
/// ping so the receiver's card and the group wall can show it.
typedef PingSendHandler = FutureOr<void> Function(
  String prompt, {
  String? photoUrl,
});

/// One person or group the multi-send step can ping.
class PingRecipient {
  const PingRecipient({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.isGroup = false,
  });
  final String id;
  final String name;
  final String? avatarUrl;
  final bool isGroup;
}

/// Multi-send: the prompt, everyone picked in the "Send to" step, and the
/// optional attached photo (uploaded once, shared by every ping).
typedef PingMultiSendHandler = FutureOr<void> Function(
  String prompt,
  List<PingRecipient> to, {
  String? photoUrl,
});

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Which prompt set a ping sheet offers.
///
/// Each value maps to its OWN dashboard-editable scope in
/// `ping_sheet_prompts` — a moderator can now set the friends-feed, group
/// and ping-page lists independently. [group] and [pingPage] were both
/// [everyone] until this, so editing the friends list silently rewrote all
/// three. An unconfigured scope falls back to 'everyone' server-side
/// (ping_prompts_for_scope), and to the app's hardcoded list below that.
enum PingContext { everyone, anonymous, group, pingPage }

/// Returns when the sheet is dismissed, so callers can sequence work
/// after it (the reply-photo viewer waits on this before closing itself).
Future<void> showPingPromptSheet(
  BuildContext context, {
  required String targetName,
  required PingContext pingContext,
  VoidCallback? onSent,
  PingSendHandler? onSentPrompt,
  bool glass = false,
  double heightFraction = 0.88,
  bool roundedTopOnly = false,
  String? postId,
  bool showScoreReward = true,
  List<PingRecipient>? recipients,
  Set<String> initialSelected = const {},
  PingMultiSendHandler? onSendMany,
  bool promptless = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PingPromptSheet(
      targetName: targetName,
      pingContext: pingContext,
      onSent: onSent,
      onSentPrompt: onSentPrompt,
      glass: glass,
      heightFraction: heightFraction,
      roundedTopOnly: roundedTopOnly,
      postId: postId,
      showScoreReward: showScoreReward,
      recipients: recipients,
      initialSelected: initialSelected,
      onSendMany: onSendMany,
      promptless: promptless,
    ),
  );
}

// ---------------------------------------------------------------------------
// Prompt data
// ---------------------------------------------------------------------------

class _Prompt {
  const _Prompt({
    required this.text,
    required this.cardColor,
    this.kind = 'photo',
  });

  final String text;
  final Color cardColor;

  /// 'photo' | 'text' — how the recipient replies. The hardcoded offline
  /// fallback lists leave this at the default; only dashboard-authored
  /// prompts carry a real value.
  final String kind;

  bool get wantsTextReply => kind == 'text';
}

const _everyonePrompts = [
  // Casual / Friendly
  _Prompt(text: "Hey, want to hang out? 👋", cardColor: Color(0xFF0F2A1E)),
  _Prompt(text: "Coffee sometime? ☕", cardColor: Color(0xFF2A1A0F)),
  _Prompt(text: "Let's catch up soon!", cardColor: Color(0xFF0F1A2A)),
  _Prompt(text: "Miss you! Where you been?", cardColor: Color(0xFF2A0F1A)),
  _Prompt(text: "Long time no see!", cardColor: Color(0xFF1A0F1E)),
  _Prompt(text: "What are you up to?", cardColor: Color(0xFF0F1A1E)),
  // Activity
  _Prompt(text: "Study session? 📚", cardColor: Color(0xFF0F1E2A)),
  _Prompt(text: "Gym buddy? 💪", cardColor: Color(0xFF1E0F2A)),
  _Prompt(text: "Lunch today? 🍕", cardColor: Color(0xFF2A1E0F)),
  _Prompt(text: "Movie this weekend? 🎬", cardColor: Color(0xFF0F182A)),
  _Prompt(text: "We should hang!", cardColor: Color(0xFF2A1A0F)),
  _Prompt(text: "You free this weekend?", cardColor: Color(0xFF1E2A0F)),
  // Reaction
  _Prompt(text: "That post was 🔥", cardColor: Color(0xFF2A0F0F)),
  _Prompt(text: "You're hilarious 😂", cardColor: Color(0xFF0F2A0F)),
  _Prompt(text: "Love your vibe ✨", cardColor: Color(0xFF1E0F2A)),
  _Prompt(text: "Great photos! 📸", cardColor: Color(0xFF0F1E2A)),
  _Prompt(text: "Same vibes honestly 🙌", cardColor: Color(0xFF1A2A1A)),
  _Prompt(text: "Saw your post, let's talk!", cardColor: Color(0xFF0F0F2A)),
  // Flirty
  _Prompt(text: "Caught my eye 👀", cardColor: Color(0xFF2A0F1E)),
  _Prompt(text: "We should talk more 😊", cardColor: Color(0xFF0F2A1E)),
  // More
  _Prompt(text: "Collab on something? 🎯", cardColor: Color(0xFF0F2A2A)),
  _Prompt(text: "You good? Checking in 🤍", cardColor: Color(0xFF2A1A2A)),

  // ── Show me (photo-answerable) ──────────────────────────────────────
  // A ping is answered with a PHOTO, so the strongest prompts are the ones
  // that name a shot. Everything above this line is conversational and can
  // only really be answered in words; these can be answered instantly by
  // pointing the camera at something, which is the whole loop.
  _Prompt(text: "Show me your view right now 🌅", cardColor: Color(0xFF0F1E2A)),
  _Prompt(text: "What's on your desk? 🗂️", cardColor: Color(0xFF1E1A0F)),
  _Prompt(text: "Show me what you're eating 🍜", cardColor: Color(0xFF2A1E0F)),
  _Prompt(text: "Outfit check 👟", cardColor: Color(0xFF1A0F2A)),
  _Prompt(text: "Where are you sitting right now? 📍", cardColor: Color(0xFF0F2A1E)),
  _Prompt(text: "Show me your screen 💻", cardColor: Color(0xFF0F1A2A)),
  _Prompt(text: "What's the sky doing? ☁️", cardColor: Color(0xFF102030)),
  _Prompt(text: "Selfie, no filter, right now 📸", cardColor: Color(0xFF2A0F1A)),
  _Prompt(text: "Show me the last thing that made you laugh 😭", cardColor: Color(0xFF1E2A0F)),
  _Prompt(text: "Proof you're actually studying 📖", cardColor: Color(0xFF0F1E1A)),

  // ── Dopamine / viral ────────────────────────────────────────────────
  _Prompt(text: "Rate my day out of 10 👀", cardColor: Color(0xFF2A0F2A)),
  _Prompt(text: "Guess where I am 🗺️", cardColor: Color(0xFF0F2A2A)),
  _Prompt(text: "Bet you can't top this 😤", cardColor: Color(0xFF2A140F)),
  _Prompt(text: "Unhinged thought of the day?", cardColor: Color(0xFF1A0F1E)),
  _Prompt(text: "Drop your current song 🎧", cardColor: Color(0xFF0F1A2E)),
  _Prompt(text: "Most chaotic thing today?", cardColor: Color(0xFF2A1A0F)),
  _Prompt(text: "Say something in 3 words", cardColor: Color(0xFF14202A)),

  // ── Appreciating ────────────────────────────────────────────────────
  _Prompt(text: "You made my week better 🤍", cardColor: Color(0xFF0F2A1A)),
  _Prompt(text: "Genuinely glad you exist", cardColor: Color(0xFF1E0F2A)),
  _Prompt(text: "You're better at this than you think", cardColor: Color(0xFF0F1E2A)),
  _Prompt(text: "Thanks for showing up 🙏", cardColor: Color(0xFF1A2A1A)),
  _Prompt(text: "You've been carrying it lately 💪", cardColor: Color(0xFF2A1E14)),
  _Prompt(text: "Proud of you, seriously", cardColor: Color(0xFF0F2A22)),
];

const _anonPrompts = [
  _Prompt(text: "I relate to this so much", cardColor: Color(0xFF0F0F1E)),
  _Prompt(
    text: "You're not alone in feeling this",
    cardColor: Color(0xFF0F1E0F),
  ),
  _Prompt(text: "This needed to be said", cardColor: Color(0xFF1E0F0F)),
  _Prompt(text: "Sending you good vibes 🌙", cardColor: Color(0xFF0F0F1E)),
  _Prompt(text: "We should talk (anon)", cardColor: Color(0xFF1E1E0F)),
  _Prompt(text: "Your words matter", cardColor: Color(0xFF0F1E1E)),
  _Prompt(text: "Same here, honestly", cardColor: Color(0xFF1E0F1E)),
  _Prompt(text: "Thank you for sharing this", cardColor: Color(0xFF0F1A0F)),
  _Prompt(text: "I see you 👁️", cardColor: Color(0xFF1A0F0F)),
  _Prompt(text: "This hit different", cardColor: Color(0xFF0F0F1A)),
  _Prompt(text: "Felt this in my chest", cardColor: Color(0xFF1A1A0F)),
  _Prompt(text: "You're braver than you think", cardColor: Color(0xFF0F1A1A)),
  _Prompt(text: "Me too, honestly", cardColor: Color(0xFF1A0F1A)),
  _Prompt(text: "Hope you're okay 🤍", cardColor: Color(0xFF0F0F1E)),
  _Prompt(text: "This is real. I feel it too", cardColor: Color(0xFF1E0F0F)),

  // ── Show me (photo-answerable) ──────────────────────────────────────
  // The anon set was ~15 short reassurances, which read as an empty,
  // one-note list. These are answerable with a photo, same as the Everyone
  // set — an anon ping is still answered with the camera.
  _Prompt(text: "Show me where you are right now 🌙", cardColor: Color(0xFF0F1420)),
  _Prompt(text: "What does your night look like? ✨", cardColor: Color(0xFF14101E)),
  _Prompt(text: "Show me something small that helped today", cardColor: Color(0xFF101E14)),
  _Prompt(text: "What are you looking at right now?", cardColor: Color(0xFF1E1410)),
  _Prompt(text: "Send the view from where you're sitting", cardColor: Color(0xFF101A1E)),

  // ── Dopamine / viral ────────────────────────────────────────────────
  _Prompt(text: "Confess something harmless 👀", cardColor: Color(0xFF1E0F1A)),
  _Prompt(text: "Most overrated thing on campus?", cardColor: Color(0xFF0F1E1E)),
  _Prompt(text: "Say the thing you'd never say out loud", cardColor: Color(0xFF1A0F1E)),
  _Prompt(text: "What's the plot twist of your week?", cardColor: Color(0xFF141A0F)),
  _Prompt(text: "Unpopular opinion, go 🔥", cardColor: Color(0xFF2A0F14)),
  _Prompt(text: "Guess who this is 🎭", cardColor: Color(0xFF0F142A)),
  _Prompt(text: "Rate this anonymously, be honest", cardColor: Color(0xFF1E1E0F)),

  // ── Appreciating ────────────────────────────────────────────────────
  _Prompt(text: "Someone noticed. That's all 🤍", cardColor: Color(0xFF0F1E14)),
  _Prompt(text: "You're doing better than you think", cardColor: Color(0xFF101E1E)),
  _Prompt(text: "This made someone's day, quietly", cardColor: Color(0xFF1A1E0F)),
  _Prompt(text: "Whatever it is, you'll get through it", cardColor: Color(0xFF141020)),
  _Prompt(text: "Genuinely, thank you for posting this", cardColor: Color(0xFF0F1A1E)),
];

// ---------------------------------------------------------------------------
// Sheet widget
// ---------------------------------------------------------------------------

class PingPromptSheet extends StatefulWidget {
  const PingPromptSheet({
    super.key,
    required this.targetName,
    required this.pingContext,
    this.onSent,
    this.onSentPrompt,
    this.glass = false,
    this.heightFraction = 0.88,
    this.roundedTopOnly = false,
    this.postId,
    this.showScoreReward = true,
    this.recipients,
    this.initialSelected = const {},
    this.onSendMany,
    this.promptless = false,
  });

  /// "Ping many" without a prompt (user decision, 2026-09-30 — pings from
  /// the Ping page and Friends feed carry no prompt; Dip and groups keep
  /// theirs). Opens straight on "Send to…"; sends prompt ''. Only
  /// meaningful with [recipients].
  final bool promptless;

  /// Non-null turns on the two-step flow: pick a prompt → "Next" → pick
  /// who gets it ("Send to…", same sheet) → "Send to N". Explicit request:
  /// "first select prompt, then upon clicking send, select people in the
  /// same ping drop down". [onSendMany] receives the picks.
  final List<PingRecipient>? recipients;

  /// Pre-ticked in the "Send to" step — tapping a face opens the sheet with
  /// that person already selected, so a single ping stays one extra tap.
  final Set<String> initialSelected;

  final PingMultiSendHandler? onSendMany;

  /// Whether a successful send drops the score-reward panel.
  ///
  /// False only in the FRIENDS FEED — explicit request: "when I ping a
  /// person in friends feed no need to show the drop down of awarding
  /// points, but still the points shall get awarded". The send, and the
  /// scoring it triggers server-side, are untouched; this suppresses the
  /// confirmation panel alone.
  final bool showScoreReward;

  final String targetName;

  /// The post being pinged, when there is one. Drives which TIER of ping
  /// prompts the sheet offers — see _loadRemotePrompts. Null when composing
  /// a fresh ping from the Ping page, where the generic set is correct.
  final String? postId;

  final PingContext pingContext;
  final VoidCallback? onSent;

  /// Fires with the resolved prompt text (picked chip or the custom-typed
  /// text) the instant Send is tapped — for callers that need to actually
  /// create something from what was sent (e.g. the Ping page inserting a
  /// PingFeedEntry), unlike [onSent] which only signals completion.
  final PingSendHandler? onSentPrompt;

  /// Frosted/blurred sheet chrome (matches the Ping tab's own choice sheet)
  /// instead of the default opaque card surface. Everyone's ping button
  /// uses this; Anonymous keeps its original look.
  final bool glass;

  /// Fraction of screen height the sheet is capped at. Content beyond that
  /// scrolls inside the existing prompt-list ScrollView rather than
  /// overflowing. Default matches the original (near-full-height) sheet.
  final double heightFraction;

  /// True for a compact bottom-sheet silhouette: only the top corners are
  /// rounded and the sheet sits flush against the screen edges (no floating
  /// side/bottom margin) — used by the Anonymous feed's notch ping icon.
  /// False keeps the original floating card look (rounded on all corners,
  /// inset margin on every side).
  final bool roundedTopOnly;

  @override
  State<PingPromptSheet> createState() => _PingPromptSheetState();
}

class _PingPromptSheetState extends State<PingPromptSheet> {
  int? _selectedIndex;
  bool _editing = false;
  bool _sent = false;

  // ── Multi-send ("Send to…") step ─────────────────────────────────────
  bool get _multi => widget.recipients != null;
  int _step = 0; // 0 = prompt, 1 = pick recipients
  late final Set<String> _picked = {...widget.initialSelected};
  String _query = '';
  late final TextEditingController _editCtrl;

  /// Dashboard-authored prompts for this sheet's scope, once fetched.
  /// Null until then — the hardcoded list stands in meanwhile, so the
  /// picker is never empty and never flashes.
  List<_Prompt>? _remotePrompts;

  /// True once the server answered (or failed). Until then the sheet shows
  /// a short loading row instead of the hardcoded fallback list — showing
  /// the fallback first and swapping to the real list a beat later was the
  /// "shows something else, then suddenly changes" glitch.
  bool _remoteResolved = false;

  String get _scopeWire => switch (widget.pingContext) {
    PingContext.everyone => 'everyone',
    PingContext.anonymous => 'anonymous',
    PingContext.group => 'group',
    PingContext.pingPage => 'ping_page',
  };

  /// Anonymous is the only context with its own visual treatment; the
  /// three named-ping contexts all read as the same sheet.
  bool get _isAnon => widget.pingContext == PingContext.anonymous;

  /// Dashboard list when there is one, the app's own list otherwise. The
  /// fallback is deliberate: this list is the only way to send a ping
  /// without typing, so a failed fetch has to degrade to something usable.
  List<_Prompt> get _prompts {
    final remote = _remotePrompts;
    if (remote != null && remote.isNotEmpty) return remote;
    return _isAnon ? _anonPrompts : _everyonePrompts;
  }

  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController();
    // Explicit request, 2026-09-29 (relaying a friend's product feedback):
    // "reading and selecting a prompt was getting too friction... redesign
    // that selection step so it takes less than 2 seconds" — "instead of
    // typing, the app instantly flashes a random, playful micro-challenge".
    // The sheet now opens with a real prompt ALREADY loaded — Send is
    // already tappable on the very first frame, before _loadRemotePrompts
    // even resolves (it reads the hardcoded fallback list, which needs no
    // network round trip). The full chip list stays exactly as it was for
    // anyone who wants to browse and pick a specific one instead; this
    // only changes what the composer starts holding.
    if (widget.promptless) {
      // Nothing to write or pick — straight to choosing people.
      _step = 1;
    } else {
      _applyRandomPrompt();
    }
    _loadRemotePrompts();
  }

  /// Loads a random prompt's text straight into the composer, the same as
  /// tapping its chip would ([_selectPrompt]) — but by TEXT, not by index,
  /// since [_prompts] can point at a different list (fallback vs.
  /// dashboard-loaded) than whichever one was showing when this runs.
  /// [avoidCurrent] (the shuffle button's own case) skips repicking the
  /// exact text already in the field; meaningless on first open, when the
  /// field is still empty. Mutates fields directly, no setState — the
  /// INITIAL call runs from initState, before this widget's first build,
  /// where setState is not allowed; [_pickRandomPrompt] (below) is what the
  /// shuffle button actually taps, and wraps this in one.
  void _applyRandomPrompt({bool avoidCurrent = false}) {
    final list = _prompts;
    if (list.isEmpty) return;
    final current = _editCtrl.text.trim();
    var text = list[_random.nextInt(list.length)].text;
    if (avoidCurrent && list.length > 1) {
      while (text == current) {
        text = list[_random.nextInt(list.length)].text;
      }
    }
    _editCtrl.text = text;
    _editCtrl.selection = TextSelection.collapsed(offset: text.length);
    // No specific chip highlighted — an auto/shuffled pick reads as free
    // text, same as _selectPrompt already treats a hand-picked chip the
    // instant it lands in the field (both set _editing true).
    _editing = true;
    _selectedIndex = null;
  }

  /// The shuffle button's tap handler — same pick, wrapped to rebuild.
  void _pickRandomPrompt({bool avoidCurrent = false}) {
    HapticFeedback.selectionClick();
    setState(() => _applyRandomPrompt(avoidCurrent: avoidCurrent));
  }

  Future<void> _loadRemotePrompts() async {
    // With a post in hand, ask the server which TIER of prompts applies —
    // the question's own set, the community's set, or the generic default
    // (see PingPromptService.fetchForPost). The cache is deliberately NOT
    // consulted for that path: the answer depends on who is looking and at
    // which post, so a scope-keyed cache would serve the wrong tier.
    final postId = widget.postId;
    // Synchronous cache hits first (set before the first frame, so no
    // flicker at all on a warm cache).
    final hit = (postId != null && postId.isNotEmpty)
        ? PingPromptService.instance.cachedForPost(postId)
        : PingPromptService.instance.cached(_scopeWire);
    if (hit != null && hit.isNotEmpty) {
      _remotePrompts = _mapRemote(hit);
      _remoteResolved = true;
      return;
    }

    final rows = (postId != null && postId.isNotEmpty)
        ? await PingPromptService.instance
            .fetchForPost(postId: postId, scope: _scopeWire)
        : await PingPromptService.instance.fetch(_scopeWire);
    if (!mounted) return;
    setState(() {
      if (rows.isNotEmpty) _remotePrompts = _mapRemote(rows);
      _remoteResolved = true;
    });
  }

  /// Rows carry an optional colour; without one they cycle through the
  /// hardcoded list's own palette, so a dashboard-authored prompt looks
  /// like the rest without a moderator ever picking a hex.
  List<_Prompt> _mapRemote(List<PingSheetPrompt> rows) {
    final palette = !_isAnon
        ? _everyonePrompts
        : _anonPrompts;
    return [
      for (var i = 0; i < rows.length; i++)
        _Prompt(
          text: rows[i].text,
          cardColor: rows[i].cardColorValue != null
              ? Color(rows[i].cardColorValue!)
              : palette[i % palette.length].cardColor,
          kind: rows[i].kind,
        ),
    ];
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  /// Tapping a prompt LOADS IT INTO THE COMPOSER rather than parking it in
  /// a separate preview.
  ///
  /// This sheet used to show three different places to deal with the same
  /// one line of text at once — an empty "or write your own…" field, a
  /// read-only preview pill of the picked prompt, and an Edit button that
  /// moved the text between them — plus two different send buttons. Now
  /// there is one field, it always holds exactly what will be sent, and
  /// editing a prompt is just typing in it.
  void _selectPrompt(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
      _editCtrl.text = _prompts[index].text;
      _editCtrl.selection =
          TextSelection.collapsed(offset: _editCtrl.text.length);
      _editing = true;
    });
  }

  // The composer field is the single source of truth for both — picking a
  // chip writes into it (see _selectPrompt), so there is no second place a
  // pending prompt can live.
  bool get _canSend =>
      !_sent &&
      (widget.promptless || _editCtrl.text.trim().isNotEmpty) &&
      (!_multi || _step == 0 || _picked.isNotEmpty);

  /// A photo attached to the ping itself — "when a person pings he shall
  /// also send a photo". Held as the local file until send (so removing it
  /// costs nothing) and uploaded as part of the send.
  XFile? _photo;

  String get _resolvedText => _editCtrl.text.trim();

  Future<void> _pickPhoto() async {
    final capture = await showModalBottomSheet<PingCapture?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PingCameraScreen(
        recipientName: widget.targetName,
      ),
    );
    if (capture == null || !mounted) return;
    setState(() => _photo = capture.photo);
  }

  Future<void> _send() async {
    if (!_canSend) return;
    // A custom-written ping is user-authored text landing in someone
    // else's inbox — same lenient check every other posting path runs.
    final moderation = ContentModerationService.instance.check(_resolvedText);
    if (moderation.blocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(moderation.reason!)),
      );
      return;
    }
    // Multi flow, step 1 → on to "Send to…" instead of sending.
    if (_multi && _step == 0) {
      HapticFeedback.selectionClick();
      FocusScope.of(context).unfocus();
      setState(() => _step = 1);
      return;
    }
    HapticFeedback.heavyImpact();
    final to = _multi
        ? [for (final r in widget.recipients!) if (_picked.contains(r.id)) r]
        : const <PingRecipient>[];
    Future<void> deliver(String text, String? photoUrl) async {
      if (_multi) {
        await widget.onSendMany?.call(text, to, photoUrl: photoUrl);
      } else {
        await widget.onSentPrompt?.call(text, photoUrl: photoUrl);
      }
    }

    // Stamped before the send so the score read below sees exactly what
    // this ping credited.
    final mark = ScoreGainService.mark();
    final text = _resolvedText;
    final photo = _photo;
    // Captured while this context is still mounted — the reward outlives
    // the sheet, and a popped context can no longer resolve an Overlay.
    final overlay = Overlay.of(context, rootOverlay: true);

    // The sheet goes NOW, before the send even starts. Explicit
    // instruction: "the ping prompts drop down shall close immediately and
    // the reward thing shall be seen". It used to sit here for 2400ms
    // holding a dropdown open over a sheet you had already finished with.
    setState(() => _sent = true);
    Navigator.of(context).pop();
    widget.onSent?.call();

    // Runs after the sheet is gone. Each caller's onSentPrompt handles its
    // own failures against its own (still-mounted) screen context — see
    // ping_page's showError and anon_feed_screen's showGlassToast — so a
    // failed ping still reports itself, it just no longer blocks the close.
    // The send itself is identical either way — only whether the reward
    // panel is drawn differs. When suppressed, the same work still runs
    // (upload + onSentPrompt), it just isn't wrapped in an overlay.
    if (!widget.showScoreReward) {
      unawaited(() async {
        try {
          String? photoUrl;
          if (photo != null) {
            photoUrl = await StorageService.uploadPingPhoto(
              file: File(photo.path),
              pingId: 'outbound/${DateTime.now().millisecondsSinceEpoch}',
            );
          }
          await deliver(text, photoUrl);
        } catch (_) {
          // onSentPrompt/onSendMany already reported this to the user (a
          // toast) before rethrowing — rethrowing is only there to tell the
          // reward-overlay branch below not to show a fake "+0"; there is
          // no overlay on this branch to suppress, so nothing else to do.
        }
      }());
      return;
    }

    showScoreRewardOverlay(
      overlay: overlay,
      // Same card as an anonymous post's reward, only the number differs.
      // This was the last reward surface still dropping the COMPACT panel
      // (the default) — reported from the anon feed's "ping the author"
      // flow: "the score card is not good, it shall be same size and
      // everything same as the anon post thing". The composer already
      // passed large: true, and so does the ping-reply overlay in
      // ping_page; this call site had simply never been updated, so the
      // same action paid out on two different-looking cards depending on
      // where you started it.
      large: true,
      loadGain: () async {
        // Uploaded here rather than at capture time: the sheet has already
        // closed, so the wait costs the sender nothing, and a ping that is
        // never actually sent never uploads anything.
        String? photoUrl;
        if (photo != null) {
          photoUrl = await StorageService.uploadPingPhoto(
            file: File(photo.path),
            // No ping row exists yet — this is only the storage folder, and
            // the bucket policy keys on the caller being authenticated, not
            // on the path (see ping_photos_authenticated_upload).
            pingId: 'outbound/${DateTime.now().millisecondsSinceEpoch}',
          );
        }
        await deliver(text, photoUrl);
        return ScoreGainService.instance.since(mark);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    // The keyboard's height. The sheet's own bottom bar is where you type
    // your prompt, and it sat at the sheet's bottom edge — i.e. exactly
    // under the keyboard, so on device you could see the keys but not what
    // you were typing. Lifting by viewInsets puts the field back above it.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // The sheet also has to SHRINK by the keyboard's height, not just move
    // up: at heightFraction 0.88 a sheet that only moved would push its own
    // header off the top of the screen.
    final maxH =
        (MediaQuery.of(context).size.height - keyboard) * widget.heightFraction;
    final radius = widget.roundedTopOnly
        ? const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          )
        : BorderRadius.circular(24);

    final sheet = Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: widget.glass
          ? null
          : BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: radius,
              border: Border.all(color: AppColors.border),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isAnon
                          ? AppColors.border
                          : AppColors.coral.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _isAnon
                          ? '?'
                          : _multi
                          ? '+'
                          : widget.targetName[0].toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 18,
                        color: widget.pingContext == PingContext.anonymous
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.promptless
                            ? 'Ping people'
                            : _multi
                            ? (_step == 0 ? 'Ping someone' : 'Ping people')
                            : widget.pingContext == PingContext.anonymous
                            ? 'Send an anonymous ping'
                            : 'Ping ${widget.targetName}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.promptless
                            ? 'Tap everyone you want to ping'
                            : _multi
                            ? (_step == 0
                                ? 'Pick a prompt, then choose who gets it'
                                : 'Pick as many people as you like')
                            : widget.pingContext == PingContext.anonymous
                            ? "They won't know it's you"
                            : 'Pick a prompt or write your own',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: AppColors.border),

          // Main content
          if (_multi && _step == 1)
            Flexible(child: _buildRecipientStep(bottomPad, keyboard))
          else
          Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Prompt scroll
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isAnon ? 'anonymous prompts' : 'choose a prompt',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (!_remoteResolved)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            )
                          else
                            _PromptFlow(
                              prompts: _prompts,
                              selectedIndex:
                                  _editing ? -1 : (_selectedIndex ?? -1),
                              onSelect: _selectPrompt,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Always-visible "write your own" bar — never scrolls
                  // away, so you can type a prompt and ping in one motion
                  // without first hunting for the write-your-own chip.
                  _buildOwnPromptBar(),

                  // Action bar (preview + Send) — only once a chip is picked.


                  // With the keyboard up its inset replaces the home-
                  // indicator padding — stacking both would leave a gap the
                  // height of the safe area above the keyboard.
                  SizedBox(height: (keyboard > 0 ? 8.0 : bottomPad + 8)),
                ],
              ),
            ),
        ],
      ),
    );

    // Bottom inset = the keyboard, so the whole sheet rides above it. This
    // is the half that actually moves the typing bar into view; the maxH
    // shrink above is what stops the sheet's header being pushed off-screen
    // while it does.
    final outerPadding = widget.roundedTopOnly
        ? EdgeInsets.only(bottom: keyboard)
        : EdgeInsets.fromLTRB(8, 0, 8, 8 + keyboard);

    if (!widget.glass) {
      return Padding(padding: outerPadding, child: sheet);
    }

    return Padding(
      padding: outerPadding,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D12).withValues(alpha: 0.85),
              borderRadius: radius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: sheet,
          ),
        ),
      ),
    );
  }

  /// Constant "write your own + ping" bar pinned under the prompt grid.
  /// Typing here takes precedence over any selected chip (see [_resolvedText]
  /// / [_canSend], which both treat a non-empty draft as the live prompt).
  /// Step 2 of the multi flow: the prompt pinned on top, a search field,
  /// friends as a tap-to-tick grid, groups under them, and "Send to N".
  Widget _buildRecipientStep(double bottomPad, double keyboard) {
    const cyan = Color(0xFF29D3E8);
    final q = _query.trim().toLowerCase();
    final all = widget.recipients!;
    final visible = [
      for (final r in all)
        if (q.isEmpty || r.name.toLowerCase().contains(q)) r,
    ];
    final people = [for (final r in visible) if (!r.isGroup) r];
    final groups = [for (final r in visible) if (r.isGroup) r];
    final n = _picked.length;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: Text(
            t,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
        );

    Widget tile(PingRecipient r) {
      final on = _picked.contains(r.id);
      final initial = r.name.isEmpty ? '?' : r.name[0].toUpperCase();
      final fallback = Center(
        child: r.isGroup
            ? const Icon(Icons.groups_rounded, size: 22, color: AppColors.textMuted)
            : Text(
                initial,
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
      );
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => on ? _picked.remove(r.id) : _picked.add(r.id));
        },
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 56,
                      height: 56,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: r.isGroup ? BoxShape.rectangle : BoxShape.circle,
                        borderRadius: r.isGroup ? BorderRadius.circular(16) : null,
                        border: Border.all(
                          color: on ? cyan : Colors.white.withValues(alpha: 0.12),
                          width: on ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(r.isGroup ? 13 : 100),
                        child: ColoredBox(
                          color: AppColors.background,
                          child: (r.avatarUrl == null || r.avatarUrl!.isEmpty)
                              ? fallback
                              : CachedNetworkImage(
                                  imageUrl: r.avatarUrl!,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 160,
                                  placeholder: (_, _) => fallback,
                                  errorWidget: (_, _, _) => fallback,
                                ),
                        ),
                      ),
                    ),
                    if (on)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: cyan,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF0D0D12), width: 2),
                          ),
                          child: const Icon(Icons.check_rounded, size: 12, color: Color(0xFF0D0D12)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Shrink to fit, never "…" (explicit request, 2026-10-02).
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  r.name,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: on ? AppColors.textPrimary : AppColors.textMuted,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget grid(List<PingRecipient> xs) => Wrap(
          spacing: 12,
          runSpacing: 14,
          children: [for (final r in xs) tile(r)],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The prompt being sent, pinned so you never lose track of it —
        // nothing to pin when there is no prompt.
        if (!widget.promptless)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cyan.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              if (_photo != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(_photo!.path), width: 30, height: 30, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  '“$_resolvedText”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: widget.promptless
                          ? 'Search people'
                          : 'Search people and groups',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (people.isNotEmpty) ...[label('people'), grid(people)],
                  if (groups.isNotEmpty) ...[label('groups'), grid(groups)],
                  if (people.isEmpty && groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          all.isEmpty
                              ? 'Add people to your Friends circle to ping them'
                              : 'No one matches “$_query”',
                          style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Back + Send to N
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, keyboard > 0 ? 8 : bottomPad + 8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              // No prompt step to go back to when promptless.
              if (!widget.promptless) ...[
              GestureDetector(
                onTap: () => setState(() => _step = 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    'Back',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ],
              Expanded(
                child: GestureDetector(
                  onTap: n > 0 ? _send : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      gradient: n > 0
                          ? const LinearGradient(
                              colors: [Color(0xFF405DE6), Color(0xFF833AB4), Color(0xFFE1306C)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: n > 0 ? null : AppColors.border,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.send_rounded, size: 14, color: n > 0 ? Colors.white : Colors.white38),
                        const SizedBox(width: 6),
                        Text(
                          n == 0 ? 'Pick someone' : 'Ping $n',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: n > 0 ? Colors.white : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOwnPromptBar() {
    final hasText = _editCtrl.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Attach a photo to the ping itself. A thumbnail replaces the
          // camera glyph once one is picked; tapping it again clears it.
          GestureDetector(
            onTap: _photo == null
                ? _pickPhoto
                : () => setState(() => _photo = null),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 38,
              height: 38,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: _photo != null
                      ? const Color(0xFF29D3E8).withValues(alpha: 0.55)
                      : AppColors.border,
                ),
              ),
              child: _photo == null
                  ? const Icon(
                      Icons.photo_camera_outlined,
                      size: 17,
                      color: AppColors.textMuted,
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_photo!.path), fit: BoxFit.cover),
                        const ColoredBox(color: Color(0x59000000)),
                        const Icon(Icons.close_rounded,
                            size: 15, color: Colors.white),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: hasText
                      ? const Color(0xFF29D3E8).withValues(alpha: 0.45)
                      : AppColors.border,
                ),
              ),
              child: TextField(
                controller: _editCtrl,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  hintText: 'Pick a prompt or write your own…',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: AppColors.textMuted,
                  ),
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {
                  // typing takes over from a picked chip
                  _editing = _editCtrl.text.trim().isNotEmpty;
                }),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // "Don't like this one" — rerolls the composer to a different
          // random prompt. Same circular-glyph treatment as the camera
          // button on the left, so the bar reads as one family: attach a
          // photo, the prompt itself, get a different one, send.
          GestureDetector(
            onTap: () => _pickRandomPrompt(avoidCurrent: true),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.shuffle_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 9),
          // The sheet's ONE send control. No anchored dropdown hangs off it
          // any more: the sheet closes the instant this is tapped, so a
          // panel pinned to this button would be torn down before it could
          // be read. The reward drops in over the screen underneath instead
          // — see _send's showScoreRewardOverlay.
          GestureDetector(
              onTap: _canSend ? _send : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: hasText
                      ? const LinearGradient(
                          colors: [
                            Color(0xFF405DE6),
                            Color(0xFF833AB4),
                            Color(0xFFE1306C),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: hasText ? null : AppColors.border,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _multi
                          ? Icons.arrow_forward_rounded
                          : Icons.send_rounded,
                      size: 14,
                      color: hasText ? Colors.white : Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      // Multi flow: this bar is step 1 — "Next" leads to
                      // the "Send to…" picker.
                      _multi ? 'Next' : 'Send',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: hasText ? Colors.white : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// Prompt chip
// ---------------------------------------------------------------------------

/// Lays the prompt chips out as JUSTIFIED lines: as many chips per line as
/// fit, with each line then stretched to the full width.
///
/// This has now been both of the obvious things and neither worked. A [Wrap]
/// packed chips side by side but left a ragged gap at the end of every line,
/// because these are sentences of wildly different lengths. One chip per
/// row fixed the ragged edge but wasted most of the line on "gm ☀️".
/// Reported again as "there is a lot of empty space, fit all those prompts
/// in line".
///
/// So: measure each chip's natural width, greedily pack a line, then hand
/// the leftover space back to that line's chips in proportion to their
/// natural widths. Short prompts share a row, a long one still gets a row of
/// its own, and every line reaches both edges. Nothing is hardcoded to a
/// column count or a prompt length, so whatever set the dashboard publishes
/// lays itself out correctly.
class _PromptFlow extends StatelessWidget {
  const _PromptFlow({
    required this.prompts,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_Prompt> prompts;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Must match _PromptChip's own padding + border, or the measurement
  /// under-reports and lines overflow.
  static const _chipHPadding = 16.0;
  static const _chipBorder = 1.5;
  static const _gap = 8.0;

  /// The reply-mode icon and its trailing gap, which sit beside the text
  /// inside every chip. Counted here for the same reason the padding is:
  /// measuring the text alone under-reports the chip by exactly this much
  /// and the last chip on a line overflows.
  static const _chipIcon = 13.0 + 7.0;

  /// Below this a chip stops being a readable target, so a line never packs
  /// so tightly that its chips shrink to slivers.
  static const _minChipWidth = 96.0;

  double _naturalWidth(_Prompt p, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(
        text: p.text,
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w =
        painter.width + (_chipHPadding + _chipBorder) * 2 + _chipIcon;
    return w.clamp(_minChipWidth, maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final maxWidth = box.maxWidth;
        final widths = [
          for (final p in prompts) _naturalWidth(p, maxWidth),
        ];

        // Greedy line packing.
        final lines = <List<int>>[];
        var current = <int>[];
        var used = 0.0;
        for (var i = 0; i < prompts.length; i++) {
          final w = widths[i];
          final extra = current.isEmpty ? w : w + _gap;
          if (current.isNotEmpty && used + extra > maxWidth) {
            lines.add(current);
            current = [i];
            used = w;
          } else {
            current.add(i);
            used += extra;
          }
        }
        if (current.isNotEmpty) lines.add(current);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var l = 0; l < lines.length; l++) ...[
              if (l > 0) const SizedBox(height: _gap),
              Row(
                children: [
                  for (var c = 0; c < lines[l].length; c++) ...[
                    if (c > 0) const SizedBox(width: _gap),
                    // flex by natural width, so the leftover space is shared
                    // in proportion rather than split evenly — a long prompt
                    // sharing a line with a short one stays the longer chip.
                    Expanded(
                      flex: (widths[lines[l][c]] * 100).round(),
                      child: _PromptChip(
                        prompt: prompts[lines[l][c]],
                        selected: selectedIndex == lines[l][c],
                        onTap: () => onSelect(lines[l][c]),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PromptChip extends StatefulWidget {
  const _PromptChip({
    required this.prompt,
    required this.selected,
    required this.onTap,
  });

  final _Prompt prompt;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PromptChip> createState() => _PromptChipState();
}

class _PromptChipState extends State<_PromptChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.coral.withValues(alpha: 0.18)
                : widget.prompt.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected
                  ? AppColors.coral.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.07),
              width: widget.selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Says how the OTHER person will answer — a camera or a
              // keyboard. The library is authored ~50/50 on purpose, and
              // without this cue the sender can't tell which they're
              // asking for until the reply lands.
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 7),
                child: Icon(
                  widget.prompt.wantsTextReply
                      ? Icons.keyboard_outlined
                      : Icons.photo_camera_outlined,
                  size: 13,
                  color: (widget.selected
                          ? AppColors.coral
                          : AppColors.textPrimary)
                      .withValues(alpha: 0.55),
                ),
              ),
              Flexible(
                child: Text(
                  widget.prompt.text,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: widget.selected
                        ? AppColors.coral
                        : AppColors.textPrimary,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

