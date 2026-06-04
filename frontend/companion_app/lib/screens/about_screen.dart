// ═══════════════════════════════════════════════════════════════════════════
// about_sol_screen.dart
// Sol — Premium About Screen  v2
// Dark luxury · Cinematic · Honest
// ═══════════════════════════════════════════════════════════════════════════
//
// DEPENDENCY NOTE
// ───────────────
// This file uses `dart:ui`, `package:flutter/services.dart` (Clipboard),
// and `package:google_fonts/google_fonts.dart` — all already in your pubspec.
// The Docs card copies the URL to clipboard on tap (no url_launcher needed).
// To enable deep-link launch, add url_launcher to pubspec and swap the
// `_copyDocsUrl()` call with `launchUrl(Uri.parse(_kDocsUrl))`.
//
// DOCS URL — replace before shippings

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

const _kDocsUrl = 'https://your-docusaurus-url.com'; // ← set this
// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  static const bg = Color(0xFF09090B);
  static const surface = Color(0xFF0F1117);

  static const purple = Color(0xFF7C5CFC);
  static const violet = Color(0xFF8B5CF6);
  static const indigo = Color(0xFF6366F1);

  static const gold = Color(0xFFD6A95C);
  static const goldLt = Color(0xFFE6D3B3);
  static const amber = Color(0xFFFBBF24);

  static const g1 = Color(0xFFD1D5DB);
  static const g2 = Color(0xFF9CA3AF);

  static const glass = Color(0x07FFFFFF);
  static const glassB = Color(0x14FFFFFF);

  static const purpleGlow = Color(0x1A7C5CFC);
  static const goldGlow = Color(0x0DD6A95C);
  static const indigoGlow = Color(0x086366F1);

  static const shipped = Color(0xFF34D399); // emerald
  static const inProg = Color(0xFFFBBF24); // amber
  static const planned = Color(0xFF6B7280); // gray
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AboutSolScreen extends StatefulWidget {
  const AboutSolScreen({super.key});

  @override
  State<AboutSolScreen> createState() => _AboutSolScreenState();
}

