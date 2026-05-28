// =============================================================================
// lib/screens/login_screen.dart
// Sol · Login Screen — Flutter/Dart
// =============================================================================
//
// DEPENDENCIES (pubspec.yaml):
//   google_sign_in: ^6.2.1
//   firebase_auth: ^4.19.1
//   google_fonts: ^6.2.1
//
// ASSETS (pubspec.yaml):
//   assets:
//     - assets/images/sol_logo.png
//     - assets/images/google_logo.png
//
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../painters/fragment_painter.dart';
import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────

const Color _bg = Color(0xFF050810);
const Color _cream = Color(0xFFE4D5BB);
const Color _amber = Color(0xFFF0952A);
const Color _amberSft = Color(0xFFF5B86A);
const Color _sand = Color(0xFF9A8C78);
const Color _ink = Color(0xFF030508);
const Color _dustRose = Color(0xFFBB7070); // error

// ─────────────────────────────────────────────────────────────────────────────
// Taglines
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
  // ── Animation controllers ─────────────────────────────────────────────────
  late final AnimationController _ticker;
  late final AnimationController _entranceCtrl;
  late final AnimationController _tagCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _burstCtrl;

  // Entrance
  late final Animation<double> _logoIn;
  late final Animation<double> _wordIn;
  late final Animation<double> _tagIn;
  late final Animation<double> _btnIn;
  late final Animation<double> _privacyIn;

  // Tagline
  late final Animation<double> _tagFade;
  int _tagIdx = 0;

  // Shimmer
  late final Animation<double> _shimmer;

  // Burst
  late final Animation<double> _burstGlow;

  // Background
  double _t = 0;
  List<FragmentParticle> _frags = [];
  List<String> _fragPool = [...kAllFragments];
  int _fragPoolIdx = 0;
  int _frameCount = 0;
  int _lastSpawn = -999;
  static const int _spawnEvery = 52;

  Offset _logoCenter = const Offset(187.5, 212.0);
  final GlobalKey _logoKey = GlobalKey();

  // State
  bool _isLoading = false;
  bool _btnPressed = false;
  String? _error;

  // ── Init ──────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _shufflePool();
    _setupControllers();
    _setupAnimations();
    _startEntrance();
    _cycleTags();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _entranceCtrl.dispose();
    _tagCtrl.dispose();
    _shimmerCtrl.dispose();
    _burstCtrl.dispose();
    super.dispose();
  }

  // ── Setup ─────────────────────────────────────────────────────────────────
  void _setupControllers() {
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 999),
    )
      ..addListener(_onTick)
      ..forward();

    _entranceCtrl = AnimationController(
      vsync: this,
      // Slowed slightly — the entrance should feel like surfacing, not loading
      duration: const Duration(milliseconds: 2100),
    );

    _tagCtrl = AnimationController(
      vsync: this,
      // Softer fade — 700ms feels more like a thought drifting in
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
      // Starts a hair later so wordmark trails the logo
      curve: const Interval(0.28, 0.62, curve: Curves.easeOutCubic),
    );
    _tagIn = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.42, 0.72, curve: Curves.easeOut),
    );
    _btnIn = CurvedAnimation(
      parent: _entranceCtrl,
      // Button arrives last with a gentle ease
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

  // ── Sequencing ────────────────────────────────────────────────────────────
  Future<void> _startEntrance() async {
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    _entranceCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 3200));
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
      // Longer hold — let each tagline breathe before cycling
      await Future.delayed(const Duration(milliseconds: 5200));
      if (!mounted) return;
      await _tagCtrl.forward();
      if (!mounted) return;
      setState(() => _tagIdx = (_tagIdx + 1) % _taglines.length);
      await _tagCtrl.reverse();
    }
  }

  // ── Ticker ────────────────────────────────────────────────────────────────
  void _onTick() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _logoKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        final pos = box.localToGlobal(Offset.zero);
        final center = pos + Offset(box.size.width / 2, box.size.height / 2);
        if (center != _logoCenter) _logoCenter = center;
      }
    });

    if (_frameCount - _lastSpawn >= _spawnEvery) {
      _spawnFragment();
      _lastSpawn = _frameCount;
      if (math.Random().nextDouble() < 0.3) {
        Future.delayed(
          Duration(milliseconds: 350 + math.Random().nextInt(300)),
          () {
            if (mounted) _spawnFragment();
          },
        );
      }
    }

    for (final f in _frags) f.update(_t);
    _frags = _frags.where((f) => !f.isDead).toList();

    _t += 0.003;
    _frameCount++;
  }

  // ── Fragment spawner ──────────────────────────────────────────────────────
  void _shufflePool() {
    _fragPool = [...kAllFragments];
    _fragPool.shuffle();
    _fragPoolIdx = 0;
  }

  String _nextText() {
    if (_fragPoolIdx >= _fragPool.length) _shufflePool();
    return _fragPool[_fragPoolIdx++];
  }

  void _spawnFragment() {
    _frags.add(FragmentParticle(
      text: _nextText(),
      logoCenter: _logoCenter,
      rng: math.Random(),
    ));
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
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
      // Success: root gate routes automatically
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background canvas ──────────────────────────────────────────
          AnimatedBuilder(
            animation: _ticker,
            builder: (_, __) => CustomPaint(
              painter: FragmentPainter(
                t: _t,
                particles: List.unmodifiable(_frags),
              ),
              size: size,
            ),
          ),

          // ── Grain ──────────────────────────────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.032,
                child: Image.network(
                  'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><filter id="n"><feTurbulence type="fractalNoise" baseFrequency="0.72" numOctaves="4" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/></filter><rect width="200" height="200" filter="url(%23n)"/></svg>',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),

          // ── Radial vignette ────────────────────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.25),
                    radius: 1.15,
                    colors: [
                      Colors.transparent,
                      Color(0x7A050810),
                      Color(0xEE050810),
                    ],
                    stops: [0.0, 0.52, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Amber bloom ────────────────────────────────────────────────
          Positioned(
            top: 48,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ticker,
                builder: (_, __) {
                  final p = (math.sin(_t * 0.6) + 1) / 2;
                  return Center(
                    child: Container(
                      width: 380,
                      height: 380,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _amber.withOpacity(0.07 + p * 0.028),
                            _amber.withOpacity(0.022),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.42, 0.72],
                        ),
                      ),
                    ),
                  );
                },
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
                  const SizedBox(height: 12),
                  _buildRule(),
                  const SizedBox(height: 20),
                  _buildTagPrimary(),
                  const SizedBox(height: 11),
                  _buildTagSecondary(),
                  const SizedBox(height: 48),
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

  // ── Logo ──────────────────────────────────────────────────────────────────
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
              // Outer halo — slow, deep pulse
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
                          color: _amber.withOpacity(0.07 + p * 0.08),
                          blurRadius: 80 + p * 35,
                          spreadRadius: 4 + p * 10,
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Inner orb glow — slightly offset, breathing on a different cycle
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
                            color: _amberSft.withOpacity(0.13 + p * 0.20),
                            blurRadius: 28 + p * 28,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Logo — breathes with the outer halo cycle
              AnimatedBuilder(
                animation: _ticker,
                builder: (_, child) {
                  final p = (math.sin(_t * 0.42) + 1) / 2;
                  return Transform.scale(
                    scale: 1.0 + p * 0.020,
                    child: child,
                  );
                },
                child: Image.asset(
                  'assets/images/sol_logo.png',
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Wordmark ──────────────────────────────────────────────────────────────
  Widget _buildWordmark() {
    return FadeTransition(
      opacity: _wordIn,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(_wordIn),
        child: Text(
          'Sol',
          style: GoogleFonts.cormorantGaramond(
            fontWeight: FontWeight.w300,
            fontSize: 68,
            color: _cream,
            // Pulled in from 8 — more intimate, less display-logotype
            letterSpacing: 6,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  // ── Rule ──────────────────────────────────────────────────────────────────
  Widget _buildRule() {
    return FadeTransition(
      opacity: _wordIn,
      child: Container(
        width: 36,
        height: 0.5,
        // Warmer rule — amber tint instead of cool sand
        color: _amber.withOpacity(0.18),
      ),
    );
  }

  // ── Primary tagline ───────────────────────────────────────────────────────
  Widget _buildTagPrimary() {
    return FadeTransition(
      opacity: _tagIn,
      child: Text(
        'You are the U.',
        style: GoogleFonts.cormorantGaramond(
          fontWeight: FontWeight.w300,
          // Bumped slightly — this is the positioning statement, deserves presence
          fontSize: 18.5,
          color: _sand,
          letterSpacing: 3.6,
        ),
      ),
    );
  }

  // ── Secondary tagline (cycling) ────────────────────────────────────────────
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
                // Bumped from 10 → 11.5 — 10px is too small to read on device
                fontSize: 11.5,
                color: _sand.withOpacity(0.38),
                letterSpacing: 2.6,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Button ────────────────────────────────────────────────────────────────
  Widget _buildButton() {
    return FadeTransition(
      opacity: _btnIn,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(_btnIn),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
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
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      // 14px radius — softer than 16, less SaaS-y
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _cream.withOpacity(_isLoading ? 0.05 : 0.10),
                        width: 0.6,
                      ),
                      // Very slightly lifted from pure black — gives depth
                      color: const Color(0x8C0D1420),
                      boxShadow: [
                        // Burst glow on tap
                        BoxShadow(
                          color: _amber.withOpacity(_burstGlow.value * 0.26),
                          blurRadius: 36,
                          spreadRadius: 0,
                        ),
                        // Ambient warmth — always present, subtle
                        BoxShadow(
                          color: _amber.withOpacity(0.045),
                          blurRadius: 20,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Shimmer sweep
                        if (!_isLoading)
                          Positioned.fill(
                            child: FractionalTranslation(
                              translation:
                                  Offset(-1.6 + _shimmer.value * 3.2, 0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      _cream.withOpacity(0.03),
                                      _cream.withOpacity(0.07),
                                      _cream.withOpacity(0.03),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                                    transform: const GradientRotation(0.4),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Content
                        _isLoading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    // Warmer amber for loading state
                                    _amberSft.withOpacity(0.65),
                                  ),
                                ),
                              )
                            : Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _googleLogo(),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Continue with Google',
                                      style: GoogleFonts.jost(
                                        fontWeight: FontWeight.w300,
                                        fontSize: 13.5,
                                        color: _cream.withOpacity(0.72),
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                      ],
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

  // ── Error ─────────────────────────────────────────────────────────────────
  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        _error ?? '',
        style: GoogleFonts.jost(
          fontSize: 11.5,
          fontWeight: FontWeight.w300,
          color: _dustRose.withOpacity(0.75),
          letterSpacing: 0.3,
          height: 1.6,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Privacy ───────────────────────────────────────────────────────────────
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
            // Fixed: was Color(0xFF3D3428) at 0.9 which rendered near-invisible
            // Now: warm sand at low opacity — readable but receding
            color: _sand.withOpacity(0.30),
            letterSpacing: 0.35,
            height: 1.8,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── Google logo ────────────────────────────────────────────────────────────
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
