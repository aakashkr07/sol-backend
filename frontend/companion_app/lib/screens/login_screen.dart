// =============================================================================
// screens/login_screen.dart — Sol Login Screen (Premium Edition)
// =============================================================================
//
// DESIGN PHILOSOPHY:
//   Ultra-clean. Premium. Cinematic. Emotionally resonant.
//   The logo is the hero — everything else supports it.
//   Tagline: "You are the U" — poetic, intimate, meaningful.
//   Google button integrates seamlessly, not bolted on.
//   Animations are subtle, premium, purposeful — not for show.
//
// COLORS (from the logo):
//   Navy #0A0E1A — calm, intimate, nocturnal
//   Amber #F5A623 — warmth, glow, presence
//   Stone #E8DCC8 — human, tactile, real
//
// ANIMATIONS:
//   Logo fades + scales in (feels like it's materializing)
//   Text follows with elegant stagger
//   Button emerges last with subtle bounce
//   Glow pulses throughout (alive, breathing)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import 'chat_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ── Color palette ──────────────────────────────────────────────────────
  static const Color _navy = Color(0xFF0A0E1A);
  static const Color _amber = Color(0xFFF5A623);
  static const Color _stone = Color(0xFFE8DCC8);
  static const Color _textMuted = Color(0xFF888888);

  // ── Animation controllers ──────────────────────────────────────────────
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final AnimationController _buttonController;
  late final AnimationController _glowController;

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoTranslateY;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _buttonFade;
  late final Animation<double> _buttonScale;
  late final Animation<double> _glowPulse;

  // ── State ──────────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startAnimations();
  }

  void _setupAnimations() {
    // Logo: fade in + scale + float up
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );
    _logoTranslateY = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );

    // Text: fade in + slide from bottom
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textFade = CurvedAnimation(parent: _textController, curve: Curves.easeOut);
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _textController, curve: Curves.easeOutCubic));

    // Button: fade in + scale with bounce
    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _buttonFade =
        CurvedAnimation(parent: _buttonController, curve: Curves.easeOut);
    _buttonScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeOutBack),
    );

    // Ambient glow: continuous subtle pulse
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _glowPulse = Tween<double>(begin: 0.2, end: 0.35).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _glowController.repeat(reverse: true);
  }

  Future<void> _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _textController.forward();

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _buttonController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _buttonController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  // ── Sign in ────────────────────────────────────────────────────────────

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    HapticFeedback.lightImpact();

    try {
      final user = await AuthService.signInWithGoogle();

      if (!mounted) return;

      if (user != null) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, animation, __) => const ChatScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOut,
                ),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 700),
          ),
        );
      } else {
        setState(() => _isLoading = false);
      }
    } on AuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _navy,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _navy,
      body: Stack(
        children: [
          // ── Animated background glow ──────────────────────────────────
          _buildBackgroundGlow(),

          // ── Content ────────────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              child: SizedBox(
                height: size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(height: 20),

                    // Logo section
                    Expanded(
                      flex: 2,
                      child: _buildLogoSection(size),
                    ),

                    // Text + button section
                    Expanded(
                      flex: 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildTextBlock(),
                          const SizedBox(height: 60),
                          _buildSignInButton(),
                          const SizedBox(height: 16),
                          _buildErrorText(),
                          _buildPrivacyNote(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Background glow ────────────────────────────────────────────────────

  Widget _buildBackgroundGlow() {
    return AnimatedBuilder(
      animation: _glowPulse,
      builder: (_, __) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.2),
              radius: 1.0,
              colors: [
                _amber.withOpacity(_glowPulse.value * 0.15),
                _navy.withOpacity(0.0),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Logo section ───────────────────────────────────────────────────────

  Widget _buildLogoSection(Size size) {
    return FadeTransition(
      opacity: _logoFade,
      child: Transform.translate(
        offset: Offset(0, _logoTranslateY.value),
        child: ScaleTransition(
          scale: _logoScale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow halo
              AnimatedBuilder(
                animation: _glowPulse,
                builder: (_, __) => Container(
                  width: size.width * 0.5,
                  height: size.width * 0.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _amber.withOpacity(_glowPulse.value * 0.8),
                        blurRadius: 100,
                        spreadRadius: 30,
                      ),
                    ],
                  ),
                ),
              ),

              // Logo image — displays the actual uploaded PNG
              Image.asset(
                'sol_mvp/frontend/companion_app/assets/images/sol_logo.png',
                width: size.width * 0.35,
                height: size.width * 0.35,
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Text block: "Sol" + "You are the U" ───────────────────────────────

  Widget _buildTextBlock() {
    return FadeTransition(
      opacity: _textFade,
      child: SlideTransition(
        position: _textSlide,
        child: Column(
          children: [
            // "Sol"
            const Text(
              'Sol',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w200,
                color: _stone,
                letterSpacing: 12,
                height: 1.0,
              ),
            ),

            const SizedBox(height: 16),

            // "You are the U"
            Text(
              'you are the U',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w300,
                color: _textMuted,
                letterSpacing: 2.8,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Google Sign-In button ──────────────────────────────────────────────

  Widget _buildSignInButton() {
    return FadeTransition(
      opacity: _buttonFade,
      child: ScaleTransition(
        scale: _buttonScale,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: GestureDetector(
            onTap: _isLoading ? null : _handleGoogleSignIn,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _stone.withOpacity(_isLoading ? 0.15 : 0.25),
                  width: 1.2,
                ),
                color: Colors.white.withOpacity(
                  _isLoading ? 0.03 : 0.06,
                ),
              ),
              child: _isLoading
                  ? Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _amber.withOpacity(0.6),
                          ),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Real Google "G" logo
                        _buildGoogleGLogo(),
                        const SizedBox(width: 10),
                        Text(
                          'Continue with Google',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: _stone.withOpacity(0.85),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Proper Google "G" Logo ─────────────────────────────────────────────

  Widget _buildGoogleGLogo() {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(
        painter: _GoogleGPainter(),
      ),
    );
  }

  // ── Error text ─────────────────────────────────────────────────────────

  Widget _buildErrorText() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _errorMessage != null ? 1.0 : 0.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          _errorMessage ?? '',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.redAccent,
            letterSpacing: 0.2,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── Privacy note ───────────────────────────────────────────────────────

  Widget _buildPrivacyNote() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 32, right: 32),
      child: Text(
        'your conversations are private and end-to-end encrypted',
        style: TextStyle(
          fontSize: 10,
          color: _textMuted.withOpacity(0.4),
          letterSpacing: 0.4,
          height: 1.6,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// =============================================================================
// Google "G" Logo — Proper SVG-like rendering
// =============================================================================

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final double cx = s / 2;
    final double cy = s / 2;

    // Blue (top-right)
    final blue = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round;

    // Red (top-left to bottom-left)
    final red = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round;

    // Yellow (bottom-left)
    final yellow = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round;

    // Green (bottom-right)
    final green = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round;

    final r = s * 0.35;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Blue arc (top-right quadrant)
    canvas.drawArc(rect, -0.3, 1.57, false, blue);

    // Red arc (top-left to bottom-left)
    canvas.drawArc(rect, 1.27, 1.57, false, red);

    // Yellow arc (bottom-left)
    canvas.drawArc(rect, 2.84, 1.57, false, yellow);

    // Green arc (bottom-right)
    canvas.drawArc(rect, -1.87, 1.57, false, green);

    // Horizontal bar (the "G" in the "G")
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(cx - r * 0.3, cy - s * 0.06, r * 0.4, s * 0.12),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