class _AboutSolScreenState extends State<AboutSolScreen>
    with TickerProviderStateMixin {
  late final ScrollController _scroll;
  late final AnimationController _breathe;
  late final AnimationController _fragments;
  late final AnimationController _entrance;

  static const _sectionIds = [
    'about',
    'arch',
    'how',
    'journey',
    'final',
  ];
  final Map<String, GlobalKey> _keys = {};
  final Set<String> _revealed = {};

  @override
  void initState() {
    super.initState();
    for (final id in _sectionIds) _keys[id] = GlobalKey();

    _scroll = ScrollController()..addListener(_checkReveal);
    _breathe =
        AnimationController(vsync: this, duration: const Duration(seconds: 8))
          ..repeat(reverse: true);
    _fragments =
        AnimationController(vsync: this, duration: const Duration(seconds: 22))
          ..repeat();
    _entrance = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..forward();
  }

  void _checkReveal() {
    if (!mounted) return;
    final h = MediaQuery.of(context).size.height;
    bool changed = false;
    for (final entry in _keys.entries) {
      if (_revealed.contains(entry.key)) continue;
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy < h * 0.92) {
        _revealed.add(entry.key);
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  @override
  void dispose() {
    _scroll.dispose();
    _breathe.dispose();
    _fragments.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Widget _reveal(String id, Widget child) {
    final v = _revealed.contains(id);
    return Container(
      key: _keys[id],
      child: AnimatedOpacity(
        opacity: v ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
        child: AnimatedSlide(
          offset: v ? Offset.zero : const Offset(0, 0.05),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.bg,
        body: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _breathe,
              builder: (_, __) =>
                  CustomPaint(painter: _AmbientPainter(_breathe.value)),
            ),
          ),
          CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child:
                          _BackButton(onTap: () => Navigator.of(context).pop()),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _HeroSection(
                  entrance: _entrance,
                  fragments: _fragments,
                  onExplore: () => _scroll.animateTo(
                    MediaQuery.of(context).size.height,
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeInOut,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                  child: _reveal('about', const _AboutSection())),
              SliverToBoxAdapter(child: _reveal('arch', const _ArchSection())),
              SliverToBoxAdapter(
                  child: _reveal('how', const _HowItWorksSection())),
              SliverToBoxAdapter(
                  child: _reveal('journey', const _JourneySection())),
              SliverToBoxAdapter(
                  child: _reveal('final', const _FinalSection())),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AMBIENT BACKGROUND PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _AmbientPainter extends CustomPainter {
  final double t;
  const _AmbientPainter(this.t);

  void _blob(Canvas c, Offset o, double r, Color col) {
    c.drawCircle(
      o,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [col, Colors.transparent],
        ).createShader(Rect.fromCircle(center: o, radius: r)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _C.bg);
    _blob(canvas, Offset(size.width * 0.88 + t * 18, -40 + t * 24),
        size.width * 0.70, _C.purpleGlow);
    _blob(canvas, Offset(-30 + t * 14, size.height * 0.82 - t * 20),
        size.width * 0.55, _C.goldGlow);
    _blob(
        canvas,
        Offset(size.width * 0.45 + t * 10, size.height * 0.38 - t * 10),
        size.width * 0.42,
        _C.indigoGlow);
  }

  @override
  bool shouldRepaint(_AmbientPainter o) => o.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED PRIMITIVE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? borderColor;

  const _GlassCard({
    required this.child,
    this.padding,
    this.radius = 16,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding ?? const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _C.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? _C.glassB, width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: _C.glass,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.glassB, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 13, color: _C.g1),
                const SizedBox(width: 6),
                Text('Back',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _C.g1,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool centered;
  const _Label(this.text, {this.centered = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, _C.purple.withOpacity(0.7)],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(text,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5,
                color: _C.purple,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.4)),
        const SizedBox(width: 10),
        Container(
          width: 18,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_C.purple.withOpacity(0.7), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}

class _DisplayTitle extends StatelessWidget {
  final String text;
  final double fontSize;
  final TextAlign align;
  const _DisplayTitle(this.text,
      {this.fontSize = 38, this.align = TextAlign.start});

  @override
  Widget build(BuildContext context) => Text(text,
      textAlign: align,
      style: TextStyle(
        fontFamily: 'CormorantGaramond',
        fontSize: fontSize,
        color: Colors.white,
        fontWeight: FontWeight.w400,
        height: 1.15,
        letterSpacing: 0.3,
      ));
}

// ─────────────────────────────────────────────────────────────────────────────
// FLOATING FRAGMENTS PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _FragmentsPainter extends CustomPainter {
  final double t;
  const _FragmentsPainter(this.t);

  static const _data = [
    ('How did the interview go?', 0.04, 0.10, 0.038, 0.055),
    ('I remembered something you told me.', 0.46, 0.62, 0.034, 0.045),
    ('You seemed quieter yesterday.', 0.62, 0.28, 0.042, 0.048),
    ('Still thinking about what you said.', 0.07, 0.78, 0.030, 0.040),
    ('How did it go with your mom?', 0.70, 0.45, 0.044, 0.038),
    ('You mentioned you were nervous.', 0.28, 0.38, 0.036, 0.042),
    ('Been thinking about you.', 0.74, 0.82, 0.032, 0.050),
    ('That sounded really hard.', 0.16, 0.55, 0.046, 0.038),
    ('Tell me more about that.', 0.54, 0.18, 0.040, 0.035),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in _data) {
      var ny = (d.$3 - t * d.$4) % 1.0;
      if (ny < 0) ny += 1.0;
      final fy = ny * size.height;

      double fade = 1.0;
      if (ny < 0.10)
        fade = ny / 0.10;
      else if (ny > 0.84) fade = (1.0 - ny) / 0.16;

      final alpha = (d.$5 * fade * 255).clamp(0.0, 255.0).toInt();
      if (alpha < 4) continue;

      final tp = TextPainter(
        text: TextSpan(
          text: '"${d.$1}"',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: Color.fromARGB(alpha, 214, 169, 92),
            fontWeight: FontWeight.w300,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.50);

      final dx = (d.$2 * size.width).clamp(8.0, size.width - tp.width - 8.0);
      tp.paint(canvas, Offset(dx, fy));
    }
  }

  @override
  bool shouldRepaint(_FragmentsPainter o) => o.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — HERO  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final AnimationController entrance;
  final AnimationController fragments;
  final VoidCallback onExplore;

  const _HeroSection({
    required this.entrance,
    required this.fragments,
    required this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final w = MediaQuery.of(context).size.width;

    return SizedBox(
      height: h * 0.94,
      child: Stack(children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: fragments,
            builder: (_, __) =>
                CustomPaint(painter: _FragmentsPainter(fragments.value)),
          ),
        ),
        Center(
          child: Container(
            width: w * 0.85,
            height: w * 0.85,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_C.purple.withOpacity(0.05), Colors.transparent],
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: entrance,
          builder: (_, __) {
            final fade = CurvedAnimation(
                parent: entrance,
                curve: const Interval(0.28, 1.0, curve: Curves.easeOut));
            final slide = CurvedAnimation(
                parent: entrance,
                curve: const Interval(0.15, 1.0, curve: Curves.easeOut));
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.09),
                  end: Offset.zero,
                ).animate(slide),
                child: _HeroContent(onExplore: onExplore),
              ),
            );
          },
        ),
        AnimatedBuilder(
          animation: entrance,
          builder: (_, __) => FadeTransition(
            opacity: CurvedAnimation(
                parent: entrance,
                curve: const Interval(0.85, 1.0, curve: Curves.easeIn)),
            child: const Positioned(
                bottom: 36, left: 0, right: 0, child: _ScrollHint()),
          ),
        ),
      ]),
    );
  }
}

class _HeroContent extends StatelessWidget {
  final VoidCallback onExplore;
  const _HeroContent({required this.onExplore});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _SolLogo(),
            const SizedBox(height: 30),
            const Text('SOL',
                style: TextStyle(
                  fontFamily: 'CormorantGaramond',
                  fontSize: 76,
                  color: Colors.white,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 22,
                )),
            const SizedBox(height: 10),
            Container(
              width: 56,
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, _C.gold, Colors.transparent],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'RELATIONSHIP-FIRST ARTIFICIAL INTELLIGENCE',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 9.5,
                  color: _C.g2,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2.8),
            ),
            const SizedBox(height: 30),
            Text(
              'A new generation of AI designed around\nmemory, continuity, personality,\nand human connection.\n\nBuilt to feel less like software\nand more like someone who remembers.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: _C.g1.withOpacity(0.88),
                  fontWeight: FontWeight.w300,
                  height: 1.85),
            ),
            const SizedBox(height: 44),
            _HeroCTA(onTap: onExplore),
          ],
        ),
      ),
    );
  }
}

