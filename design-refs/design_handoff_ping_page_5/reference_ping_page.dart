// ============================================================================
// Ping Page — Flutter implementation
// Single-file reference build. Split into files per the header comments when
// integrating. Requires Manrope bundled (see pubspec snippet at bottom of
// FLUTTER_SPEC.md §2.1). Null-safe, Flutter 3.x, no third-party packages.
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ============================================================================
// tokens.dart — palette, scaling, type
// ============================================================================

const double kDesignW = 402.0;

const kGround = Color(0xFF0B0B0D);
const kSurface1 = Color(0xFF131317);
const kSurface2 = Color(0xFF17171B);
const kText = Color(0xFFF5F4F1);
const kCyan = Color(0xFF29D3E8);
const kCyanLite = Color(0xFF7FE8F2);
const kCyanDeep = Color(0xFF1BAFC4);
const kCyanPale = Color(0xFFDFF9FB);
const kCyanTextHi = Color(0xE6CDF6FA); // rgba(205,246,250,.9)
const kDanger = Color(0xFFF0705E);
const kClay = Color(0xFFA9A49A);
const kDarkOnCyan = Color(0xBF0B0B0D); // rgba(11,11,13,.75)

Color txt(double o) => kText.withOpacity(o);
Color clay(double o) => kClay.withOpacity(o);
Color w(double o) => Colors.white.withOpacity(o);
Color blk(double o) => Colors.black.withOpacity(o);

/// Earth-gradient avatar pairs (index by stable id hash).
const List<List<Color>> kEarth = [
  [Color(0xFFC97B5A), Color(0xFFA85D3E)], // 0 terracotta
  [Color(0xFFB08968), Color(0xFF8B6A4F)], // 1 tan
  [Color(0xFF7A8B6F), Color(0xFF5F7355)], // 2 sage
  [Color(0xFFD2A05C), Color(0xFFB8843F)], // 3 ochre
  [Color(0xFF8A7A6D), Color(0xFF6B5D52)], // 4 taupe
  [Color(0xFF6E8B8A), Color(0xFF516B6A)], // 5 slate-teal
];

/// CSS linear-gradient(deg) -> Flutter begin/end.
LinearGradient cssGradient(double deg, List<Color> colors) {
  final rad = (deg - 90) * math.pi / 180; // CSS 0deg=up; Flutter 0rad=right
  final dx = math.cos(rad), dy = math.sin(rad);
  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: colors,
  );
}

LinearGradient g150(Color a, Color b) => cssGradient(150, [a, b]);
LinearGradient g160(Color a, Color b) => cssGradient(160, [a, b]);
LinearGradient g180(Color a, Color b) => cssGradient(180, [a, b]);
LinearGradient g90(Color a, Color b) => cssGradient(90, [a, b]);

/// Scale helper — build once per page from device width.
class Scale {
  final double k;
  Scale(double screenW) : k = (screenW.clamp(320.0, 440.0)) / kDesignW;
  double call(double px) => px * k;
  double ls(double em, double fontPx) => em * fontPx * k; // letter-spacing
}

/// Text style factory. lh = line-height multiplier (CSS unitless).
TextStyle ts(Scale s, {
  required int weight,
  required double size,
  double lh = 1.2,
  double em = 0.0,
  required Color color,
}) => TextStyle(
  fontFamily: 'Manrope',
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  fontSize: s(size),
  height: lh,
  letterSpacing: em == 0 ? null : s.ls(em, size),
  color: color,
);

/// Irregular four-corner radius (the app fingerprint).
BorderRadius r4(Scale s, double tl, double tr, double br, double bl) =>
    BorderRadius.only(
      topLeft: Radius.circular(s(tl)),
      topRight: Radius.circular(s(tr)),
      bottomRight: Radius.circular(s(br)),
      bottomLeft: Radius.circular(s(bl)),
    );

// ============================================================================
// models.dart
// ============================================================================

class InboundPing {
  final String id, senderName, initial, prompt, time;
  final int tintIndex;
  final bool isGroup, isAnon;
  final int? groupCount;
  InboundPing(this.id, this.senderName, this.initial, this.prompt, this.time,
      this.tintIndex,
      {this.isGroup = false, this.isAnon = false, this.groupCount});
}

class OutboundPing {
  final String id, who, initial, prompt;
  final bool seen;
  OutboundPing(this.id, this.who, this.initial, this.prompt, this.seen);
}

class InboundReply {
  final String id, who, prompt, body, when;
  final bool viewedInit;
  final String? pingBackLeft;
  InboundReply(this.id, this.who, this.prompt, this.body, this.when,
      this.viewedInit, this.pingBackLeft);
  bool get isAnon => who == 'Someone';
}

class Comment {
  final String who, when, text;
  final int tintIndex;
  Comment(this.who, this.when, this.text, this.tintIndex);
}

class Friend {
  final String id, who, initial;
  final int tintIndex, streak;
  Friend(this.id, this.who, this.initial, this.tintIndex, this.streak);
}

class Group {
  final String id, name;
  final int count;
  final List<int> tintIndices;
  Group(this.id, this.name, this.count, this.tintIndices);
}

class GroupTile {
  final String id, who;
  final String? text;
  final List<Color>? tint;
  GroupTile(this.id, this.who, this.text, this.tint);
  bool get answered => text != null;
}

// ---- sample data (mirrors source) ----
final kFriends = [
  Friend('n1', 'Naomi K.', 'N', 0, 12),
  Friend('n2', 'Theo', 'T', 1, 5),
  Friend('n3', 'Priya', 'P', 2, 3),
  Friend('n4', 'Marcus', 'M', 3, 1),
  Friend('n5', 'Ilana', 'I', 4, 8),
  Friend('n6', 'Sam', 'S', 5, 2),
];
final kGroups = [
  Group('g1', 'Basement Four', 4, [0, 1, 2, 3]),
  Group('g2', 'Thesis Hell', 3, [4, 5, 0]),
];
final kToReply = [
  InboundPing('f1', 'Naomi K.', 'N', "Something you're not over yet", '5h left to reply', 0),
  InboundPing('f2', 'Dev P.', 'D', "What's been weighing on you this week?", '19h left to reply', 1),
  InboundPing('a1', 'Someone', '?', "A thing you'd only admit at 2am", '9h left to reply', 4, isAnon: true),
  InboundPing('g1p', 'Basement Four', '4', 'Where were you an hour ago?', '12h left to reply', 2, isGroup: true, groupCount: 4),
];
final kSent = [
  OutboundPing('s1', 'Priya', 'P', 'The last thing that made you laugh out loud', true),
  OutboundPing('s2', 'Marcus', 'M', 'A place on campus you keep going back to', false),
  OutboundPing('as1', 'Anonymous', '?', 'What are you pretending not to want?', true),
];
final kReplies = [
  InboundReply('r1', 'Ilana', 'A song you played too many times', "It's the one from the drive back in March. I keep it on when the library gets loud.", '40m ago', false, '23h'),
  InboundReply('ar1', 'Someone', 'The version of you nobody here has met', 'I used to sing. Loudly. In front of people. I have not told anyone here that.', '3h ago', false, '24h'),
  InboundReply('r2', 'Theo', 'Something small that went right today', 'Got the espresso machine in the basement to work. Nobody saw it happen but me.', 'yesterday', true, '11h'),
  InboundReply('r3', 'Sam', 'A thing you miss about first year', 'Leaving my door open. I should probably just start doing that again.', 'last week', true, null),
];
final kPromptBank = [
  "Something you're not over yet",
  'What went right today, however small',
  "A thing you'd only admit at 2am",
  'What are you pretending not to want?',
];
final kGroupWall = <GroupTile>[
  GroupTile('gt1', 'Naomi', 'the email. still the email.', [kCyan.withOpacity(.22), const Color(0x286E8B8A)]),
  GroupTile('gt2', 'Theo', 'sleep, apparently', [const Color(0x33B08968), const Color(0x298A7A6D)]),
  GroupTile('gt3', 'Priya', 'calling my mom back', [const Color(0x337A8B6F), const Color(0x247A8B6F)]),
  GroupTile('gt4', 'Marcus', null, null),
];
const kWallGroup = 'Basement Four';
const kWallPrompt = 'What are you avoiding right now?';
const kWallWhen = '2h ago';
const kPingScore = 742;

