// =============================================================================
// painters/fragment_painter.dart
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────

const Color kFragCream = Color(0xFFE4D5BB);

// ─────────────────────────────────────────────────────────────────────────────
// Fragment data
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kAllFragments = [
  'u awake',
  'nah that’s actually insane',
  'wait 😭',
  'okay but hear me out',
  'you ever think about that one random day and feel weird after',
  'idk why but that reminded me of you',
  'lmao',
  'you disappeared',
  'that’s kinda sad actually',
  'lowkey proud of you for that',
  'what even happened there',
  'okay yeah fair',
  'you still listening to that song?',
  'i knew you were gonna say that',
  'that sounds exhausting honestly',
  'bro 😭',
  'did it at least go okay?',
  'that’s so specific',
  'you think too much',
  'lowkey miss talking like this',
  'nah because why would they do that',
  'wait what',
  'you always do this thing where',
  'i don’t think you realize how much that affected you',
  'real',
  'you say “it’s fine” in a very unconvincing way',
  'did you sleep at all',
  'okay that’s actually funny',
  'i feel like you knew that already though',
  'you’ve been weirdly quiet lately',
  'that would genuinely piss me off',
  'honestly?',
  'you remember the weirdest details',
  'i can’t tell if you’re joking sometimes',
  'you think about stuff way longer than people realize',
  'that sounds like something you’d do',
  'not gonna lie that kinda suits you',
  'you still there?',
  'i don’t buy that excuse at all',
  'hmm',
  'you know what’s weird',
  'that feels important somehow',
  'you avoid things until 2am and suddenly wanna process life',
  'i mean… fair enough',
  'you always come back to this topic somehow',
  'that’s actually kinda cute',
  'i don’t think you’re as okay as you pretend to be',
  'you type differently when you’re upset',
  'nah i get what you mean',
  'sometimes i think you miss old versions of your life',
];

// ─────────────────────────────────────────────────────────────────────────────
// FragmentParticle
// ─────────────────────────────────────────────────────────────────────────────

class FragmentParticle {
  FragmentParticle({
    required this.text,
    required Offset logoCenter,
    required math.Random rng,
  }) {
    // Wider emergence from center
    final spawnR = 36.0 + rng.nextDouble() * 92.0;

    final angle = rng.nextDouble() * math.pi * 2;

    x = logoCenter.dx + math.cos(angle) * spawnR;
    y = logoCenter.dy + math.sin(angle) * spawnR;

    // Slower, more thoughtful motion
    final driftAngle = angle + (rng.nextDouble() - 0.5) * 0.9;

    final spd = 0.075 + rng.nextDouble() * 0.11;

    vx = math.cos(driftAngle) * spd;
    vy = math.sin(driftAngle) * spd - 0.07;

    // Gentle sway
    swayAmp = (rng.nextDouble() - 0.5) * 0.055;
    swayFreq = 0.35 + rng.nextDouble() * 0.65;
    swayPhase = rng.nextDouble() * math.pi * 2;

    // Longer life
    maxLife = (320 + rng.nextDouble() * 220).toInt();

    // Slightly larger for readability
    fontSize = 8.8 + rng.nextDouble() * 2.4;
  }

  final String text;

  late double x;
  late double y;

  late double vx;
  late double vy;

  late double swayAmp;
  late double swayFreq;
  late double swayPhase;

  late int maxLife;
  late double fontSize;

  static const int fadeIn = 45;
  static const int fadeOut = 75;

  int life = 0;

  void update(double t) {
    x += vx + math.sin(t * swayFreq + swayPhase) * swayAmp;
    y += vy;

    life++;
  }

  double opacity() {
    if (life < fadeIn) {
      return life / fadeIn;
    }

    if (life > maxLife - fadeOut) {
      return ((maxLife - life) / fadeOut.toDouble()).clamp(0.0, 1.0);
    }

    return 1.0;
  }

  bool get isDead => life >= maxLife;
}

// ─────────────────────────────────────────────────────────────────────────────
// MoteParticle
// ─────────────────────────────────────────────────────────────────────────────

class MoteParticle {
  MoteParticle(int i) {
    double seed(double n) {
      final x = math.sin(i * 11.0 + n) * 10000;
      return x - x.floor();
    }

    xFrac = seed(1);
    yFrac = seed(2);

    radius = seed(3) * 0.85 + 0.22;
    speed = seed(4) * 0.24 + 0.06;

    phase = seed(5) * math.pi * 2;
  }

  late double xFrac;
  late double yFrac;

  late double radius;
  late double speed;

  late double phase;
}

// Reduced dust clutter
final List<MoteParticle> kMotes = List.generate(18, (i) => MoteParticle(i));

// ─────────────────────────────────────────────────────────────────────────────
// FragmentPainter
// ─────────────────────────────────────────────────────────────────────────────

class FragmentPainter extends CustomPainter {
  FragmentPainter({
    required this.t,
    required this.particles,
  });

  final double t;
  final List<FragmentParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    _drawMotes(canvas, size);
    _drawFragments(canvas, size);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Dust motes
  // ───────────────────────────────────────────────────────────────────────────

  void _drawMotes(Canvas canvas, Size size) {
    for (final m in kMotes) {
      var dy = (m.yFrac - t * m.speed * 0.022) % 1.0;

      if (dy < 0) {
        dy += 1.0;
      }

      final sx = m.xFrac +
          math.sin(
                t * math.pi * 2 * m.speed + m.phase,
              ) *
              0.009;

      final pulse = (math.sin(
                t * math.pi * 2 * m.speed * 0.65 + m.phase,
              ) +
              1) /
          2;

      final op = (0.03 + pulse * 0.11).clamp(0.0, 1.0);

      canvas.drawCircle(
        Offset(
          sx * size.width,
          dy * size.height,
        ),
        m.radius,
        Paint()
          ..color = kFragCream.withOpacity(op)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            1.2,
          ),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Memory fragments
  // ───────────────────────────────────────────────────────────────────────────

  void _drawFragments(Canvas canvas, Size size) {
    for (final p in particles) {
      final op = p.opacity();

      if (op <= 0.01) continue;

      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: GoogleFonts.jost(
            fontWeight: FontWeight.w300,
            fontSize: p.fontSize,

            // Stronger readability
            color: kFragCream.withOpacity(0.58 * op),

            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final tw = tp.width;

      final ph = p.fontSize + 8;
      final pw = tw + 22;

      final px = p.x - pw / 2;
      final py = p.y - ph / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(px, py, pw, ph),
        const Radius.circular(100),
      );

      // Capsule fill
      canvas.drawRRect(
        rect,
        Paint()..color = kFragCream.withOpacity(0.075 * op),
      );

      // Capsule border
      canvas.drawRRect(
        rect,
        Paint()
          ..color = kFragCream.withOpacity(0.18 * op)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );

      // Text
      tp.paint(
        canvas,
        Offset(
          p.x - tw / 2,
          p.y - tp.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(FragmentPainter old) => true;
}