class _SolLogo extends StatelessWidget {
  const _SolLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: _C.purple.withOpacity(0.35),
              blurRadius: 48,
              spreadRadius: 4),
          BoxShadow(
              color: _C.gold.withOpacity(0.12),
              blurRadius: 32,
              spreadRadius: 0),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/sol_logo.png',
          width: 82,
          height: 82,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 82,
            height: 82,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_C.purple, _C.indigo],
              ),
            ),
            child: const Center(
              child: Text('S',
                  style: TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 38,
                    color: Colors.white,
                    fontWeight: FontWeight.w300,
                  )),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCTA extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroCTA({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
            decoration: BoxDecoration(
              color: _C.purple.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: _C.purple.withOpacity(0.28), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Explore Sol',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4)),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_downward_rounded,
                    size: 14, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollHint extends StatelessWidget {
  const _ScrollHint();

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 1,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_C.g2.withOpacity(0.35), Colors.transparent],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('scroll',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 8.5,
                color: _C.g2.withOpacity(0.35),
                letterSpacing: 2.2,
                fontWeight: FontWeight.w500)),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — ABOUT THE PROJECT  (honest framing)
// ─────────────────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('ABOUT THE PROJECT'),
          const SizedBox(height: 22),
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gradient headline
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Colors.white, _C.goldLt],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(b),
                  child: const Text('Built By Aakash',
                      style: TextStyle(
                        fontFamily: 'CormorantGaramond',
                        fontSize: 36,
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                      )),
                ),

                const SizedBox(height: 30),

                // ── The problem ───────────────────────────────────
                _lede('The Problem'),
                const SizedBox(height: 12),
                _bp('Every conversation with an AI starts from zero.'),
                const SizedBox(height: 8),
                _bp(
                  'No memory of what you said last week. No context from '
                  'last month. No sense of who you are or what matters to you. '
                  'Every session is a blank slate — and that fundamentally '
                  'limits how meaningful those conversations can be.',
                ),

                const SizedBox(height: 24),

                // ── The idea ──────────────────────────────────────
                _lede('The Idea'),
                const SizedBox(height: 12),
                _bq('What if conversations with AI didn\'t have to reset?'),
                const SizedBox(height: 16),
                _bp(
                  'Sol is an attempt to solve that. Not by faking depth — '
                  'but by actually building the systems that create continuity: '
                  'multi-layer memory extraction, relationship progression, '
                  'personality-driven behavior, and proactive outreach.',
                ),

                const SizedBox(height: 24),

                // ── Honest assessment ─────────────────────────────
                _lede('Where We Are — Honestly'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _C.amber.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _C.amber.withOpacity(0.18), width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline_rounded,
                            size: 15, color: _C.amber.withOpacity(0.8)),
                        const SizedBox(width: 8),
                        Text('An honest note',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: _C.amber.withOpacity(0.8),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6)),
                      ]),
                      const SizedBox(height: 12),
                      Text(
                        'Sol creates the illusion of continuity — and works '
                        'hard to make that illusion feel real. The memory '
                        'system extracts facts. The relationship engine tracks '
                        'progression. The personality layer adapts over time.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: _C.g1,
                            height: 1.75,
                            fontWeight: FontWeight.w300),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'But genuine long-term continuity — the kind that '
                        'feels truly human — is still an open problem in AI. '
                        'Sol is a serious attempt at it.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: _C.g1,
                            height: 1.75,
                            fontWeight: FontWeight.w300),
                      ),
                      const SizedBox(height: 16),
                      // Progress indicator
                      _ProgressBar(
                          label: 'Continuity goal achieved', percent: 0.60),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── What it actually is ───────────────────────────
                _lede('What Sol Actually Is'),
                const SizedBox(height: 12),
                _bp(
                  'Three months. One developer. A working system with real '
                  'multi-layer memory, relationship progression, multiple '
                  'personality models, proactive messaging, and an inbox-first '
                  'social UX.',
                ),
                const SizedBox(height: 8),
                _bp(
                  'It\'s not complete. But it ships, it works, and every '
                  'architectural decision inside it was made intentionally.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lede(String text) => Text(text,
      style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          color: _C.purple,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4));

  Widget _bp(String text) => Text(text,
      style: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          color: _C.g1,
          fontWeight: FontWeight.w300,
          height: 1.78));

  Widget _bq(String text) => Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        decoration: BoxDecoration(
          color: _C.purple.withOpacity(0.07),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
          border: Border(
            left: BorderSide(color: _C.purple.withOpacity(0.55), width: 2),
          ),
        ),
        child: Text(text,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15.5,
                color: Colors.white,
                fontWeight: FontWeight.w500,
                height: 1.6)),
      );
}