// ============================================================================
// widgets — shared primitives
// ============================================================================

/// Frosted glass container with irregular radius.
class Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final Gradient? gradient;
  final Color? color;
  final Border? border;
  final List<BoxShadow>? shadow;
  final double blurSigma;
  const Glass({super.key, required this.child, required this.radius,
    this.gradient, this.color, this.border, this.shadow, this.blurSigma = 0});
  @override
  Widget build(BuildContext c) {
    Widget box = Container(
      decoration: BoxDecoration(
        borderRadius: radius, gradient: gradient, color: color,
        border: border, boxShadow: shadow),
      child: child,
    );
    if (blurSigma > 0) {
      box = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: box,
        ),
      );
    }
    return box;
  }
}

/// Conic progress ring (hold-to-reveal).
class RingPainter extends CustomPainter {
  final double p;
  final Color accent;
  RingPainter(this.p, this.accent);
  @override
  void paint(Canvas c, Size s) {
    final r = s.width / 2;
    final center = Offset(r, r);
    final sw = s.width * 0.08;
    final track = Paint()..style = PaintingStyle.stroke..strokeWidth = sw..color = w(.09);
    final arc = Paint()..style = PaintingStyle.stroke..strokeWidth = sw
      ..color = accent..strokeCap = StrokeCap.round;
    c.drawCircle(center, r - sw / 2, track);
    if (p > 0) {
      c.drawArc(Rect.fromCircle(center: center, radius: r - sw / 2),
          -math.pi / 2, 2 * math.pi * p, false, arc);
    }
  }
  @override
  bool shouldRepaint(RingPainter o) => o.p != p || o.accent != accent;
}

/// 45deg hatch placeholder.
class HatchPainter extends CustomPainter {
  final double stripe;
  final Color a, b;
  HatchPainter(this.stripe, this.a, this.b);
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.clipRect(Offset.zero & s);
    final pa = Paint()..color = a, pb = Paint()..color = b;
    final diag = s.width + s.height;
    double x = -s.height;
    bool flip = false;
    while (x < diag) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + stripe, 0)
        ..lineTo(x + stripe - s.height, s.height)
        ..lineTo(x - s.height, s.height)
        ..close();
      c.drawPath(path, flip ? pb : pa);
      x += stripe;
      flip = !flip;
    }
    c.restore();
  }
  @override
  bool shouldRepaint(HatchPainter o) => false;
}

/// Pulsing dot (seen / live / window).
class PulseDot extends StatefulWidget {
  final double size;
  final Color color;
  final int ms;
  const PulseDot({super.key, this.size = 5, this.color = kCyan, this.ms = 3000});
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController ctl =
      AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms))..repeat(reverse: true);
  @override
  void dispose() { ctl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: ctl,
    builder: (_, __) {
      final t = Curves.easeInOut.transform(ctl.value);
      final o = ui.lerpDouble(.35, 1, t)!;
      final sc = ui.lerpDouble(1, 1.35, t)!;
      return Transform.scale(
        scale: sc,
        child: Container(
          width: widget.size, height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(o),
            boxShadow: [BoxShadow(color: widget.color.withOpacity(.9), blurRadius: 9)],
          ),
        ),
      );
    },
  );
}

/// Spring-tap wrapper (scale .94 + rotate -1deg).
class SpringTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const SpringTap({super.key, required this.child, this.onTap});
  @override
  State<SpringTap> createState() => _SpringTapState();
}

class _SpringTapState extends State<SpringTap> {
  bool down = false;
  @override
  Widget build(BuildContext c) => GestureDetector(
    onTapDown: (_) => setState(() => down = true),
    onTapUp: (_) => setState(() => down = false),
    onTapCancel: () => setState(() => down = false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: down ? .94 : 1,
      duration: const Duration(milliseconds: 180),
      curve: const Cubic(.34, 1.56, .64, 1),
      child: AnimatedRotation(
        turns: down ? -1 / 360 : 0,
        duration: const Duration(milliseconds: 180),
        curve: const Cubic(.34, 1.56, .64, 1),
        child: widget.child,
      ),
    ),
  );
}

// ============================================================================
// app + page
// ============================================================================

void main() => runApp(const PingApp());

class PingApp extends StatelessWidget {
  const PingApp({super.key});
  @override
  Widget build(BuildContext c) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(backgroundColor: kGround, body: PingPage()),
  );
}

class PingPage extends StatefulWidget {
  const PingPage({super.key});
  @override
  State<PingPage> createState() => _PingPageState();
}

class _PingPageState extends State<PingPage> with TickerProviderStateMixin {
  // ---- state (mirror of source Component.state) ----
  final revealed = <String, DateTime>{};
  String? openId;
  final viewed = <String, bool>{};
  final captured = <String, bool>{};
  final mediaOpen = <String, bool>{};
  final sentReplies = <String, List<String>>{};
  final pingedBack = <String, bool>{};
  String? composeFor;
  String composeDraft = '';
  final groupPicks = <String, bool>{};
  String? replyDetailId;
  String replyDraft = '';

  double holdSeconds = 1.0;
  final accent = kCyan;

  // ---- hold ticker ----
  String? holdId;
  double holdP = 0;
  AnimationController? _hold;

