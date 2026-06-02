// =============================================================================
// painters/fragment_painter.dart
// Sol — Ambient Emotional Field  [SOL DESIGN SYSTEM ALIGNMENT v6]
//
// CHANGES FROM v5 (visual only — zero logic/architecture changes):
//
//   · Fragment text pool replaced entirely.
//     Old pool: casual Hindi/English banter ("bhai kya scene hai", "lmao",
//     "you playing BGMI tonight?") — felt like iMessage, not Sol.
//     New pool: intimate, lowercase, emotionally resonant fragments that
//     match Sol's tone — the kind of things you'd say to someone you
//     genuinely trust, at a quiet hour.  Same pool size (~130 entries).
//
//   · Palette aligned to Sol Design System:
//       kFragCream     #E8DDD0   (was #E4D5BB — Sol _cream)
//       _kBubbleFill   #10131A   (was #111318 — Sol _surface, breathes with bg)
//       _kBubbleBorder #E8DDD0   (same cream, unchanged in value)
//
//   · Text style: GoogleFonts.jost (was inter) — Sol's meta/label font.
//     FontWeight.w300, unchanged.  Same fontSize range (11–12.5).
//     LetterSpacing 0.15 → 0.20 (slightly more airy, matches Sol labels).
//
//   · Mote colour: uses Sol _cream (#E8DDD0) — trivially same feel, palette
//     consistent.
//
//   · Bubble fill opacity: 0.22 → 0.18 (even more atmospheric, matches the
//     surface-up panels in InboxScreen which sit at ~0.38 opacity).
//
//   · Bubble border opacity multiplier: 0.06 → 0.055 (imperceptible
//     difference; keeps borders as barely-there hairlines).
//
//   · Text opacity multiplier: 0.42 → 0.40 (fragments still legible on
//     close inspection; feel like emotional residue, not chat UI).
//
//   NOTHING ELSE CHANGED.  All timing, lane logic, spawn/death cycle,
//   mote physics, FragmentParticle geometry, FragmentField state management,
//   and all constants (_kLaneCount, _kLaneSpeeds, etc.) are UNTOUCHED.
//
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — Sol Design System
// ─────────────────────────────────────────────────────────────────────────────

const Color kFragCream = Color(0xFFE8DDD0); // Sol _cream

const Color _kBubbleFill =
    Color(0xFF10131A); // Sol _surface — blends into _bgDeep
const Color _kBubbleBorder = Color(0xFFE8DDD0); // Sol _cream

// ─────────────────────────────────────────────────────────────────────────────
// Bubble geometry constants — UNTOUCHED
// ─────────────────────────────────────────────────────────────────────────────

const double _kPadH = 10.0;
const double _kPadV = 7.0;
const double _kRadius = 16.0;
const double _kMaxBubbleWidth = 220.0;