/// Thin progress bar widget.
class _ProgressBar extends StatelessWidget {
  final String label;
  final double percent; // 0.0 – 1.0

  const _ProgressBar({required this.label, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: _C.g2, fontWeight: FontWeight.w400)),
            Text('${(percent * 100).toInt()}%',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _C.amber,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 4,
            color: Colors.white.withOpacity(0.06),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percent,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_C.purple, _C.gold],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — TECHNICAL ARCHITECTURE  (docs link + free-tier story)
// ─────────────────────────────────────────────────────────────────────────────

class _ArchSection extends StatelessWidget {
  const _ArchSection();

  void _copyDocsUrl(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: _kDocsUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Docs URL copied',
            style:
                GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white)),
        backgroundColor: _C.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('TECHNICAL ARCHITECTURE'),
          const SizedBox(height: 18),
          const _DisplayTitle('Technical Architecture'),
          const SizedBox(height: 28),

          // ── DOCS LINK CARD (prominent) ─────────────────────────
          _DocsCard(onTap: () => _copyDocsUrl(context)),
          const SizedBox(height: 32),

          // ── The free-tier challenge ────────────────────────────
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _C.gold.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: _C.gold.withOpacity(0.22), width: 0.5),
                    ),
                    child: Text('THE CHALLENGE',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9.5,
                            color: _C.gold,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8)),
                  ),
                ]),
                const SizedBox(height: 18),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Colors.white, _C.goldLt],
                  ).createShader(b),
                  child: Text(
                    'Built entirely on free tiers.\nFrom a dorm room. On purpose.',
                    style: const TextStyle(
                      fontFamily: 'CormorantGaramond',
                      fontSize: 28,
                      color: Colors.white,
                      fontWeight: FontWeight.w400,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'The constraint wasn\'t an obstacle — it was the design goal. '
                  'A 3rd-year CS student, zero budget, and an idea that felt '
                  'worth building properly. Every architectural decision had to '
                  'justify itself within the free tier.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      color: _C.g1,
                      fontWeight: FontWeight.w300,
                      height: 1.78),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Free tier breakdown ────────────────────────────────
          const _FreeTierCard(),
          const SizedBox(height: 32),

          // ── Stack cards ────────────────────────────────────────
          const _ArchStackCard(
            icon: Icons.dns_outlined,
            title: 'Backend',
            accent: _C.purple,
            items: [
              'FastAPI',
              'Python',
              'Firebase Authentication',
              'SQLite',
              'ChromaDB',
              'Groq LLM Integration',
            ],
          ),
          const SizedBox(height: 14),
          const _ArchStackCard(
            icon: Icons.phone_android_outlined,
            title: 'Frontend',
            accent: _C.gold,
            items: [
              'Flutter',
              'Firebase',
              'Google Sign-In',
              'Push Notifications',
              'Shared Preferences',
            ],
          ),
          const SizedBox(height: 14),
          const _ArchStackCard(
            icon: Icons.cloud_queue_outlined,
            title: 'Infrastructure',
            accent: _C.indigo,
            items: [
              'Railway Deployment',
              'Persistent Volume Storage',
              'Vector Memory (Chroma)',
              'Relationship Engine',
            ],
          ),
        ],
      ),
    );
  }
}