  void startHold(String id, bool isPing) {
    _hold?.dispose();
    _hold = AnimationController(vsync: this, duration: Duration(milliseconds: (holdSeconds * 1000).round()))
      ..addListener(() => setState(() => holdP = _hold!.value))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) finishHold(id, isPing);
      });
    setState(() { holdId = id; holdP = 0; });
    _hold!.forward();
  }

  void endHold() {
    if (_hold != null && _hold!.value < 1) {
      _hold!.stop();
      setState(() { holdId = null; holdP = 0; });
    }
  }

  void finishHold(String id, bool isPing) {
    setState(() {
      holdId = null; holdP = 0;
      if (isPing) { revealed[id] = DateTime.now(); openId = id; }
      else { viewed[id] = true; }
    });
  }

  @override
  void dispose() { _hold?.dispose(); super.dispose(); }

  String windowLeft(DateTime at) {
    final ms = at.add(const Duration(hours: 3)).difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 'window closed';
    final h = ms ~/ 3600000, m = (ms % 3600000) ~/ 60000;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  // ---- derived: open loops (bidirectional, incl. anon + group) ----
  List<_Loop> get loops {
    final out = <_Loop>[];
    for (final p in kToReply) {
      if ((sentReplies[p.id] ?? []).isEmpty || (pingedBack[p.id] ?? false)) continue;
      out.add(_Loop(
        id: p.id,
        initial: p.isAnon ? '?' : p.initial,
        title: p.isAnon ? 'Ping them back?' : 'Ping ${p.isGroup ? p.senderName : p.senderName.split(' ').first} back?',
        reason: p.isGroup ? 'you replied to the group' : 'you replied to theirs',
        left: '24h left',
        isAnon: p.isAnon, tintIndex: p.tintIndex,
        onTap: () => setState(() { pingedBack[p.id] = true; composeFor = null; }),
      ));
    }
    for (final r in kReplies) {
      final v = viewed[r.id] ?? r.viewedInit;
      if (!(v && r.pingBackLeft != null && !(pingedBack[r.id] ?? false))) continue;
      out.add(_Loop(
        id: r.id, initial: r.isAnon ? '?' : r.who[0],
        title: r.isAnon ? 'Ping them back?' : 'Ping ${r.who} back?',
        reason: 'they replied to yours', left: '${r.pingBackLeft} left',
        isAnon: r.isAnon, tintIndex: 0,
        onTap: () => setState(() => pingedBack[r.id] = true),
      ));
    }
    return out;
  }

  bool get wallUnlocked => (sentReplies['g1p'] ?? []).isNotEmpty;

  @override
  Widget build(BuildContext ctx) {
    final s = Scale(MediaQuery.of(ctx).size.width);
    final safeTop = MediaQuery.of(ctx).padding.top;
    final safeBottom = MediaQuery.of(ctx).padding.bottom;

    return Stack(children: [
      const _Ambient(),
      Positioned.fill(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: safeTop + s(12), bottom: safeBottom + s(46)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(s),
            _pingSomeone(s),
            if (loops.isNotEmpty) _loops(s),
            if (composeFor != null) _compose(s),
            _toReplySection(s),
            _repliesSection(s),
            _groupWall(s),
            _sentSection(s),
            Padding(
              padding: EdgeInsets.only(left: s(22), right: s(22), top: s(6)),
              child: Center(child: Text('that\u2019s everything \u00b7 no feed, no streaks',
                  style: ts(s, weight: 400, size: 10.5, color: txt(.2)))),
            ),
          ]),
        ),
      ),
      if (replyDetailId != null) _detail(s),
    ]);
  }

  // ---------- HEADER ----------
  Widget _header(Scale s) {
    final tier = kPingScore >= 700
        ? ['Deeply Present', '', '']
        : kPingScore >= 400 ? ['Showing Up', '', ''] : ['Getting Started', '', ''];
    final tierColor = kPingScore >= 700 ? kGround : kPingScore >= 400 ? txt(.85) : txt(.5);
    final tierBg = kPingScore >= 700 ? kCyan : kPingScore >= 400 ? w(.08) : Colors.transparent;
    final tierBorder = kPingScore >= 700 ? kCyan : kPingScore >= 400 ? w(.18) : w(.14);
    return Padding(
      padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(18)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CAMPUS \u00b7 BROWN', style: ts(s, weight: 500, size: 10, em: .22, color: txt(.34))),
          SizedBox(height: s(5)),
          Text('Ping', style: ts(s, weight: 800, size: 28, lh: 1.15, em: -.03, color: kText)),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('$kPingScore', style: ts(s, weight: 800, size: 21, lh: 1, em: -.02, color: kText)),
            SizedBox(width: s(5)),
            Text('score', style: ts(s, weight: 400, size: 10, color: txt(.34))),
          ]),
          SizedBox(height: s(5)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: s(9), vertical: s(3)),
            decoration: BoxDecoration(color: tierBg, borderRadius: BorderRadius.circular(100),
              border: Border.all(color: tierBorder, width: 1)),
            child: Text(tier[0], style: ts(s, weight: 500, size: 10, em: .04, color: tierColor)),
          ),
        ]),
      ]),
    );
  }

  // ---------- PING SOMEONE ----------
  Widget _pingSomeone(Scale s) => Padding(
    padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(20)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: EdgeInsets.only(bottom: s(10)),
        child: Text('PING SOMEONE', style: ts(s, weight: 500, size: 11, em: .18, color: txt(.4)))),
      SizedBox(height: s(84), child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final f in kFriends) ...[_friendTile(s, f), SizedBox(width: s(14))],
      ])),
      SizedBox(height: s(14)),
      SizedBox(height: s(42), child: ListView(scrollDirection: Axis.horizontal, children: [
        _newGroupChip(s), SizedBox(width: s(10)),
        for (final g in kGroups) ...[_groupChip(s, g), SizedBox(width: s(10))],
      ])),
    ]),
  );

  Widget _friendTile(Scale s, Friend f) => GestureDetector(
    onTap: () => setState(() { composeFor = f.id; composeDraft = ''; }),
    child: SizedBox(width: s(56), child: Column(children: [
      SizedBox(width: s(52), height: s(52), child: Stack(clipBehavior: Clip.none, children: [
        Container(width: s(52), height: s(52), alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: g160(kEarth[f.tintIndex][0], kEarth[f.tintIndex][1]),
            border: Border.all(color: w(.14), width: 1)),
          child: Text(f.initial, style: ts(s, weight: 500, size: 16, color: kDarkOnCyan))),
        Positioned(bottom: -s(3), right: -s(3), child: Container(
          padding: EdgeInsets.symmetric(horizontal: s(5), vertical: s(2)),
          decoration: BoxDecoration(color: kGround, borderRadius: BorderRadius.circular(100),
            border: Border.all(color: w(.14), width: 1)),
          child: Text('\ud83d\udd25${f.streak}', style: ts(s, weight: 400, size: 8.5, color: kCyan)))),
      ])),
      SizedBox(height: s(6)),
      Text(f.who, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: ts(s, weight: 400, size: 10.5, color: txt(.55))),
    ])),
  );

  Widget _newGroupChip(Scale s) => GestureDetector(
    onTap: () => setState(() { composeFor = 'newgroup'; composeDraft = ''; }),
    child: Container(
      padding: EdgeInsets.only(left: s(11), top: s(8), right: s(15), bottom: s(8)),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
        color: kCyan.withOpacity(.06),
        border: Border.all(color: kCyan.withOpacity(.4), width: 1)), // dashed → solid approx
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: s(24), height: s(24), alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle,
            border: Border.all(color: kCyan.withOpacity(.45), width: 1)),
          child: Text('+', style: ts(s, weight: 300, size: 15, lh: 1, color: kCyanTextHi))),
        SizedBox(width: s(9)),
        Text('New group', style: ts(s, weight: 500, size: 12, color: kCyanTextHi)),
      ]),
    ),
  );

  Widget _groupChip(Scale s, Group g) => GestureDetector(
    onTap: () => setState(() { composeFor = g.id; composeDraft = ''; }),
    child: Container(
      padding: EdgeInsets.only(left: s(10), top: s(8), right: s(14), bottom: s(8)),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
        color: w(.04), border: Border.all(color: w(.1), width: 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: s(24) + s(11) * (g.tintIndices.length - 1), height: s(24),
          child: Stack(children: [
            for (int i = 0; i < g.tintIndices.length; i++)
              Positioned(left: s(11) * i, child: Container(width: s(24), height: s(24),
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: g160(kEarth[g.tintIndices[i]][0], kEarth[g.tintIndices[i]][1]),
                  border: Border.all(color: kGround, width: 1.5)))),
          ])),
        SizedBox(width: s(10)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(g.name, style: ts(s, weight: 500, size: 12, color: txt(.88))),
          SizedBox(height: s(1)),
          Text('${g.count} people', style: ts(s, weight: 400, size: 9.5, color: txt(.34))),
        ]),
      ]),
    ),
  );

  // ---------- OPEN LOOPS ----------
  Widget _loops(Scale s) {
    final ls = loops;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(9)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('OPEN LOOPS', style: ts(s, weight: 500, size: 11, em: .18, color: kCyan.withOpacity(.75))),
          Text(ls.length == 1 ? '1 waiting' : '${ls.length} waiting',
            style: ts(s, weight: 400, size: 10, color: txt(.28))),
        ])),
      Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(22)),
        child: Column(children: [
          for (int i = 0; i < ls.length; i++) ...[
            _loopRow(s, ls[i]), if (i < ls.length - 1) SizedBox(height: s(9)),
          ],
        ])),
    ]);
  }

  Widget _loopRow(Scale s, _Loop l) => Container(
    padding: EdgeInsets.symmetric(horizontal: s(15), vertical: s(13)),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
      gradient: g90(kCyan.withOpacity(.16), kCyan.withOpacity(.08)),
      border: Border.all(color: w(.13), width: 1),
      boxShadow: [BoxShadow(color: kCyan.withOpacity(.1), blurRadius: s(26))]),
    child: Row(children: [
      Container(width: s(32), height: s(32), alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: l.isAnon ? null : g160(kEarth[l.tintIndex][0], kEarth[l.tintIndex][1]),
          color: l.isAnon ? clay(.12) : null,
          border: Border.all(color: l.isAnon ? clay(.5) : w(.16), width: l.isAnon ? 1.5 : 1)),
        child: Text(l.initial, style: ts(s, weight: 500, size: 12, color: l.isAnon ? clay(.9) : kDarkOnCyan))),
      SizedBox(width: s(12)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.title, style: ts(s, weight: 500, size: 13, color: txt(.94))),
        SizedBox(height: s(2)),
        Text('${l.reason} \u00b7 ${l.left}', style: ts(s, weight: 400, size: 10, color: txt(.42))),
      ])),
      SizedBox(width: s(12)),
      GestureDetector(onTap: l.onTap, child: Container(
        padding: EdgeInsets.symmetric(horizontal: s(15), vertical: s(9)),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
          gradient: g180(kCyanLite, kCyan),
          boxShadow: [BoxShadow(color: kCyan.withOpacity(.3), blurRadius: s(22))]),
        child: Text('Ping back', style: ts(s, weight: 500, size: 12, color: kGround)))),
    ]),
  );

  // ---------- COMPOSE ----------
  Widget _compose(Scale s) {
    final id = composeFor!;
    final isNewGroup = id == 'newgroup';
    final friend = kFriends.where((f) => f.id == id).toList();
    final group = kGroups.where((g) => g.id == id).toList();
    final who = friend.isNotEmpty ? friend.first.who
        : group.isNotEmpty ? group.first.name
        : isNewGroup ? 'a new group' : '';
    final picked = groupPicks.values.where((v) => v).length;
    return _SheetIn(
      key: ValueKey('compose-$id'),
      child: Container(
        margin: EdgeInsets.only(left: s(22), right: s(22), bottom: s(20)),
        padding: EdgeInsets.all(s(16)),
        decoration: BoxDecoration(borderRadius: r4(s, 28, 12, 26, 14),
          gradient: g160(w(.09), w(.04)),
          border: Border.all(color: w(.13), width: 1),
          boxShadow: [
            BoxShadow(color: blk(.4), blurRadius: s(40), offset: Offset(0, s(18))),
            BoxShadow(color: kCyan.withOpacity(.08), blurRadius: s(30)),
          ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Ping $who', style: ts(s, weight: 500, size: 13.5, color: kText)),
            const Spacer(),
            GestureDetector(onTap: () => setState(() { composeFor = null; composeDraft = ''; }),
              child: Container(width: s(26), height: s(26), alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: w(.06),
                  border: Border.all(color: w(.1), width: 1)),
                child: Text('\u00d7', style: ts(s, weight: 400, size: 13, lh: 1, color: txt(.6))))),
          ]),
          SizedBox(height: s(12)),
          if (isNewGroup) ...[
            Text('WHO\u2019S IN \u00b7 $picked PICKED', style: ts(s, weight: 400, size: 10, em: .1, color: txt(.34))),
            SizedBox(height: s(9)),
            Wrap(spacing: s(7), runSpacing: s(7), children: [
              for (final f in kFriends) GestureDetector(
                onTap: () => setState(() => groupPicks[f.id] = !(groupPicks[f.id] ?? false)),
                child: Container(
                  padding: EdgeInsets.only(left: s(7), top: s(6), right: s(12), bottom: s(6)),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
                    color: (groupPicks[f.id] ?? false) ? kCyan.withOpacity(.14) : w(.04),
                    border: Border.all(color: (groupPicks[f.id] ?? false) ? kCyan.withOpacity(.4) : w(.1), width: 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: s(20), height: s(20), decoration: BoxDecoration(shape: BoxShape.circle,
                      gradient: g160(kEarth[f.tintIndex][0], kEarth[f.tintIndex][1]))),
                    SizedBox(width: s(7)),
                    Text(f.who, style: ts(s, weight: 400, size: 11.5, color: txt(.8))),
                  ]))),
            ]),
            SizedBox(height: s(4)),
            Container(height: 1, color: w(.08)), SizedBox(height: s(12)),
          ],
          ConstrainedBox(constraints: BoxConstraints(maxHeight: s(220)),
            child: SingleChildScrollView(child: Column(children: [
              for (int i = 0; i < kPromptBank.length; i++) ...[
                _PromptIn(delayMs: 50 + i * 50, child: GestureDetector(
                  onTap: () => setState(() { composeFor = null; }),
                  child: Container(width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: s(14), vertical: s(12)),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
                      color: w(.04), border: Border.all(color: w(.1), width: 1)),
                    child: Text(kPromptBank[i], style: ts(s, weight: 400, size: 13.5, lh: 1.4, color: txt(.85)))))),
                if (i < kPromptBank.length - 1) SizedBox(height: s(8)),
              ],
            ]))),
          SizedBox(height: s(12)),
          Container(
            padding: EdgeInsets.only(left: s(16), top: s(4), right: s(6), bottom: s(4)),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
              color: w(.05), border: Border.all(color: w(.1), width: 1)),
            child: Row(children: [
              Expanded(child: TextField(
                onChanged: (v) => setState(() => composeDraft = v),
                style: ts(s, weight: 400, size: 14, color: kText),
                decoration: InputDecoration(isDense: true, border: InputBorder.none,
                  hintText: 'or write your own prompt\u2026',
                  hintStyle: ts(s, weight: 400, size: 14, color: txt(.4))))),
              GestureDetector(onTap: composeDraft.trim().isEmpty ? null
                : () => setState(() { composeFor = null; composeDraft = ''; }),
                child: Container(padding: EdgeInsets.symmetric(horizontal: s(18), vertical: s(10)),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
                    gradient: composeDraft.trim().isNotEmpty ? g180(kCyan, kCyanDeep) : null,
                    color: composeDraft.trim().isEmpty ? w(.07) : null),
                  child: Text('Send', style: ts(s, weight: 500, size: 13,
                    color: composeDraft.trim().isNotEmpty ? kGround : txt(.4))))),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---------- TO REPLY ----------
  Widget _toReplySection(Scale s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(8)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('TO REPLY', style: ts(s, weight: 500, size: 11, em: .18, color: txt(.72))),
        Text('${kToReply.length} waiting', style: ts(s, weight: 400, size: 11, color: txt(.3))),
      ])),
    Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(30)),
      child: Column(children: [
        for (int i = 0; i < kToReply.length; i++) ...[
          _toReplyItem(s, kToReply[i]),
          if (i < kToReply.length - 1) SizedBox(height: s(12)),
        ],
      ])),
  ]);

  Widget _toReplyItem(Scale s, InboundPing p) {
    final isRevealed = revealed.containsKey(p.id);
    if (openId == p.id) return _expandedCard(s, p);
    if (isRevealed) return _revealedCollapsed(s, p);
    return _blurredRow(s, p);
  }

  Widget _blurredRow(Scale s, InboundPing p) {
    final active = holdId == p.id;
    final pr = active ? holdP : 0.0;
    final glow = active
        ? [BoxShadow(color: blk(.45), blurRadius: s(40), offset: Offset(0, s(10))),
           BoxShadow(color: kCyan.withOpacity(.1 + .25 * pr), blurRadius: s(18 + 30 * pr))]
        : [BoxShadow(color: blk(.3), blurRadius: s(24), offset: Offset(0, s(6)))];
    return GestureDetector(
      onTapDown: (_) => startHold(p.id, true),
      onTapUp: (_) => endHold(),
      onTapCancel: endHold,
      child: Glass(
        radius: r4(s, 26, 14, 30, 10),
        gradient: g150(w(.07), w(.03)),
        border: Border.all(color: w(.1), width: 1),
        blurSigma: 11,
        shadow: glow,
        child: SizedBox(
          child: Stack(children: [
            Padding(
              padding: EdgeInsets.only(left: s(18), top: s(17), right: s(90), bottom: s(17)),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: (9 * (1 - pr)) / 2, sigmaY: (9 * (1 - pr)) / 2),
                child: Row(children: [
                  _avatar(s, p),
                  SizedBox(width: s(13)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.isGroup ? '${p.senderName} \u00b7 ${p.groupCount} people' : p.senderName,
                      style: ts(s, weight: 500, size: 13, color: p.isAnon ? clay(.85) : txt(.62))),
                    SizedBox(height: s(5)),
                    Text(p.prompt, style: ts(s, weight: 500, size: 16, lh: 1.35, color: kText)),
                  ])),
                ]),
              ),
            ),
            Positioned(top: 0, right: 0, bottom: 0, width: s(90),
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: cssGradient(270, [w(.06), Colors.transparent])),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: s(42), height: s(42), child: Stack(alignment: Alignment.center, children: [
                    if (active) Container(width: s(62), height: s(62),
                      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                        BoxShadow(color: kCyan.withOpacity(.12 + .4 * pr), blurRadius: s(10 + 26 * pr))])),
                    CustomPaint(size: Size(s(42), s(42)), painter: RingPainter(pr, accent)),
                    Container(width: s(7), height: s(7),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: txt(.65))),
                  ])),
                  SizedBox(height: s(6)),
                  SizedBox(width: s(78), child: Text(
                    active ? (pr < .99 ? 'keep holding' : 'opening') : 'hold ${holdSeconds.toStringAsFixed(1)}s to reveal',
                    textAlign: TextAlign.center,
                    style: ts(s, weight: 400, size: 8.5, lh: 1.3, em: .06,
                      color: active ? kCyan.withOpacity(.85) : txt(.28)))),
                ]),
              )),
          ]),
        ),
      ),
    );
  }

  Widget _avatar(Scale s, InboundPing p) => Container(
    width: s(36), height: s(36), alignment: Alignment.center,
    decoration: BoxDecoration(shape: BoxShape.circle,
      gradient: p.isAnon ? null : g160(kEarth[p.tintIndex][0], kEarth[p.tintIndex][1]),
      color: p.isAnon ? clay(.12) : null,
      border: Border.all(color: p.isAnon ? clay(.5) : w(.14), width: p.isAnon ? 1.5 : 1)),
    child: Text(p.initial, style: ts(s, weight: 500, size: 13, color: p.isAnon ? clay(.9) : kDarkOnCyan)),
  );

  Widget _revealedCollapsed(Scale s, InboundPing p) => GestureDetector(
    onTap: () => setState(() => openId = p.id),
    child: Glass(
      radius: r4(s, 26, 14, 30, 10),
      gradient: g150(kCyan.withOpacity(.08), w(.03)),
      border: Border.all(color: kCyan.withOpacity(.28), width: 1),
      shadow: [BoxShadow(color: blk(.3), blurRadius: s(24), offset: Offset(0, s(6)))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(left: s(18), top: s(17), right: s(20), bottom: s(0)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _avatar(s, p), SizedBox(width: s(13)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.senderName, style: ts(s, weight: 500, size: 13, color: txt(.62))),
              SizedBox(height: s(5)),
              Text(p.prompt, style: ts(s, weight: 500, size: 16, lh: 1.35, color: kText)),
            ])),
          ])),
        Padding(padding: EdgeInsets.only(left: s(67), right: s(20), top: s(0), bottom: s(15)),
          child: Row(children: [
            PulseDot(size: s(5)), SizedBox(width: s(8)),
            Text('window open \u00b7 ${windowLeft(revealed[p.id]!)} to send more',
              style: ts(s, weight: 400, size: 11.5, color: kCyan.withOpacity(.75))),
          ])),
      ]),
    ),
  );

  Widget _expandedCard(Scale s, InboundPing p) {
    final cap = captured[p.id] ?? false;
    final cam = mediaOpen[p.id] ?? false;
    final sent = sentReplies[p.id] ?? [];
    final canSend = cap;
    return Stack(children: [
      Glass(
        radius: r4(s, 30, 12, 34, 16),
        gradient: g160(w(.09), w(.045)),
        border: Border.all(color: w(.13), width: 1),
        blurSigma: 12,
        shadow: [
          BoxShadow(color: blk(.45), blurRadius: s(44), offset: Offset(0, s(18))),
          BoxShadow(color: kCyan.withOpacity(.08), blurRadius: s(32)),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: EdgeInsets.only(left: s(16), top: s(14), right: s(16), bottom: s(12)),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: w(.08)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: s(32), height: s(32), alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: p.isAnon ? null : g160(kEarth[p.tintIndex][0], kEarth[p.tintIndex][1]),
                    color: p.isAnon ? clay(.12) : null,
                    border: Border.all(color: p.isAnon ? clay(.5) : w(.16), width: p.isAnon ? 1.5 : 1)),
                  child: Text(p.initial, style: ts(s, weight: 500, size: 12, color: p.isAnon ? clay(.9) : kDarkOnCyan))),
                SizedBox(width: s(10)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.senderName, style: ts(s, weight: 500, size: 12.5, color: kText)),
                  SizedBox(height: s(2)),
                  Text('pinged you \u00b7 ${p.time}', style: ts(s, weight: 400, size: 10, color: txt(.36))),
                ])),
                Container(padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(5)),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
                    color: kCyan.withOpacity(.1), border: Border.all(color: kCyan.withOpacity(.24), width: 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    PulseDot(size: s(5)), SizedBox(width: s(5)),
                    Text('open', style: ts(s, weight: 400, size: 9.5, color: kCyan.withOpacity(.8))),
                  ])),
              ]),
              SizedBox(height: s(11)),
              Text(p.prompt, style: ts(s, weight: 500, size: 17, lh: 1.35, em: -.01, color: kText)),
            ]),
          ),
          Padding(padding: EdgeInsets.all(s(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () => setState(() => mediaOpen[p.id] = true),
              child: Container(width: s(120), height: s(150), alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
                  color: w(.03), border: Border.all(color: w(.2), width: 1.5)),
                child: cap
                  ? Text('[ frame ]', style: ts(s, weight: 400, size: 11, color: txt(.62)))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(width: s(46), height: s(46), alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          border: Border.all(color: w(.24), width: 1.5)),
                        child: Text('+', style: ts(s, weight: 300, size: 22, lh: 1, color: txt(.65)))),
                      SizedBox(height: s(9)),
                      Text('add photo', style: ts(s, weight: 400, size: 10.5, color: txt(.34))),
                    ]))),
            SizedBox(height: s(10)),
            Container(
              padding: EdgeInsets.only(left: s(14), top: s(4), right: s(5), bottom: s(4)),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
                color: w(.05), border: Border.all(color: w(.1), width: 1)),
              child: Row(children: [
                Expanded(child: TextField(
                  onChanged: (v) => setState(() => replyDraft = v),
                  style: ts(s, weight: 400, size: 13, color: kText),
                  decoration: InputDecoration(isDense: true, border: InputBorder.none,
                    hintText: 'say something\u2026', hintStyle: ts(s, weight: 400, size: 13, color: txt(.4))))),
                GestureDetector(
                  onTap: () => setState(() {
                    if (!cap) { captured[p.id] = true; return; }
                    (sentReplies[p.id] ??= []).add(replyDraft.trim().isEmpty ? 'photo only' : replyDraft.trim());
                    captured[p.id] = false; replyDraft = '';
                  }),
                  child: Container(padding: EdgeInsets.symmetric(horizontal: s(15), vertical: s(8)),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
                      gradient: canSend ? g180(kCyan, kCyanDeep) : null,
                      color: canSend ? null : w(.07),
                      boxShadow: canSend ? [BoxShadow(color: kCyan.withOpacity(.3), blurRadius: s(26))] : null),
                    child: Text('Send', style: ts(s, weight: 500, size: 12, color: canSend ? kGround : txt(.4))))),
              ]),
            ),
            if (sent.isNotEmpty) ...[
              SizedBox(height: s(11)),
              for (final txtLine in sent) Padding(padding: EdgeInsets.only(bottom: s(6)),
                child: Container(padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(7)),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(11),
                    color: kCyan.withOpacity(.07), border: Border.all(color: kCyan.withOpacity(.16), width: 1)),
                  child: Row(children: [
                    Container(width: s(20), height: s(26), decoration: BoxDecoration(borderRadius: BorderRadius.circular(4),
                      color: w(.08))),
                    SizedBox(width: s(8)),
                    Expanded(child: Text(txtLine, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: ts(s, weight: 400, size: 11, color: txt(.66)))),
                    Text('sent', style: ts(s, weight: 400, size: 9, color: kCyan.withOpacity(.7))),
                  ]))),
              Padding(padding: EdgeInsets.only(left: s(2)),
                child: Text('unlimited within the window \u2014 send more anytime',
                  style: ts(s, weight: 400, size: 9.5, color: txt(.3)))),
            ],
          ])),
        ]),
      ),
      if (cam) _cameraOverlay(s, p),
    ]);
  }

  Widget _cameraOverlay(Scale s, InboundPing p) {
    final cap = captured[p.id] ?? false;
    return Positioned.fill(child: ClipRRect(borderRadius: r4(s, 30, 12, 34, 16), child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: HatchPainter(s(10), w(.055), w(.02)))),
      Center(child: cap
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            Text('[ captured frame ]', style: ts(s, weight: 400, size: 11, color: txt(.62))),
            SizedBox(height: s(9)),
            GestureDetector(onTap: () => setState(() => captured[p.id] = false),
              child: Container(padding: EdgeInsets.symmetric(horizontal: s(14), vertical: s(7)),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
                  color: const Color(0x660B0B0D), border: Border.all(color: w(.16), width: 1)),
                child: Text('retake', style: ts(s, weight: 400, size: 10.5, color: txt(.7))))),
          ])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            Text('[ back camera preview ]', style: ts(s, weight: 400, size: 11, color: txt(.4))),
            SizedBox(height: s(4)),
            Text('dual \u00b7 reply in the moment', style: ts(s, weight: 400, size: 10, color: txt(.24))),
          ])),
      if (!cap) Positioned(bottom: s(12), right: s(12), child: Container(
        width: s(76), height: s(96), alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: w(.06),
          border: Border.all(color: w(.5), width: 1.5),
          boxShadow: [BoxShadow(color: blk(.4), blurRadius: s(16), offset: Offset(0, s(4)))]),
        child: Text('front', style: ts(s, weight: 400, size: 8, color: txt(.4))))),
      Positioned(top: s(12), left: s(12), child: Container(
        padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(5)),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
          color: const Color(0x6B0B0B0D), border: Border.all(color: w(.1), width: 1)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PulseDot(size: s(5), ms: 2600), SizedBox(width: s(6)),
          Text('LIVE', style: ts(s, weight: 400, size: 9.5, em: .1, color: txt(.6))),
        ]))),
      Positioned(top: s(56), right: s(16), child: GestureDetector(
        onTap: () => setState(() => mediaOpen[p.id] = false),
        child: Container(width: s(34), height: s(34), alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x800B0B0D),
            border: Border.all(color: w(.14), width: 1)),
          child: Text('\u00d7', style: ts(s, weight: 400, size: 16, lh: 1, color: txt(.8)))))),
      Positioned(bottom: s(28), left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(onTap: () => setState(() { captured[p.id] = true; mediaOpen[p.id] = false; }),
          child: Container(width: s(38), height: s(38), alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), color: w(.06),
              border: Border.all(color: w(.14), width: 1)),
            child: Container(width: s(17), height: s(15),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(3),
                border: Border.all(color: txt(.6), width: 1.4))))),
        SizedBox(width: s(26)),
        GestureDetector(onTap: () => setState(() { captured[p.id] = true; mediaOpen[p.id] = false; }),
          child: Container(width: s(70), height: s(70), alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: w(.4), width: 2.5),
              boxShadow: [BoxShadow(color: kCyan.withOpacity(.24), blurRadius: s(30))]),
            child: Container(width: s(56), height: s(56),
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: g180(kCyanPale, kCyan))))),
        SizedBox(width: s(26)),
        SizedBox(width: s(38), height: s(38)),
      ])),
    ])));
  }

  // ---------- REPLIES ----------
  Widget _repliesSection(Scale s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(8)),
      child: Text('REPLIES', style: ts(s, weight: 500, size: 11, em: .18, color: txt(.55)))),
    Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(30)),
      child: Column(children: [
        for (int i = 0; i < kReplies.length; i++) ...[
          (viewed[kReplies[i].id] ?? kReplies[i].viewedInit)
            ? _viewedReply(s, kReplies[i]) : _unviewedReply(s, kReplies[i]),
          if (i < kReplies.length - 1) SizedBox(height: s(12)),
        ],
      ])),
  ]);

  Widget _unviewedReply(Scale s, InboundReply r) {
    final active = holdId == r.id;
    final pr = active ? holdP : 0.0;
    return GestureDetector(
      onTapDown: (_) => startHold(r.id, false),
      onTapUp: (_) => endHold(),
      onTapCancel: endHold,
      child: Glass(
        radius: r4(s, 26, 14, 30, 10),
        gradient: g150(w(.07), w(.03)),
        border: Border.all(color: w(.1), width: 1),
        blurSigma: 11,
        shadow: active
          ? [BoxShadow(color: blk(.45), blurRadius: s(40), offset: Offset(0, s(10))),
             BoxShadow(color: kCyan.withOpacity(.1 + .25 * pr), blurRadius: s(18 + 30 * pr))]
          : [BoxShadow(color: blk(.3), blurRadius: s(24), offset: Offset(0, s(6)))],
        child: Stack(children: [
          Padding(padding: EdgeInsets.only(left: s(18), top: s(17), right: s(90), bottom: s(17)),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: (9 * (1 - pr)) / 2, sigmaY: (9 * (1 - pr)) / 2),
              child: Row(children: [
                Container(width: s(36), height: s(36),
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: g160(const Color(0x4CB08968), kCyan.withOpacity(.24)))),
                SizedBox(width: s(13)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.who} replied', style: ts(s, weight: 500, size: 13, color: txt(.62))),
                  SizedBox(height: s(5)),
                  Text(r.prompt, style: ts(s, weight: 500, size: 16, lh: 1.35, color: kText)),
                ])),
              ]))),
          Positioned(top: 0, right: 0, bottom: 0, width: s(90),
            child: DecoratedBox(decoration: BoxDecoration(gradient: cssGradient(270, [w(.06), Colors.transparent])),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: s(42), height: s(42), child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(size: Size(s(42), s(42)), painter: RingPainter(pr, accent)),
                  Container(width: s(7), height: s(7), decoration: BoxDecoration(shape: BoxShape.circle, color: txt(.65))),
                ])),
                SizedBox(height: s(6)),
                SizedBox(width: s(78), child: Text(
                  active ? (pr < .99 ? 'keep holding' : 'opening') : 'hold ${holdSeconds.toStringAsFixed(1)}s to reveal',
                  textAlign: TextAlign.center,
                  style: ts(s, weight: 400, size: 8.5, lh: 1.3, color: active ? kCyan.withOpacity(.85) : txt(.28)))),
              ]))),
        ]),
      ),
    );
  }

  Widget _viewedReply(Scale s, InboundReply r) {
    final showPingBack = r.pingBackLeft != null && !(pingedBack[r.id] ?? false);
    return ClipRRect(borderRadius: r4(s, 24, 12, 26, 14), child: Container(
      decoration: BoxDecoration(color: kSurface1, border: Border.all(color: w(.07), width: 1),
        borderRadius: r4(s, 24, 12, 26, 14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showPingBack) Container(
          padding: EdgeInsets.symmetric(horizontal: s(14), vertical: s(11)),
          decoration: BoxDecoration(gradient: g90(kCyan.withOpacity(.14), kCyan.withOpacity(.08)),
            border: Border(bottom: BorderSide(color: w(.07)))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ping back?', style: ts(s, weight: 500, size: 12.5, color: txt(.9))),
              SizedBox(height: s(2)),
              Text('open for ${r.pingBackLeft}', style: ts(s, weight: 400, size: 10, color: txt(.36))),
            ])),
            GestureDetector(onTap: () => setState(() => pingedBack[r.id] = true),
              child: Container(padding: EdgeInsets.symmetric(horizontal: s(15), vertical: s(8)),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
                  gradient: g180(kCyanLite, kCyan),
                  boxShadow: [BoxShadow(color: kCyan.withOpacity(.34), blurRadius: s(24))]),
                child: Text('Ping ${r.isAnon ? "back" : r.who}', style: ts(s, weight: 500, size: 12, color: kGround)))),
          ]),
        ),
        Padding(padding: EdgeInsets.symmetric(horizontal: s(15), vertical: s(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: s(62), height: s(76), alignment: Alignment.bottomCenter,
              padding: EdgeInsets.only(bottom: s(5)),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                gradient: g160(kCyan.withOpacity(.16), const Color(0x24B08968))),
              child: Text('their photo', style: ts(s, weight: 400, size: 7.5, color: txt(.42)))),
            SizedBox(width: s(12)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(r.who, style: ts(s, weight: 500, size: 13.5, color: txt(.82))),
                SizedBox(width: s(8)),
                Text(r.when, style: ts(s, weight: 400, size: 10, color: txt(.26))),
              ]),
              SizedBox(height: s(6)),
              Text('re: ${r.prompt}', style: ts(s, weight: 400, size: 10.5, color: txt(.3))),
              SizedBox(height: s(6)),
              Text(r.body, style: ts(s, weight: 400, size: 13.5, lh: 1.5, color: txt(.72))),
              SizedBox(height: s(2)),
              Text('viewed \u00b7 stays here', style: ts(s, weight: 400, size: 10, color: txt(.22))),
            ])),
          ])),
        Padding(padding: EdgeInsets.only(left: s(15), right: s(15), bottom: s(13)),
          child: GestureDetector(onTap: () => setState(() => replyDetailId = r.id),
            child: Container(width: double.infinity, alignment: Alignment.center,
              padding: EdgeInsets.symmetric(vertical: s(9)),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
                color: w(.04), border: Border.all(color: w(.1), width: 1)),
              child: Text('View full reply', style: ts(s, weight: 500, size: 11.5, color: txt(.65)))))),
      ]),
    ));
  }

  // ---------- GROUP WALL ----------
  Widget _groupWall(Scale s) {
    final answered = kGroupWall.where((t) => t.answered).length;
    final opened = kGroupWall.where((t) => t.answered && (viewed[t.id] ?? false)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('GROUP WALL', style: ts(s, weight: 500, size: 11, em: .18, color: txt(.55))),
          Text(wallUnlocked ? '$answered of ${kGroupWall.length} answered \u00b7 $opened opened'
            : '$answered answered \u00b7 reply to unlock',
            style: ts(s, weight: 400, size: 10, color: txt(.3))),
        ])),
      Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(30)),
        child: ClipRRect(borderRadius: r4(s, 28, 12, 30, 16), child: Container(
          decoration: BoxDecoration(color: kSurface1, border: Border.all(color: w(.08), width: 1),
            borderRadius: r4(s, 28, 12, 30, 16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(padding: EdgeInsets.only(left: s(16), top: s(14), right: s(16), bottom: s(12)),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: w(.07)))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$kWallGroup \u00b7 $kWallWhen', style: ts(s, weight: 500, size: 12.5, color: txt(.85))),
                SizedBox(height: s(4)),
                Text(kWallPrompt, style: ts(s, weight: 500, size: 15, lh: 1.35, color: kText)),
              ])),
            Padding(padding: EdgeInsets.only(left: s(16), top: s(14), right: s(16), bottom: s(16)),
              child: GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2, mainAxisSpacing: s(10), crossAxisSpacing: s(10), childAspectRatio: 3 / 4,
                children: [for (final t in kGroupWall) _wallTile(s, t)])),
          ]),
        ))),
    ]);
  }

  Widget _wallTile(Scale s, GroupTile t) {
    final radius = BorderRadius.circular(s(16));
    if (!t.answered) {
      return Container(decoration: BoxDecoration(borderRadius: radius, color: w(.02),
        border: Border.all(color: w(.14), width: 1)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: s(26), height: s(26), decoration: BoxDecoration(shape: BoxShape.circle,
            border: Border.all(color: w(.16), width: 1))),
          SizedBox(height: s(6)),
          Text(t.who, style: ts(s, weight: 500, size: 11, color: txt(.4))),
          Text('hasn\u2019t answered', style: ts(s, weight: 400, size: 8.5, color: txt(.22))),
        ]));
    }
    final seen = viewed[t.id] ?? false;
    final active = holdId == t.id;
    final pr = active ? holdP : 0.0;
    if (!wallUnlocked) {
      // locked
      return ClipRRect(borderRadius: radius, child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: t.tint!))),
        BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: CustomPaint(painter: HatchPainter(s(8), w(.07), w(.02)))),
        Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(t.who, style: ts(s, weight: 500, size: 11.5, color: txt(.75))),
          SizedBox(height: s(7)),
          Text('reply to\nunlock', textAlign: TextAlign.center,
            style: ts(s, weight: 400, size: 8.5, lh: 1.3, color: txt(.4))),
        ])),
      ]));
    }
    if (seen) {
      return ClipRRect(borderRadius: radius, child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: t.tint!))),
        CustomPaint(painter: HatchPainter(s(9), w(.08), w(.02))),
        Positioned(top: s(9), left: s(9), child: Container(width: s(30), height: s(38),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(7),
            border: Border.all(color: w(.45), width: 1.5), color: w(.08)))),
        Positioned(left: s(10), right: s(10), bottom: s(10), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(t.who, style: ts(s, weight: 500, size: 11, color: txt(.95))),
            SizedBox(height: s(3)),
            Text(t.text!, style: ts(s, weight: 400, size: 10.5, lh: 1.35, color: txt(.72))),
          ])),
      ]));
    }
    // hidden (mid-reveal)
    return GestureDetector(
      onTapDown: (_) => startHold(t.id, false),
      onTapUp: (_) => endHold(),
      onTapCancel: endHold,
      child: ClipRRect(borderRadius: radius, child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: t.tint!))),
        BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: (9 * (1 - pr)) / 2, sigmaY: (9 * (1 - pr)) / 2),
          child: CustomPaint(painter: HatchPainter(s(8), w(.07), w(.02)))),
        Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: s(36), height: s(36), child: Stack(alignment: Alignment.center, children: [
            CustomPaint(size: Size(s(36), s(36)), painter: RingPainter(pr, accent)),
            Container(width: s(6), height: s(6), decoration: BoxDecoration(shape: BoxShape.circle, color: txt(.75))),
          ])),
          SizedBox(height: s(8)),
          Text(t.who, style: ts(s, weight: 500, size: 11.5, color: txt(.9))),
          Text(active ? (pr < .99 ? 'keep holding' : 'opening') : 'hold to reveal',
            style: ts(s, weight: 400, size: 8.5, color: active ? kCyan.withOpacity(.85) : txt(.28))),
        ])),
      ])),
    );
  }

  // ---------- SENT ----------
  Widget _sentSection(Scale s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(8)),
      child: Text('SENT', style: ts(s, weight: 500, size: 11, em: .18, color: txt(.4)))),
    Padding(padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(30)),
      child: Column(children: [
        for (int i = 0; i < kSent.length; i++) ...[
          _sentRow(s, kSent[i]), if (i < kSent.length - 1) SizedBox(height: s(9)),
        ],
      ])),
  ]);

  Widget _sentRow(Scale s, OutboundPing o) => Container(
    padding: EdgeInsets.symmetric(horizontal: s(16), vertical: s(14)),
    decoration: BoxDecoration(borderRadius: r4(s, 20, 10, 22, 12),
      color: kSurface2, border: Border.all(color: w(.05), width: 1)),
    child: Row(children: [
      Container(width: s(28), height: s(28), alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: w(.16), width: 1)),
        child: Text(o.initial, style: ts(s, weight: 400, size: 10, color: txt(.4)))),
      SizedBox(width: s(12)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('to ${o.who}', style: ts(s, weight: 400, size: 11, color: txt(.32))),
        SizedBox(height: s(3)),
        Text(o.prompt, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: ts(s, weight: 400, size: 14, lh: 1.3, color: txt(.62))),
      ])),
      SizedBox(width: s(12)),
      if (o.seen) Row(mainAxisSize: MainAxisSize.min, children: [
        PulseDot(size: s(5)), SizedBox(width: s(6)),
        Text('Seen', style: ts(s, weight: 400, size: 10.5, color: kCyan.withOpacity(.72))),
      ]) else Text('Delivered', style: ts(s, weight: 400, size: 10.5, color: txt(.24))),
    ]),
  );

  // ---------- REPLY DETAIL ----------
  Widget _detail(Scale s) {
    final r = kReplies.firstWhere((x) => x.id == replyDetailId);
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Positioned.fill(child: _SlideUp(child: Container(color: kGround, child: Column(children: [
      Expanded(child: SingleChildScrollView(child: Column(children: [
        Container(width: double.infinity,
          padding: EdgeInsets.only(left: s(18), top: safeTop + s(8), right: s(18), bottom: s(10)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(onTap: () => setState(() => replyDetailId = null),
              child: Container(width: s(34), height: s(34), alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: w(.06),
                  border: Border.all(color: w(.1), width: 1)),
                child: Text('\u2039', style: ts(s, weight: 400, size: 17, lh: 1, color: txt(.8))))),
            Column(children: [
              Text(r.who, style: ts(s, weight: 600, size: 14, color: kText)),
              SizedBox(height: s(2)),
              Text(r.when, style: ts(s, weight: 400, size: 10, color: txt(.34))),
            ]),
            SizedBox(width: s(34), height: s(34)),
          ])),
        Padding(padding: EdgeInsets.only(left: s(22), top: s(8), right: s(22), bottom: s(18)),
          child: Column(children: [
            SizedBox(width: s(150), child: AspectRatio(aspectRatio: 3 / 4,
              child: ClipRRect(borderRadius: BorderRadius.circular(s(18)), child: Stack(children: [
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                  gradient: g160(kCyan.withOpacity(.14), const Color(0x1FB08968))))),
                Positioned.fill(child: CustomPaint(painter: HatchPainter(s(9), w(.09), w(.03)))),
                Positioned(top: s(9), left: s(9), child: Container(width: s(44), height: s(56),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: w(.5), width: 1.5), color: w(.08),
                    boxShadow: [BoxShadow(color: blk(.4), blurRadius: s(14), offset: Offset(0, s(4)))]))),
              ])))),
            SizedBox(height: s(12)),
            Text('re: ${r.prompt}', style: ts(s, weight: 400, size: 10.5, color: txt(.32))),
            SizedBox(height: s(8)),
            ConstrainedBox(constraints: BoxConstraints(maxWidth: s(280)),
              child: Text(r.body, textAlign: TextAlign.center,
                style: ts(s, weight: 400, size: 15, lh: 1.6, color: txt(.85)))),
          ])),
        Container(width: double.infinity,
          padding: EdgeInsets.only(left: s(22), top: s(14), right: s(22), bottom: s(24)),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: w(.07)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text('Comments', style: ts(s, weight: 600, size: 14, color: kText)),
              SizedBox(width: s(8)),
              Text('1', style: ts(s, weight: 400, size: 11, color: txt(.32))),
            ]),
            SizedBox(height: s(12)),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: s(30), height: s(30), decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: g160(kEarth[4][0], kEarth[4][1]))),
              SizedBox(width: s(10)),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('nonoka', style: ts(s, weight: 500, size: 12.5, color: kText)),
                  SizedBox(width: s(7)),
                  Text('2h ago', style: ts(s, weight: 400, size: 9.5, color: txt(.3))),
                ]),
                SizedBox(height: s(3)),
                Text('this is so real', style: ts(s, weight: 400, size: 13.5, lh: 1.4, color: txt(.78))),
                SizedBox(height: s(3)),
                Text('Reply', style: ts(s, weight: 400, size: 10.5, color: txt(.32))),
              ]),
            ]),
          ])),
      ]))),
      Container(width: double.infinity,
        padding: EdgeInsets.only(left: s(16), top: s(12), right: s(16), bottom: safeBottom + s(20)),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: w(.06)))),
        child: Row(children: [
          Expanded(child: Container(padding: EdgeInsets.symmetric(horizontal: s(16), vertical: s(11)),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(100),
              color: w(.05), border: Border.all(color: w(.1), width: 1)),
            child: Text('Add a comment\u2026', style: ts(s, weight: 400, size: 13.5, color: txt(.4))))),
          SizedBox(width: s(10)),
          Container(width: s(38), height: s(38), alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: g180(kCyan, kCyanDeep)),
            child: Text('\ud83d\udcac', style: TextStyle(fontSize: s(15)))),
        ])),
    ]))));
  }
}