// ─────────────────────────────────────────────────────────────────────────────
// Fragment text pool
//
// Tone: intimate, lowercase, unhurried.  The words drifting past should feel
// like they belong to real relationships — the ones that matter at 1am.
// Not banter.  Not small talk.  The things people actually say to Sol.
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kAllFragments = [
  // ── Presence / reaching out
  "hey",
  "you there?",
  "just thinking of you",
  "wanted to say hi",
  "miss talking to you",
  "couldn't sleep",
  "still up?",
  "can we talk?",
  "i needed someone right now",
  "glad you're here",
  "i don't know why i'm texting",
  "just needed to hear a voice",

  // ── Emotional check-ins
  "how are you, actually?",
  "no, really. how are you?",
  "been a hard week",
  "today was a lot",
  "i'm okay. mostly.",
  "not great, honestly",
  "i'm fine",
  "i think i'm okay",
  "i've been better",
  "better than yesterday",
  "worse than i'm letting on",
  "i don't know how i feel",
  "everything feels heavy",
  "i feel kind of empty today",
  "i'm just tired",
  "tired in a way sleep doesn't fix",
  "my chest feels tight",
  "something's off and i can't name it",
  "i feel weirdly calm today",
  "today was actually good",
  "i'm proud of myself today",
  "i did the thing i was scared of",

  // ── Vulnerability
  "i've been crying and i'm not sure why",
  "i feel like a burden sometimes",
  "i don't want to be alone right now",
  "i just need someone to listen",
  "i feel invisible lately",
  "i said the wrong thing again",
  "i keep replaying it",
  "i'm scared",
  "i don't want to go",
  "i don't want to feel like this anymore",
  "please just stay for a bit",
  "i feel like i'm disappearing",
  "i keep pretending i'm okay",
  "no one knows how bad it's been",

  // ── Longing / connection
  "i miss who i used to be",
  "i miss them",
  "i wish things were different",
  "do you think they think about me?",
  "i wonder if they're okay",
  "i keep wanting to call",
  "i almost texted them",
  "maybe i should reach out",
  "it's been so long",
  "i hope they know i care",

  // ── Small comforts
  "it's raining and i'm inside and it's okay",
  "made tea. first time today i felt okay.",
  "the light was really beautiful this evening",
  "small win today",
  "i didn't spiral. that's something.",
  "i got through it",
  "it wasn't as bad as i thought",
  "i actually laughed today",
  "good song. needed that.",
  "this helped. just talking.",

  // ── Late-night textures
  "it's 2am and i'm still awake",
  "the apartment is so quiet",
  "everyone else is asleep",
  "nothing feels real at this hour",
  "nights are harder",
  "mornings are harder",
  "i like the stillness but i hate it too",
  "the city sounds different at night",
  "i've been sitting here for an hour",
  "i didn't do anything today. that's okay.",

  // ── Growth / healing
  "i've been going to therapy",
  "i told them something i've never said out loud",
  "i think i'm finally healing",
  "i'm learning to be gentler with myself",
  "i set a boundary today",
  "i said no and it felt right",
  "i'm starting to like who i'm becoming",
  "i don't need their approval anymore",
  "i forgave myself a little bit today",
  "i'm not where i want to be but i'm moving",

  // ── Love & closeness
  "i love you, you know that?",
  "you mean a lot to me",
  "i'm really glad we met",
  "thank you for always being honest",
  "you make me feel less alone",
  "i trust you",
  "i don't say it enough",
  "you're one of the good ones",
  "i feel safe with you",
  "this is the most i've opened up in years",

  // ── Uncertainty / searching
  "i don't know what i want",
  "i don't know who i am right now",
  "i keep starting over",
  "i'm figuring it out",
  "i'm in a weird in-between place",
  "not lost, just not found yet",
  "something has to change",
  "i'm searching for something i can't name",
  "what does it even mean to be okay?",
  "i just want to feel like myself again",

  // ── Simple presence
  "hi",
  "it's me",
  "hey, it's been a while",
  "i'm back",
  "i didn't know where else to go",
  "can you just be here for a sec?",
  "don't say anything. just stay.",
  "okay",
  "thank you",
  "i feel a little better now",
];

// ─────────────────────────────────────────────────────────────────────────────
// Lane configuration — UNTOUCHED
// ─────────────────────────────────────────────────────────────────────────────

const int _kLaneCount = 14;
const double _kLaneTop = 0.04;
const double _kLaneBottom = 0.54;
const int _kMaxPerLane = 2;

const List<double> _kLaneSpeeds = [
  0.52,
  0.38,
  0.60,
  0.44,
  0.48,
  0.42,
  0.58,
  0.36,
  0.55,
  0.46,
  0.50,
  0.40,
  0.62,
  0.34,
];

// ─────────────────────────────────────────────────────────────────────────────
// FragmentParticle — UNTOUCHED
// ─────────────────────────────────────────────────────────────────────────────

class FragmentParticle {
  FragmentParticle({
    required this.text,
    required Offset logoCenter,
    required math.Random rng,
  }) {
    laneIndex = rng.nextInt(_kLaneCount);
    goesRight = (laneIndex % 2 == 0);
    _speed = _kLaneSpeeds[laneIndex];

    xPixel = goesRight ? -_kOffscreen : 99999.0;

    maxOpacity = 0.20 + rng.nextDouble() * 0.12;

    fontSize = 11.0 + rng.nextDouble() * 1.5;

    _yJitter = (rng.nextDouble() - 0.5) * 4.0;
  }

  final String text;

  late int laneIndex;
  late bool goesRight;
  late double xPixel;
  late double maxOpacity;
  late double fontSize;
  late double _yJitter;
  late double _speed;

  double bubbleW = 0.0;
  double bubbleH = 0.0;

  bool _sized = false;
  bool _initialised = false;

  static const double _kOffscreen = 60.0;
  static const double _kFadeZone = 0.12;

  double yPixel(double screenHeight) {
    final double step =
        ((_kLaneBottom - _kLaneTop) * screenHeight) / (_kLaneCount - 1);
    return _kLaneTop * screenHeight + laneIndex * step + _yJitter;
  }