/// Prominent Docusaurus link card.
class _DocsCard extends StatelessWidget {
  final VoidCallback onTap;
  const _DocsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _C.purple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: _C.purple.withOpacity(0.30), width: 0.8),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _C.purple.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                        color: _C.purple.withOpacity(0.25), width: 0.5),
                  ),
                  child: const Icon(Icons.menu_book_outlined,
                      color: _C.purple, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Architecture Documentation',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        'Detailed technical spec, system design, '
                        'and implementation decisions — built with Docusaurus.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: _C.g2,
                            height: 1.55,
                            fontWeight: FontWeight.w400),
                      ),
                      const SizedBox(height: 8),
                      Text(_kDocsUrl,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: _C.purple.withOpacity(0.80),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.north_east_rounded,
                    size: 18, color: _C.purple),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Free-tier breakdown cards.
class _FreeTierCard extends StatelessWidget {
  const _FreeTierCard();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Free Tier Breakdown',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          const _FreeTierRow(
            icon: Icons.bolt_outlined,
            name: 'Groq API',
            color: _C.purple,
            why: 'LPU-based inference — significantly faster than GPU servers '
                'and the free tier is generous enough for real use.',
            capacity:
                'Free tier · Rate limited but sufficient for early-stage traffic',
          ),
          const SizedBox(height: 16),
          const _FreeTierRow(
            icon: Icons.train_rounded,
            name: 'Railway (Hobby)',
            color: _C.indigo,
            why: 'Persistent volumes, auto-deploy from GitHub, and enough '
                'compute for a backend that handles hundreds of concurrent users '
                'at this stage of the product.',
            capacity:
                'Hobby plan · \$5/mo credit — effectively free for MVP scale',
          ),
          const SizedBox(height: 16),
          const _FreeTierRow(
            icon: Icons.local_fire_department_outlined,
            name: 'Firebase',
            color: _C.gold,
            why: 'Auth, push notifications, and app config — all within '
                'Spark (free) tier limits for the current user base.',
            capacity: 'Spark plan · Free up to generous MAU and storage limits',
          ),
          const SizedBox(height: 16),
          const _FreeTierRow(
            icon: Icons.storage_outlined,
            name: 'SQLite + ChromaDB',
            color: _C.g2,
            why: 'Self-hosted on the Railway volume. No external DB cost. '
                'Scales to tens of thousands of relationship pairs before '
                'a migration would be needed.',
            capacity: 'Self-hosted · Zero additional cost',
          ),
        ],
      ),
    );
  }
}

