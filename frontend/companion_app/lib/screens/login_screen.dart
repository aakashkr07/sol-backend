// =============================================================================
// lib/screens/login_screen.dart
// Sol · Login Screen — Flutter/Dart  [SOL DESIGN SYSTEM ALIGNMENT v3]
// =============================================================================
//
// VISUAL CHANGES ONLY — zero backend/auth/logic changes:
//
//   · Font stack updated: Plus Jakarta Sans (display/emotional) + Jost (meta/label)
//     to match Sol design system used throughout the rest of the app.
//
//   · Palette aligned to Sol's canonical colours:
//       _bgDeep  #080A0E  (was #0B0D11)
//       _blue    #7DA2FF  Presence Blue — now used on button glow + bloom orb
//       _violet  #A78BFA  Warm Violet   — now used on secondary tagline + pulse
//       _cream   #E8DDD0  (was #E4D5BB)
//       _sand    #9A8C78  (unchanged)
//       _amber / _amberSft / _warmth unchanged — still drive logo bloom
//
//   · Wordmark: Jost w200 replaces interTight, tracking reduced (14 → 9)
//     to feel like the 'sol' eyebrow label in InboxScreen.
//
//   · Primary tagline: Plus Jakarta Sans w300, sand @ 0.72, tracking 0.4
//     — warmer, less mechanical than the previous Inter w300 + 2.8 spacing.
//
//   · Secondary cycling tagline: Jost w300, violet tint @ 0.38
//     (was sand-only; now carries the violet emotional depth accent).
//
//   · Button: glassmorphic treatment aligned to InboxScreen._iconBtn style —
//     backdrop-filter blur, cream border @ 0.07, Presence Blue glow replaces
//     plain amber-only glow so it sits in the blue/amber dual-accent palette.
//     Text now Plus Jakarta Sans w400 to match tile names in InboxScreen.
//
//   · Amber bloom orb gains a second Presence Blue orb at bottom-right (same
//     breathing pattern as _AtmospherePainter in inbox) so the login bg reads
//     as the same atmospheric space.
//
//   · Error text: Jost w300, _dustRose (unchanged value, font aligned).
//
//   · Privacy footer: Jost w300 replaces Inter to match section labels.
//
//   · Loader: strokeWidth 1.0, blue @ 0.45 — identical to InboxScreen loader.
//
//   ALL animation controllers, entrance sequence, shimmer, burst, tagline
//   cycling, button behaviour, and every auth/navigation call are UNTOUCHED.
//
// =============================================================================

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../painters/fragment_painter.dart';
import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — Sol Design System (canonical, matches InboxScreen)
// ─────────────────────────────────────────────────────────────────────────────

const Color _bgDeep = Color(0xFF080A0E); // Sol _bgDeep
const Color _surface = Color(0xFF10131A); // Sol _surface — used on button bg
const Color _blue = Color(0xFF7DA2FF); // Presence Blue
const Color _violet = Color(0xFFA78BFA); // Warm Violet
const Color _amber =
    Color(0xFFF2B8A0); // Human Warmth (login uses this as primary bloom)
const Color _amberAcc =
    Color(0xFFF0952A); // Amber accent (button glow, shimmer)
const Color _cream = Color(0xFFE8DDD0); // Sol _cream
const Color _sand = Color(0xFF9A8C78); // Sol _sand
const Color _ink = Color(0xFF060810); // Sol _ink
const Color _dustRose = Color(0xFFBB7070);