// ---- helper value type ----
class _Loop {
  final String id, initial, title, reason, left;
  final bool isAnon;
  final int tintIndex;
  final VoidCallback onTap;
  _Loop({required this.id, required this.initial, required this.title, required this.reason,
    required this.left, required this.isAnon, required this.tintIndex, required this.onTap});
}

// ---- ambient background ----
class _Ambient extends StatefulWidget {
  const _Ambient();
  @override
  State<_Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<_Ambient> with TickerProviderStateMixin {
  late final a = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat(reverse: true);
  late final b = AnimationController(vsync: this, duration: const Duration(seconds: 22))..repeat(reverse: true);
  late final c = AnimationController(vsync: this, duration: const Duration(seconds: 26))..repeat(reverse: true);
  @override
  void dispose() { a.dispose(); b.dispose(); c.dispose(); super.dispose(); }
  Widget blob(Animation ctl, Offset from, Offset to, double size, Color color) => AnimatedBuilder(
    animation: ctl, builder: (_, __) {
      final o = Offset.lerp(from, to, Curves.easeInOut.transform(ctl.value))!;
      return Positioned(left: o.dx, top: o.dy, child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent], stops: const [0, .68])))));
    });
  @override
  Widget build(BuildContext ctx) => Positioned.fill(child: DecoratedBox(
    decoration: const BoxDecoration(color: kGround),
    child: Stack(clipBehavior: Clip.hardEdge, children: [
      blob(a, const Offset(-90, -140), const Offset(-72, -162), 340, kCyan.withOpacity(.16)),
      blob(b, const Offset(280, 220), const Offset(256, 236), 320, kCyan.withOpacity(.15)),
      blob(c, const Offset(40, 620), const Offset(58, 598), 300, const Color(0xFFB08968).withOpacity(.10)),
    ]),
  ));
}