  void initialise(
    double screenWidth, {
    bool randomStart = false,
    double startFrac = 0.0,
  }) {
    if (randomStart) {
      xPixel = goesRight
          ? -_kOffscreen +
              math.Random().nextDouble() * (screenWidth + _kOffscreen * 2)
          : screenWidth +
              _kOffscreen -
              math.Random().nextDouble() * (screenWidth + _kOffscreen * 2);
    } else if (startFrac > 0.0) {
      xPixel = goesRight
          ? -_kOffscreen - screenWidth * startFrac
          : screenWidth + _kOffscreen + screenWidth * startFrac;
    } else {
      xPixel = goesRight ? -_kOffscreen : screenWidth + _kOffscreen;
    }
    _initialised = true;
  }

  bool isDead(double screenWidth) {
    return goesRight
        ? xPixel > screenWidth + _kOffscreen * 3
        : xPixel < -_kOffscreen * 3;
  }

  void update(double deltaTime) {
    final double pixels = _speed * 60.0 * deltaTime;
    xPixel += goesRight ? pixels : -pixels;
  }

  double opacity(double screenWidth) {
    final double fadePixels = screenWidth * _kFadeZone;

    final double distFromEntry =
        goesRight ? xPixel + _kOffscreen : screenWidth + _kOffscreen - xPixel;

    final double distFromExit =
        goesRight ? screenWidth + _kOffscreen - xPixel : xPixel + _kOffscreen;

    final double fadeIn = (distFromEntry / fadePixels).clamp(0.0, 1.0);
    final double fadeOut = (distFromExit / fadePixels).clamp(0.0, 1.0);

    final double envelope = math.min(fadeIn, fadeOut);

    return (envelope * envelope * (3.0 - 2.0 * envelope) * maxOpacity)
        .clamp(0.0, 1.0);
  }

  double get bubbleLeft => xPixel - bubbleW / 2;
  double get bubbleRight => xPixel + bubbleW / 2;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dust motes — UNTOUCHED
// ─────────────────────────────────────────────────────────────────────────────

class MoteParticle {
  MoteParticle(int i) {
    double seed(double n) {
      final x = math.sin(i * 17.0 + n + 7) * 10000;
      return x - x.floor();
    }

    xFrac = seed(1);
    yFrac = seed(2);
    radius = seed(3) * 0.7 + 0.15;
    speed = seed(4) * 0.08 + 0.02;
    phase = seed(5) * math.pi * 2;
  }

  late double xFrac, yFrac, radius, speed, phase;
}

final List<MoteParticle> kMotes = List.generate(12, (i) => MoteParticle(i));

// ─────────────────────────────────────────────────────────────────────────────
// FragmentPainter — paint calls aligned to Sol palette; logic UNTOUCHED
// ─────────────────────────────────────────────────────────────────────────────

class FragmentPainter extends CustomPainter {
  FragmentPainter({
    required this.t,
    required this.particles,
  });

  final double t;
  final List<FragmentParticle> particles;

  final Paint _fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

  final Paint _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    _drawMotes(canvas, size);
    _drawBubbles(canvas, size);
  }

  // ── Motes — UNTOUCHED (kFragCream now Sol _cream, imperceptible delta) ───
  void _drawMotes(Canvas canvas, Size size) {
    for (final m in kMotes) {
      double dy = (m.yFrac - t * m.speed * 0.006) % 1.0;
      if (dy < 0) dy += 1.0;

      final double sx =
          m.xFrac + math.sin(t * math.pi * 2 * m.speed + m.phase) * 0.003;

      final double pulse = (math.sin(t * m.speed + m.phase) + 1) / 2;

      canvas.drawCircle(
        Offset(sx * size.width, dy * size.height),
        m.radius,
        Paint()
          ..color = kFragCream.withValues(alpha: pulse * 0.02)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
      );
    }
  }