class _FreeTierRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final Color color;
  final String why;
  final String capacity;

  const _FreeTierRow({
    required this.icon,
    required this.name,
    required this.color,
    required this.why,
    required this.capacity,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.20), width: 0.5),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(why,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _C.g2,
                      height: 1.60,
                      fontWeight: FontWeight.w400)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(5),
                  border:
                      Border.all(color: color.withOpacity(0.15), width: 0.5),
                ),
                child: Text(capacity,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        color: color.withOpacity(0.85),
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ArchStackCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accent;
  final List<String> items;

  const _ArchStackCard({
    required this.icon,
    required this.title,
    required this.accent,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: accent.withOpacity(0.20), width: 0.5),
            ),
            child: Icon(icon, color: accent, size: 19),
          ),
          const SizedBox(width: 14),
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              items.map((i) => _TechChip(label: i, accent: accent)).toList(),
        ),
      ]),
    );
  }
}

class _TechChip extends StatelessWidget {
  final String label;
  final Color accent;
  const _TechChip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withOpacity(0.18), width: 0.5),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: _C.g1, fontWeight: FontWeight.w400)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — HOW SOL WORKS  (timeline, unchanged from v1)
// ─────────────────────────────────────────────────────────────────────────────

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('HOW IT WORKS'),
          const SizedBox(height: 18),
          const _DisplayTitle('How Sol Works'),
          const SizedBox(height: 36),
          const _TStep(
              '01',
              'Identity Layer',
              'Users authenticate through Firebase Authentication, establishing a secure, persistent digital identity.',
              false),
          const _TStep(
              '02',
              'Relationship Layer',
              'Sol creates a unique user-companion relationship identity. Every relationship exists independently — its own thread of shared history.',
              false),
          const _TStep(
              '03',
              'Memory Layer',
              'Important information is extracted and stored across multiple systems.\n\nFacts.  Patterns.  Emotional events.  Narrative summaries.  Semantic memories.',
              false),
          const _TStep(
              '04',
              'Context Assembly',
              'Before every response, Sol rebuilds full context from memory, relationship history, and conversation state.',
              false),
          const _TStep(
              '05',
              'Personality Layer',
              'Each companion has its own behavior model, communication style, relationship arc, and proactive outreach strategy.',
              false),
          const _TStep(
              '06',
              'Response Generation',
              'Context is combined with personality instructions and processed through the language model.',
              false),
          const _TStep(
              '07',
              'Continuity Engine',
              'The conversation updates memory, relationship progression, and future context. Every exchange accumulates.',
              true),
        ],
      ),
    );
  }
}

class _TStep extends StatelessWidget {
  final String number, title, desc;
  final bool isLast;
  const _TStep(this.number, this.title, this.desc, this.isLast);

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 50,
          child: Column(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _C.purple.withOpacity(0.10),
                border:
                    Border.all(color: _C.purple.withOpacity(0.30), width: 0.5),
              ),
              child: Center(
                child: Text(number,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 9.5,
                        color: _C.purple,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            if (!isLast)
              Expanded(
                child: Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _C.purple.withOpacity(0.30),
                        _C.purple.withOpacity(0.04),
                      ],
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: 12, bottom: isLast ? 0 : 38, top: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        height: 1.3)),
                const SizedBox(height: 9),
                Text(desc,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5,
                        color: _C.g2,
                        height: 1.72,
                        fontWeight: FontWeight.w400)),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — DEVELOPMENT JOURNEY  (simplified metrics)
// ─────────────────────────────────────────────────────────────────────────────