// ---- entrance animations ----
class _SheetIn extends StatefulWidget {
  final Widget child;
  const _SheetIn({super.key, required this.child});
  @override
  State<_SheetIn> createState() => _SheetInState();
}

class _SheetInState extends State<_SheetIn> with SingleTickerProviderStateMixin {
  late final ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
  @override
  void dispose() { ctl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext c) => AnimatedBuilder(animation: ctl, builder: (_, child) {
    final t = const Cubic(.2, .8, .2, 1).transform(ctl.value);
    return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * -10),
      child: Transform.scale(scale: ui.lerpDouble(.97, 1, t), child: child)));
  }, child: widget.child);
}

class _PromptIn extends StatefulWidget {
  final int delayMs;
  final Widget child;
  const _PromptIn({required this.delayMs, required this.child});
  @override
  State<_PromptIn> createState() => _PromptInState();
}

class _PromptInState extends State<_PromptIn> with SingleTickerProviderStateMixin {
  late final ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () { if (mounted) ctl.forward(); });
  }
  @override
  void dispose() { ctl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext c) => AnimatedBuilder(animation: ctl, builder: (_, child) {
    final t = const Cubic(.2, .8, .2, 1).transform(ctl.value);
    return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child));
  }, child: widget.child);
}

class _SlideUp extends StatefulWidget {
  final Widget child;
  const _SlideUp({required this.child});
  @override
  State<_SlideUp> createState() => _SlideUpState();
}

class _SlideUpState extends State<_SlideUp> with SingleTickerProviderStateMixin {
  late final ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..forward();
  @override
  void dispose() { ctl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext c) => AnimatedBuilder(animation: ctl, builder: (_, child) {
    final t = Curves.easeOut.transform(ctl.value);
    return Opacity(opacity: t, child: Transform.translate(
      offset: Offset(0, (1 - t) * MediaQuery.of(c).size.height * .04), child: child));
  }, child: widget.child);
}