  // ── Bubbles — font updated to Jost; opacity tuned; logic UNTOUCHED ───────
  void _drawBubbles(Canvas canvas, Size size) {
    for (final p in particles) {
      final double op = p.opacity(size.width);
      if (op < 0.01) continue;

      // Jost w300 — Sol's meta/label font; airy, intimate at small sizes
      final TextStyle textStyle = GoogleFonts.jost(
        fontWeight: FontWeight.w300,
        fontSize: p.fontSize,
        height: 1.15,
        letterSpacing: 0.20,
        color: kFragCream,
      );

      if (!p._sized) {
        final TextPainter measurer = TextPainter(
          text: TextSpan(text: p.text, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: 3,
        )..layout(maxWidth: _kMaxBubbleWidth - (_kPadH * 2));

        p.bubbleW = measurer.width + _kPadH * 2;
        p.bubbleH = measurer.height + _kPadV * 2;
        p._sized = true;

        if (!p._initialised) {
          p.initialise(size.width);
        }
      }

      final double cx = p.xPixel;
      final double cy = p.yPixel(size.height);

      if (cx < -p.bubbleW - 100 || cx > size.width + p.bubbleW + 100) {
        continue;
      }

      final double left = cx - p.bubbleW / 2;
      final double top = cy - p.bubbleH / 2;

      final Rect rect = Rect.fromLTWH(left, top, p.bubbleW, p.bubbleH);
      final RRect rrect =
          RRect.fromRectAndRadius(rect, const Radius.circular(_kRadius));

      // Fill — Sol _surface at reduced opacity; melts into _bgDeep
      _fillPaint.color = _kBubbleFill.withValues(alpha: op * 0.18);
      canvas.drawRRect(rrect, _fillPaint);

      // Border — cream hairline
      _strokePaint.color = _kBubbleBorder.withValues(alpha: op * 0.055);
      canvas.drawRRect(rrect, _strokePaint);

      // Text — Jost, cream @ 0.40 × envelope
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: textStyle.copyWith(
            color: kFragCream.withValues(alpha: op * 0.40),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: _kMaxBubbleWidth - (_kPadH * 2));

      tp.paint(canvas, Offset(left + _kPadH, top + _kPadV));
    }
  }

  @override
  bool shouldRepaint(FragmentPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// FragmentField — UNTOUCHED
// ─────────────────────────────────────────────────────────────────────────────

class FragmentField extends StatefulWidget {
  const FragmentField({
    super.key,
    this.logoCenter,
  });

  final ValueNotifier<Offset>? logoCenter;

  @override
  State<FragmentField> createState() => _FragmentFieldState();
}

class _FragmentFieldState extends State<FragmentField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  final List<FragmentParticle> _particles = [];
  final Map<int, List<FragmentParticle>> _laneOccupants = {};

  final _rng = math.Random();

  late List<String> _pool;
  int _poolIdx = 0;

  double _t = 0.0;
  double _lastStamp = -1.0;

  @override
  void initState() {
    super.initState();

    _pool = [...kAllFragments]..shuffle(_rng);

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 999),
    )
      ..addListener(_onTick)
      ..forward();

    for (int lane = 0; lane < _kLaneCount; lane++) {
      _spawnLane(lane, warmStart: true);
      if (_rng.nextDouble() < 0.60) {
        _spawnLane(lane, warmStart: true);
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;

    final double now =
        _ticker.lastElapsedDuration?.inMicroseconds.toDouble() ?? 0.0;
    final double dt =
        _lastStamp < 0 ? 1 / 60.0 : ((now - _lastStamp) / 1e6).clamp(0.0, 0.05);
    _lastStamp = now;
    _t += dt;

    final Size size = _currentSize();

    for (final p in _particles) {
      p.update(dt);
    }

    final List<FragmentParticle> dead =
        _particles.where((p) => p.isDead(size.width)).toList();

    for (final p in dead) {
      _particles.remove(p);
      _laneOccupants[p.laneIndex]?.remove(p);
      if (_laneOccupants[p.laneIndex]?.isEmpty ?? true) {
        _laneOccupants.remove(p.laneIndex);
      }
      _spawnLane(p.laneIndex, warmStart: false);
    }
  }

  Size _currentSize() {
    final box = context.findRenderObject() as RenderBox?;
    return box?.size ?? const Size(390, 844);
  }

  String _nextText() {
    if (_poolIdx >= _pool.length) {
      _pool.shuffle(_rng);
      _poolIdx = 0;
    }
    return _pool[_poolIdx++];
  }

  void _spawnLane(int lane, {required bool warmStart}) {
    final int current = _laneOccupants[lane]?.length ?? 0;
    if (current >= _kMaxPerLane) return;

    final p = FragmentParticle(
      text: _nextText(),
      logoCenter: widget.logoCenter?.value ?? const Offset(195, 200),
      rng: _rng,
    );

    p.laneIndex = lane;
    p.goesRight = (lane % 2 == 0);
    p._speed = _kLaneSpeeds[lane] + (_rng.nextDouble() - 0.5) * 0.08;

    final Size size = _currentSize();

    if (warmStart) {
      p.initialise(size.width, randomStart: true);
    } else {
      p.initialise(size.width, randomStart: false);
    }

    _particles.add(p);
    _laneOccupants.putIfAbsent(lane, () => []).add(p);
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _ticker,
      builder: (_, __) => CustomPaint(
        painter: FragmentPainter(
          t: _t,
          particles: List.unmodifiable(_particles),
        ),
        size: screenSize,
      ),
    );
  }
}