class _JourneySection extends StatelessWidget {
  const _JourneySection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('DEVELOPMENT JOURNEY'),
          const SizedBox(height: 18),
          const _DisplayTitle('Ideation to MVP'),
          const SizedBox(height: 8),
          Text(
            '3 months of continuous work.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: _C.g2,
                fontWeight: FontWeight.w300,
                height: 1.6),
          ),
          const SizedBox(height: 28),
          _GlassCard(
            child: Column(children: [
              // Big metrics row
              Row(
                children: [
                  _JourneyMetric(
                    value: '3',
                    unit: 'Mo',
                    label: 'Ideation\nto MVP',
                    color: _C.purple,
                  ),
                  _vDivider(),
                  _JourneyMetric(
                    value: '20k+',
                    unit: 'LoC',
                    label: 'Lines of\nauthored code',
                    color: _C.gold,
                  ),
                  _vDivider(),
                  _JourneyMetric(
                    value: '∞',
                    unit: '',
                    label: 'Unique\nrelationships',
                    color: _C.violet,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Container(height: 0.5, color: _C.glassB),
              const SizedBox(height: 24),

              // Context note
              Text(
                '"Infinite unique relationships" isn\'t marketing copy — '
                'it\'s how the data model actually works. Every user-companion '
                'pair gets its own memory boundary, relationship state, '
                'and conversation history. Completely isolated. No shared state.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _C.g2,
                    height: 1.70,
                    fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 24),
              Container(height: 0.5, color: _C.glassB),
              const SizedBox(height: 20),

              // Stack badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StackBadge('Flutter'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('+',
                        style: GoogleFonts.plusJakartaSans(
                            color: _C.g2,
                            fontSize: 18,
                            fontWeight: FontWeight.w200)),
                  ),
                  _StackBadge('FastAPI'),
                  const SizedBox(width: 12),
                  Text('Full Stack',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color: _C.g2,
                          fontWeight: FontWeight.w400)),
                ],
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 0.5,
        height: 80,
        color: _C.glassB,
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

class _JourneyMetric extends StatelessWidget {
  final String value, unit, label;
  final Color color;
  const _JourneyMetric({
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ShaderMask(
                  shaderCallback: (b) => LinearGradient(
                    colors: [Colors.white, color],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(b),
                  child: Text(value,
                      style: const TextStyle(
                        fontFamily: 'CormorantGaramond',
                        fontSize: 44,
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                        height: 0.95,
                      )),
                ),
                if (unit.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7, left: 3),
                    child: Text(unit,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: color,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _C.g2,
                    fontWeight: FontWeight.w400,
                    height: 1.45)),
          ],
        ),
      );
}

class _StackBadge extends StatelessWidget {
  final String label;
  const _StackBadge(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: _C.purple.withOpacity(0.10),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _C.purple.withOpacity(0.22), width: 0.5),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: _C.g1, fontWeight: FontWeight.w500)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — FINAL STATEMENT + ROADMAP
// ─────────────────────────────────────────────────────────────────────────────

class _FinalSection extends StatelessWidget {
  const _FinalSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Personal statement ─────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(24, 72, 24, 56),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                _C.purple.withOpacity(0.04),
                _C.gold.withOpacity(0.03),
                Colors.transparent,
              ],
            ),
            border: Border.symmetric(
              horizontal:
                  BorderSide(color: Colors.white.withOpacity(0.05), width: 0.5),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 1,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, _C.glassB],
                  ),
                ),
              ),
              const SizedBox(height: 44),

              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [Colors.white, _C.goldLt, Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(b),
                child: const Text(
                  'Conversations Shouldn\'t\nStart From Zero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 46,
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    height: 1.18,
                    letterSpacing: 0.4,
                  ),
                ),
              ),

              const SizedBox(height: 44),

              Text(
                'I want to build something that people actually love.\nNot something that impresses — something that someone\nopens at 2am because they want to talk.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15.5,
                    color: _C.g1,
                    height: 1.88,
                    fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 18),
              Text(
                'That\'s the bar. Sol is how I\'m trying to get there.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    color: _C.g2,
                    height: 1.75,
                    fontWeight: FontWeight.w300),
              ),

              const SizedBox(height: 52),

              // Ornamental divider
              Row(children: [
                Expanded(
                  child: Container(
                    height: 0.5,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, _C.glassB],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _C.gold.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 0.5,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_C.glassB, Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),

        // ── Roadmap ────────────────────────────────────────────
        const _RoadmapSection(),

        // ── Footer ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
          child: Column(children: [
            Text('Designed and Developed by Aakash',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _C.g2,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Text('Sol — Relationship-First AI',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: _C.g2.withOpacity(0.45),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.6)),
          ]),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROADMAP  (delivered · in progress · planned)
// ─────────────────────────────────────────────────────────────────────────────

class _RoadmapSection extends StatelessWidget {
  const _RoadmapSection();

  // ── Roadmap data ───────────────────────────────────────────
  static const _shipped = [
    'Firebase Authentication',
    'Inbox-first social home screen',
    'Multi-companion roster + chemistry matching',
    'Multi-layer long-term memory extraction',
    'Relationship progression engine',
    'Proactive messaging system',
    'Burst-style chat (text-message realism)',
    'Semantic episodic memory (ChromaDB)',
    'Personality framework (12 characters)',
    'Privacy & presence settings screen',
    'Railway + SQLite + Chroma deployment',
    'Free-tier full-stack architecture',
  ];

  static const _inProgress = [
    'Push notifications (full end-to-end)',
    'Memory consolidation improvements',
    'Proactive strategy refinement',
    'Onboarding flow polish',
    'Error handling & edge case hardening',
  ];

  static const _planned = [
    'End-to-end message encryption',
    'More robust production architecture',
    'Memory transparency dashboard for users',
    'Voice message support',
    'Expanded character roster',
    'Web companion version',
    'Multi-language support',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('WHAT\'S BEEN BUILT · WHAT\'S COMING'),
          const SizedBox(height: 18),
          const _DisplayTitle('Roadmap'),
          const SizedBox(height: 8),
          Text(
            'A transparent look at where Sol stands today.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: _C.g2,
                fontWeight: FontWeight.w300,
                height: 1.6),
          ),
          const SizedBox(height: 28),

          // Summary bar
          _RoadmapSummaryBar(
            shipped: _shipped.length,
            inProgress: _inProgress.length,
            planned: _planned.length,
          ),
          const SizedBox(height: 24),

          // Shipped
          _RoadmapGroup(
            status: 'SHIPPED',
            statusColor: _C.shipped,
            icon: Icons.check_circle_outline_rounded,
            items: _shipped,
          ),
          const SizedBox(height: 14),

          // In Progress
          _RoadmapGroup(
            status: 'IN PROGRESS',
            statusColor: _C.inProg,
            icon: Icons.sync_rounded,
            items: _inProgress,
            pulsing: true,
          ),
          const SizedBox(height: 14),

          // Planned
          _RoadmapGroup(
            status: 'ON THE ROADMAP',
            statusColor: _C.planned,
            icon: Icons.radio_button_unchecked_rounded,
            items: _planned,
          ),
        ],
      ),
    );
  }
}

