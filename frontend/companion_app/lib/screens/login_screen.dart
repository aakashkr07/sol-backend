// =============================================================================
// screens/login_screen.dart — Sol Login Screen
// =============================================================================
//
// DESIGN LANGUAGE:
//   Deep navy background (#0D1117) — same as the logo's sky.
//   Logo centered, glowing amber ambient light radiating from behind it.
//   App name "Sol" in thin, wide-tracked serif below logo.
//   Tagline in small, muted, spaced caps.
//   Google button: frosted glass feel, subtle border, no heavy fill.
//   Everything fades in sequentially — logo first, then text, then button.
//
// ANIMATIONS:
//   1. Logo: fade in + scale from 0.85 → 1.0 (800ms, easeOut)
//   2. Text block: fade in, 300ms delay after logo
//   3. Button: fade in, 500ms delay after logo
//   These staggered reveals feel premium, not snappy.
//
// WHAT HAPPENS ON TAP:
//   1. Button shows loading spinner
//   2. Google sheet opens
//   3. On success → Navigator replaces this screen with ChatScreen
//   4. On cancel → button resets silently
//   5. On error → inline error text below button (no dialogs)
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
  // ── Animation controllers ──────────────────────────────────────────────
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final AnimationController _buttonController;
  late final AnimationController _glowController;

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _textFade;
  late final Animation<double> _buttonFade;
  late final Animation<double> _glowPulse;

  // ── State ──────────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _errorMessage;

  // ── Sol color palette (derived from the logo) ──────────────────────────
  static const Color _navy = Color(0xFF0A0E1A); // Background
  static const Color _navyLight = Color(0xFF0D1421); // Slightly lighter
  static const Color _amber = Color(0xFFF5A623); // Logo glow / accent
  static const Color _amberGlow = Color(0xFFFF9500); // Warmer glow
  static const Color _stone = Color(0xFFE8DCC8); // Logo crescent color
  static const Color _textPrimary = Color(0xFFEEE8DF); // Warm white
  static const Color _textMuted = Color(0xFF6B7280); // Muted grey

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startAnimations();
  }

  void _setupAnimations() {
    // Logo entrance
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );

    // Text entrance
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _textFade = CurvedAnimation(parent: _textController, curve: Curves.easeOut);

    // Button entrance
    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _buttonFade =
        CurvedAnimation(parent: _buttonController, curve: Curves.easeOut);

    // Ambient glow pulse (continuous, subtle)
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _glowPulse = Tween<double>(begin: 0.15, end: 0.28).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _glowController.repeat(reverse: true);
  }

  Future<void> _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _textController.forward();

    await Future.delayed(const Duration(milliseconds: 300));
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

  // ── Sign in logic ──────────────────────────────────────────────────────

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
        // Success — replace login screen with chat
        // pushReplacement means back button won't return to login
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
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      } else {
        // User cancelled — reset silently
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

  // ── Build ──────────────────────────────────────────────────────────────

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
          // ── Ambient background gradient ──────────────────────────────
          _buildBackground(size),

          // ── Main content ─────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo
                _buildLogo(size),

                const SizedBox(height: 40),

                // App name + tagline
                _buildTextBlock(),

                const Spacer(flex: 3),

                // Google sign-in button
                _buildSignInButton(),

                const SizedBox(height: 16),

                // Error message
                _buildErrorText(),

                // Privacy note
                _buildPrivacyNote(),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Background ─────────────────────────────────────────────────────────

  Widget _buildBackground(Size size) {
    return AnimatedBuilder(
      animation: _glowPulse,
      builder: (_, __) {
        return Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.15),
              radius: 0.85,
              colors: [
                _amber.withOpacity(_glowPulse.value),
                _navy.withOpacity(0.0),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Logo ───────────────────────────────────────────────────────────────

  Widget _buildLogo(Size size) {
    return FadeTransition(
      opacity: _logoFade,
      child: ScaleTransition(
        scale: _logoScale,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient glow behind logo
            AnimatedBuilder(
              animation: _glowPulse,
              builder: (_, __) => Container(
                width: size.width * 0.55,
                height: size.width * 0.55,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _amber.withOpacity(_glowPulse.value * 0.7),
                      blurRadius: 80,
                      spreadRadius: 20,
                    ),
                    BoxShadow(
                      color: _amberGlow.withOpacity(_glowPulse.value * 0.4),
                      blurRadius: 120,
                      spreadRadius: 40,
                    ),
                  ],
                ),
              ),
            ),

            // The actual logo
            // =============================================================
            // DROP YOUR LOGO HERE:
            // Place sol_logo.png in: assets/images/sol_logo.png
            // =============================================================
            Image.asset(
              'assets/images/sol_logo.png',
              width: size.width * 0.42,
              height: size.width * 0.42,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _buildLogoPlaceholder(size),
            ),
          ],
        ),
      ),
    );
  }

  // Placeholder shown if the image isn't placed yet
  Widget _buildLogoPlaceholder(Size size) {
    return Container(
      width: size.width * 0.42,
      height: size.width * 0.42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            _amber.withOpacity(0.3),
            _navy.withOpacity(0.1),
          ],
        ),
        border: Border.all(
          color: _stone.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          'Sol',
          style: TextStyle(
            color: _stone.withOpacity(0.6),
            fontSize: 32,
            fontWeight: FontWeight.w200,
            letterSpacing: 8,
          ),
        ),
      ),
    );
  }

  // ── Text block ─────────────────────────────────────────────────────────

  Widget _buildTextBlock() {
    return FadeTransition(
      opacity: _textFade,
      child: Column(
        children: [
          // App name
          Text(
            'Sol',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w200,
              color: _textPrimary,
              letterSpacing: 14,
              height: 1.0,
            ),
          ),

          const SizedBox(height: 12),

          // Tagline
          Text(
            'someone who knows you',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: _textMuted,
              letterSpacing: 3.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Google sign-in button ──────────────────────────────────────────────

  Widget _buildSignInButton() {
    return FadeTransition(
      opacity: _buttonFade,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: GestureDetector(
          onTap: _isLoading ? null : _handleGoogleSignIn,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(_isLoading ? 0.04 : 0.07),
              border: Border.all(
                color: Colors.white.withOpacity(_isLoading ? 0.08 : 0.14),
                width: 1,
              ),
            ),
            child: _isLoading
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _amber.withOpacity(0.8),
                        ),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Google "G" logo drawn manually (no asset needed)
                      _GoogleGLogo(size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: _textPrimary.withOpacity(0.85),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ── Error text ─────────────────────────────────────────────────────────

  Widget _buildErrorText() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _errorMessage != null ? 1.0 : 0.0,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          _errorMessage ?? '',
          style: TextStyle(
            fontSize: 12,
            color: Colors.redAccent.withOpacity(0.8),
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ── Privacy note ───────────────────────────────────────────────────────

  Widget _buildPrivacyNote() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 40, right: 40),
      child: Text(
        'your conversations are private and encrypted',
        style: TextStyle(
          fontSize: 11,
          color: _textMuted.withOpacity(0.5),
          letterSpacing: 0.5,
          height: 1.6,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// =============================================================================
// Google "G" Logo Widget — drawn with CustomPainter (no SVG asset needed)
// =============================================================================

class _GoogleGLogo extends StatelessWidget {
  final double size;
  const _GoogleGLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleGPainter(),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final double cx = s / 2;
    final double cy = s / 2;
    final double r = s / 2;

    // Blue arc (top-right)
    final paintBlue = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.175
      ..strokeCap = StrokeCap.butt;

    // Red arc (top-left)
    final paintRed = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.175
      ..strokeCap = StrokeCap.butt;

    // Yellow arc (bottom-left)
    final paintYellow = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.175
      ..strokeCap = StrokeCap.butt;

    // Green arc (bottom-right)
    final paintGreen = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.175
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.78);

    // Draw 4 colored arcs (rough G shape)
    canvas.drawArc(rect, -0.52, 1.57, false, paintBlue); // top-right blue
    canvas.drawArc(rect, 1.05, 1.57, false, paintYellow); // bottom-left yellow
    canvas.drawArc(rect, 2.62, 1.57, false, paintGreen); // bottom-right green
    canvas.drawArc(rect, -2.09, 1.57, false, paintRed); // top-left red

    // Horizontal bar of the G
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(cx, cy - s * 0.088, r * 0.78, s * 0.175),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