// ─────────────────────────────────────────────────────────────────────────────
// Taglines — unchanged
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _taglines = [
  'back again?',
  'good to see you',
  'still awake?',
  'how was today?',
  'long day?',
  'couldn\'t sleep either?',
  'you okay?',
  'hey.',
];

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers — UNTOUCHED ────────────────────────────────────
  late final AnimationController _ticker;
  late final AnimationController _entranceCtrl;
  late final AnimationController _tagCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _burstCtrl;

  // ── Entrance animations — UNTOUCHED ──────────────────────────────────────
  late final Animation<double> _logoIn;
  late final Animation<double> _wordIn;
  late final Animation<double> _taglineIn;
  late final Animation<double> _tagIn;
  late final Animation<double> _btnIn;
  late final Animation<double> _privacyIn;

  // ── Tag / shimmer / burst — UNTOUCHED ────────────────────────────────────
  late final Animation<double> _tagFade;
  int _tagIdx = 0;
  late final Animation<double> _shimmer;
  late final Animation<double> _burstGlow;

  // ── Background time — UNTOUCHED ───────────────────────────────────────────
  double _t = 0;

  // ── Logo position — UNTOUCHED ─────────────────────────────────────────────
  final ValueNotifier<Offset> _logoCenterNotifier =
      ValueNotifier(const Offset(187.5, 212.0));
  final GlobalKey _logoKey = GlobalKey();

  // ── Button state — UNTOUCHED ──────────────────────────────────────────────
  bool _isLoading = false;
  bool _btnPressed = false;
  String? _error;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _setupControllers();
    _setupAnimations();
    _startEntrance();
    _cycleTags();
  }

  @override
  void dispose() {
    _logoCenterNotifier.dispose();
    _ticker.dispose();
    _entranceCtrl.dispose();
    _tagCtrl.dispose();
    _shimmerCtrl.dispose();
    _burstCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Controllers & animations — UNTOUCHED
  // ─────────────────────────────────────────────────────────────────────────
  void _setupControllers() {
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 999),
    )
      ..addListener(_onTick)
      ..forward();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _tagCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );

    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  void _setupAnimations() {
    _logoIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.00, 0.50, curve: Curves.easeOutCubic),
    );
    _wordIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.28, 0.62, curve: Curves.easeOutCubic),
    );
    _taglineIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.36, 0.68, curve: Curves.easeOutCubic),
    );
    _tagIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.42, 0.72, curve: Curves.easeOut),
    );
    _btnIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.58, 0.90, curve: Curves.easeOutCubic),
    );
    _privacyIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.74, 1.00, curve: Curves.easeOut),
    );
    _tagFade = CurvedAnimation(parent: _tagCtrl, curve: Curves.easeInOut);
    _shimmer = CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut);
    _burstGlow = CurvedAnimation(
      parent: _burstCtrl,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Entrance / shimmer / tag cycling — UNTOUCHED
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _startEntrance() async {
    await Future.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    _entranceCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    _loopShimmer();
  }

  Future<void> _loopShimmer() async {
    while (mounted && !_isLoading) {
      await Future.delayed(Duration(
        milliseconds: 6500 + math.Random().nextInt(3000),
      ));
      if (!mounted || _isLoading) return;
      _shimmerCtrl.forward(from: 0);
    }
  }

  Future<void> _cycleTags() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 7000));
      if (!mounted) return;
      await _tagCtrl.forward();
      if (!mounted) return;
      setState(() => _tagIdx = (_tagIdx + 1) % _taglines.length);
      await _tagCtrl.reverse();
    }
  }

  // ── Tick — UNTOUCHED (only drives bloom + logo breath) ────────────────────
  void _onTick() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _logoKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final pos = box.localToGlobal(Offset.zero);
        final center = pos + Offset(box.size.width / 2, box.size.height / 2);
        if (center != _logoCenterNotifier.value) {
          _logoCenterNotifier.value = center;
        }
      }
    });
    _t += 0.003;
  }

  // ── Sign-in handler — UNTOUCHED ───────────────────────────────────────────
  Future<void> _handleSignIn() async {
    if (_isLoading) return;
    HapticFeedback.mediumImpact();
    _burstCtrl.forward(from: 0);
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = await AuthService.signInWithGoogle();
      if (!mounted) return;
      if (user == null) {
        setState(() => _isLoading = false);
        _loopShimmer();
      }
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _isLoading = false;
        _error = 'Something went wrong. Try again.';
      });
      _loopShimmer();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: _bgDeep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Fragment ambient field ─────────────────────────────────────
          Positioned.fill(
            child: FragmentField(
              logoCenter: _logoCenterNotifier,
            ),
          ),

          // ── Atmospheric orbs — matches _AtmospherePainter in InboxScreen ─
          _buildAtmosphere(),

          // ── Bottom vignette ────────────────────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      _bgDeep.withValues(alpha: 0.45),
                      _bgDeep.withValues(alpha: 0.92),
                    ],
                    stops: const [0.0, 0.50, 0.78, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────
          SafeArea(
            child: SizedBox.expand(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),
                  _buildLogo(),
                  const Spacer(flex: 2),
                  _buildWordmark(),
                  const SizedBox(height: 10),
                  _buildTaglinePrimary(),
                  const SizedBox(height: 20),
                  _buildTagSecondary(),
                  const Spacer(flex: 2),
                  _buildButton(),
                  const SizedBox(height: 16),
                  if (_error != null) _buildError(),
                  if (_error != null) const SizedBox(height: 8),
                  const Spacer(flex: 1),
                  _buildPrivacy(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Atmospheric orbs — same three-orb breathing pattern as InboxScreen ────
  Widget _buildAtmosphere() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ticker,
          builder: (_, __) {
            final p = (math.sin(_t * 0.6) + 1) / 2;
            final pFast = (math.sin(_t * 0.88 + 1.2) + 1) / 2;
            return Stack(
              children: [
                // Orb 1 — top-centre, amber warmth (logo bloom, as before)
                Positioned(
                  top: 40 + math.sin(_t * math.pi * 0.6) * 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 360 + p * 40,
                      height: 360 + p * 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _amber.withValues(alpha: 0.045 + p * 0.018),
                            _amberAcc.withValues(alpha: 0.022 + p * 0.010),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.38, 0.72],
                        ),
                      ),
                    ),
                  ),
                ),
                // Orb 2 — bottom-right, Presence Blue (matches InboxScreen orb 1)
                Positioned(
                  bottom: -60 - pFast * 20,
                  right: -40 - math.cos(_t * math.pi * 0.6) * 10,
                  child: Container(
                    width: 280 + (1 - pFast) * 50,
                    height: 280 + (1 - pFast) * 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _blue.withValues(alpha: 0.028 + pFast * 0.018),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Orb 3 — bottom-left, Warm Violet (matches InboxScreen orb 2)
                Positioned(
                  bottom: 20 + math.sin(_t * math.pi * 0.4 + 1) * 12,
                  left: -30,
                  child: Container(
                    width: 220 + p * 30,
                    height: 220 + p * 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _violet.withValues(alpha: 0.022 + p * 0.016),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Logo — UNTOUCHED (animation logic preserved; only inner halo colours
  //   now carry _blue for the outer ring to bind to the Sol blue palette) ───
  Widget _buildLogo() {
    return FadeTransition(
      opacity: _logoIn,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.82, end: 1.0).animate(_logoIn),
        child: SizedBox(
          key: _logoKey,
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer halo — amber, slow breath (unchanged)
              AnimatedBuilder(
                animation: _ticker,
                builder: (_, __) {
                  final p = (math.sin(_t * 0.42) + 1) / 2;
                  return Container(
                    width: 290,
                    height: 290,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(255, 111, 69, 238)
                              .withValues(alpha: 0.07 + p * 0.08),
                          blurRadius: 80 + p * 35,
                          spreadRadius: 4 + p * 10,
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Secondary halo — Presence Blue, opposite phase
              // Gives the logo a dual-tone corona matching Sol's blue/amber duality
              AnimatedBuilder(
                animation: _ticker,
                builder: (_, __) {
                  final p = (math.sin(_t * 0.32 + math.pi) + 1) / 2;
                  return Container(
                    width: 270,
                    height: 270,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(255, 95, 136, 238)
                              .withValues(alpha: 0.04 + p * 0.055),
                          blurRadius: 60 + p * 28,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Inner orb — warmth offset (unchanged)
              AnimatedBuilder(
                animation: _ticker,
                builder: (_, __) {
                  final p = (math.sin(_t * 0.88 + 0.5) + 1) / 2;
                  return Transform.translate(
                    offset: const Offset(14, -10),
                    child: Container(
                      width: 210,
                      height: 210,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color.fromARGB(255, 250, 184, 109)
                                .withValues(alpha: 0.13 + p * 0.20),
                            blurRadius: 28 + p * 28,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Logo image — breathes (UNTOUCHED)
              AnimatedBuilder(
                animation: _ticker,
                builder: (_, child) {
                  final p = (math.sin(_t * 0.42) + 1) / 2;
                  return Transform.scale(
                    scale: 1.0 + p * 0.020,
                    child: child,
                  );
                },
                child: Opacity(
                  opacity: 0.85,
                  child: Image.asset(
                    'assets/images/sol_logo.png',
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Wordmark — Jost w200 (matches 'sol' eyebrow in InboxScreen) ───────────
  Widget _buildWordmark() {
    return FadeTransition(
      opacity: _wordIn,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.16),
          end: Offset.zero,
        ).animate(_wordIn),
        child: Text(
          'Sol', // lowercase — matches InboxScreen eyebrow label convention
          style: GoogleFonts.jost(
            fontWeight: FontWeight.w200,
            fontSize: 64,
            color: _amber.withValues(alpha: 0.92),
            letterSpacing: 22,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  // ── Primary tagline — Plus Jakarta Sans w300 (display font in Sol) ────────
  Widget _buildTaglinePrimary() {
    return FadeTransition(
      opacity: _taglineIn,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.10),
          end: Offset.zero,
        ).animate(_taglineIn),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w300,
              fontSize: 14,
              color: _sand.withValues(alpha: 0.65),
              letterSpacing: 0.4,
              height: 1.0,
            ),
            children: [
              const TextSpan(text: 'A so'),
              TextSpan(
                text: 'U',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: _violet.withValues(alpha: 0.88),
                  letterSpacing: 0.4,
                ),
              ),
              const TextSpan(text: 'l waiting for you.'),
            ],
          ),
        ),
      ),
    );
  }

  // ── Secondary tagline — Jost w300, violet tint (emotional depth) ─────────
  Widget _buildTagSecondary() {
    return FadeTransition(
      opacity: _tagIn,
      child: SizedBox(
        height: 18,
        child: AnimatedBuilder(
          animation: _tagFade,
          builder: (_, __) => Opacity(
            opacity: (1.0 - _tagFade.value).clamp(0.0, 1.0),
            child: Text(
              _taglines[_tagIdx],
              style: GoogleFonts.jost(
                fontWeight: FontWeight.w300,
                fontSize: 11,
                color: _violet.withValues(alpha: 0.38),
                letterSpacing: 2.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Button — glassmorphic, aligned to InboxScreen._iconBtn aesthetic ──────
  Widget _buildButton() {
    return FadeTransition(
      opacity: _btnIn,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(_btnIn),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: AnimatedBuilder(
            animation: Listenable.merge([_shimmerCtrl, _burstCtrl]),
            builder: (_, __) {
              return GestureDetector(
                onTapDown: (_) => setState(() => _btnPressed = true),
                onTapUp: (_) {
                  setState(() => _btnPressed = false);
                  _handleSignIn();
                },
                onTapCancel: () => setState(() => _btnPressed = false),
                child: AnimatedScale(
                  scale: _btnPressed ? 0.970 : 1.0,
                  duration: const Duration(milliseconds: 90),
                  curve: Curves.easeOut,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        height: 54,
                        width: 280,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _cream.withValues(alpha: _isLoading ? 0.04 : 0.07,),
                            width: 0.6,
                          ),
                          color: _surface.withValues(alpha: 0.60),
                          boxShadow: [
                            // Burst glow — amber (on tap, unchanged feel)
                            BoxShadow(
                              color: const Color.fromARGB(255, 60, 83, 141)
                                  .withValues(alpha: _burstGlow.value * 0.20,),
                              blurRadius: 40,
                              spreadRadius: 0,
                            ),
                            // Resting glow — Presence Blue (new, ties to Sol palette)
                            BoxShadow(
                              color: _blue.withValues(alpha: 0.055),
                              blurRadius: 22,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Shimmer sweep — UNTOUCHED logic
                            if (!_isLoading)
                              Positioned.fill(
                                child: FractionalTranslation(
                                  translation: Offset(
                                    -1.6 + _shimmer.value * 3.2,
                                    0,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          _cream.withValues(alpha: 0.025),
                                          _cream.withValues(alpha: 0.060),
                                          _cream.withValues(alpha: 0.025),
                                          Colors.transparent,
                                        ],
                                        stops: const [
                                          0.0,
                                          0.3,
                                          0.5,
                                          0.7,
                                          1.0,
                                        ],
                                        transform: const GradientRotation(0.4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // Content — UNTOUCHED logic, font updated
                            _isLoading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.0,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _blue.withValues(alpha: 0.45),
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      _googleLogo(),
                                      const SizedBox(width: 7),
                                      Text(
                                        'Continue with Google',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.w400,
                                          fontSize: 14,
                                          color: _cream.withValues(alpha: 0.72),
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Error — Jost w300 (aligned to Sol meta/label font) ───────────────────
  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        _error ?? '',
        style: GoogleFonts.jost(
          fontSize: 11.5,
          fontWeight: FontWeight.w300,
          color: _dustRose.withValues(alpha: 0.65),
          letterSpacing: 0.2,
          height: 1.6,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Privacy — Jost w300 (matches section labels in InboxScreen) ──────────
  Widget _buildPrivacy() {
    return FadeTransition(
      opacity: _privacyIn,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Text(
          'Your conversations and memories are encrypted,\nprivate, and always under your control.',
          style: GoogleFonts.jost(
            fontSize: 10,
            fontWeight: FontWeight.w300,
            color: _sand.withValues(alpha: 0.28),
            letterSpacing: 0.2,
            height: 1.85,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── Google logo — UNTOUCHED ───────────────────────────────────────────────
  Widget _googleLogo() {
    return SizedBox(
      width: 16,
      height: 16,
      child: Image.asset(
        'assets/images/google_logo.png',
        fit: BoxFit.contain,
      ),
    );
  }
}