/// Progress summary bar showing shipped / in-progress / planned counts.
class _RoadmapSummaryBar extends StatelessWidget {
  final int shipped, inProgress, planned;
  const _RoadmapSummaryBar({
    required this.shipped,
    required this.inProgress,
    required this.planned,
  });

  @override
  Widget build(BuildContext context) {
    final total = shipped + inProgress + planned;
    return _GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: Row(children: [
              Flexible(
                flex: shipped,
                child: Container(color: _C.shipped),
              ),
              Flexible(
                flex: inProgress,
                child: Container(color: _C.inProg),
              ),
              Flexible(
                flex: planned,
                child: Container(color: Colors.white.withOpacity(0.06)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        // Legend row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BarLegend(color: _C.shipped, label: 'Shipped', count: shipped),
            _BarLegend(
                color: _C.inProg, label: 'In Progress', count: inProgress),
            _BarLegend(color: _C.planned, label: 'Planned', count: planned),
          ],
        ),
      ]),
    );
  }
}

class _BarLegend extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _BarLegend(
      {required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('$count',
            style: TextStyle(
              fontFamily: 'CormorantGaramond',
              fontSize: 32,
              color: color,
              fontWeight: FontWeight.w400,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10.5, color: _C.g2, fontWeight: FontWeight.w500)),
      ]);
}

/// One group of roadmap items (shipped / in-progress / planned).
class _RoadmapGroup extends StatelessWidget {
  final String status;
  final Color statusColor;
  final IconData icon;
  final List<String> items;
  final bool pulsing;

  const _RoadmapGroup({
    required this.status,
    required this.statusColor,
    required this.icon,
    required this.items,
    this.pulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(status,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8)),
          ]),
          const SizedBox(height: 16),
          // Items
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    pulsing
                        ? _PulseDot(color: statusColor)
                        : Icon(icon,
                            size: 14, color: statusColor.withOpacity(0.75)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(item,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              color: _C.g1,
                              fontWeight: FontWeight.w400,
                              height: 1.4)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// Animated pulsing dot for in-progress items.
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.35, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(_pulse.value),
        ),
      ),
    );
  }
}
