import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

class OnboardingScreen extends StatefulWidget {
  final Future<void> Function(SessionStartResponse session) onComplete;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const Color _bg = Color(0xFF060A12);
  static const Color _surface = Color(0xFF111827);
  static const Color _surfaceSoft = Color(0xFF171F31);
  static const Color _amber = Color(0xFFF5A623);
  static const Color _cream = Color(0xFFEEE8DF);
  static const Color _muted = Color(0xFFB7A892);

  late final AnimationController _fadeCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _cardIn;

  MyCompanionsResponse? _roster;
  CompanionSummary? _matchedCompanion;
  bool _isLoading = true;
  bool _isStarting = false;
  String? _error;
  int _lineIndex = 0;
  Timer? _lineTimer;

  List<String> get _encounterLines {
    final companion = _matchedCompanion;
    final firstName = _firstName();
    return [
      firstName == null ? 'you have a message waiting' : '$firstName, you have a message waiting',
      companion == null
          ? 'the conversation is there. it just has to come into focus.'
          : 'it is from ${companion.name}',
      companion?.summary.isNotEmpty == true
          ? companion!.summary
          : 'it should feel like opening a real thread, not setting up a product.',
    ];
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _fadeIn = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOutCubic,
    );
    _cardIn = CurvedAnimation(
      parent: _fadeCtrl,
      curve: const Interval(0.22, 1.0, curve: Curves.easeOutCubic),
    );
    _loadEncounter();
  }

  @override
  void dispose() {
    _lineTimer?.cancel();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEncounter() async {
    try {
      final roster = await ApiService.getMyCompanions();
      final matched = roster?.primaryCompanion ??
          (roster?.pairs.isNotEmpty == true
              ? roster!.pairs.first
              : roster?.availableCompanions.isNotEmpty == true
                  ? roster!.availableCompanions.first
                  : null);

      if (matched == null || matched.id.trim().isEmpty) {
        throw const ChatException(
          'No matched companion could be loaded. Make sure the backend is running and try again.',
          -1,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _roster = roster;
        _matchedCompanion = matched;
        _isLoading = false;
      });

      _fadeCtrl.forward(from: 0);
      _startEncounterLines();
    } on ChatException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'The conversation did not come through. Try again.';
        _isLoading = false;
      });
    }
  }

  void _startEncounterLines() {
    _lineTimer?.cancel();
    _lineIndex = 0;
    _lineTimer = Timer.periodic(const Duration(milliseconds: 1600), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lineIndex >= _encounterLines.length - 1) {
        timer.cancel();
        return;
      }
      setState(() => _lineIndex += 1);
    });
  }

  String? _firstName() {
    final name = _roster?.userName ?? AuthService.currentUserName;
    if (name == null || name.trim().isEmpty) {
      return null;
    }
    return name.trim().split(' ').first;
  }

  String _ctaLabel() {
    return 'Open the chat';
  }

  Future<void> _beginEncounter() async {
    if (_isStarting) {
      return;
    }

    final companionId = _matchedCompanion?.id;
    if (companionId == null || companionId.isEmpty) {
      setState(() => _error = 'No matched conversation could be opened yet.');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _isStarting = true;
      _error = null;
    });

    try {
      final session = await ApiService.startSession(characterId: companionId);
      if (session == null) {
        throw const ChatException('could not start the first thread.', -1);
      }
      await widget.onComplete(session);
    } on ChatException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isStarting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isStarting = false;
        _error = 'something interrupted the first message. try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackdrop()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: _isLoading ? _buildLoading() : _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdrop() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final wave = 0.35 + (_pulseCtrl.value * 0.65);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.72),
              radius: 1.18,
              colors: [
                _amber.withValues(alpha: 0.12 * wave),
                const Color(0xFF172033).withValues(alpha: 0.42),
                _bg,
              ],
              stops: const [0.0, 0.42, 1.0],
            ),
          ),
          child: child,
        );
      },
      child: IgnorePointer(
        child: CustomPaint(
          painter: _EncounterPainter(),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _amber.withValues(alpha: 0.08),
              boxShadow: [
                BoxShadow(
                  color: _amber.withValues(alpha: 0.14),
                  blurRadius: 28,
                ),
              ],
            ),
            child: const Center(
              child: Image(
                image: AssetImage('assets/images/sol_logo.png'),
                width: 46,
                height: 46,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'finding the conversation that is already waiting...',
            textAlign: TextAlign.center,
            style: GoogleFonts.jost(
              color: _muted.withValues(alpha: 0.74),
              fontSize: 13,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final lines = _encounterLines;
    final companion = _matchedCompanion;

    return FadeTransition(
      opacity: _fadeIn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'A message is waiting',
            style: GoogleFonts.jost(
              color: _muted.withValues(alpha: 0.65),
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(lines.length, (index) {
            final visible = index <= _lineIndex;
            return AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, 0.08),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    lines[index],
                    style: GoogleFonts.cormorantGaramond(
                      color: index == 0 ? _cream : _cream.withValues(alpha: 0.88),
                      fontSize: index == 0 ? 34 : 24,
                      height: 1.06,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          if (companion != null)
            ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(_cardIn),
              child: FadeTransition(
                opacity: _cardIn,
                child: _buildCompanionCard(companion),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF3A1717).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE08B8B).withValues(alpha: 0.22),
                ),
              ),
              child: Text(
                _error!,
                style: GoogleFonts.jost(
                  color: const Color(0xFFE08B8B),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _isStarting
                    ? null
                    : () {
                        setState(() {
                          _isLoading = true;
                          _error = null;
                          _matchedCompanion = null;
                          _roster = null;
                        });
                        _loadEncounter();
                      },
                child: Text(
                  'Try again',
                  style: GoogleFonts.jost(
                    color: _amber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          FadeTransition(
            opacity: _cardIn,
            child: _buildEncounterButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanionCard(CompanionSummary companion) {
    final isNew = companion.totalSessions == 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _surface.withValues(alpha: 0.94),
            _surfaceSoft.withValues(alpha: 0.94),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _amber.withValues(alpha: 0.72),
                      const Color(0xFF3D2A00).withValues(alpha: 0.44),
                    ],
                  ),
                ),
                child: const Center(
                  child: Image(
                    image: AssetImage('assets/images/sol_logo.png'),
                    width: 22,
                    height: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companion.name,
                      style: GoogleFonts.cormorantGaramond(
                        color: _cream,
                        fontSize: 29,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      isNew
                          ? 'first conversation'
                          : '${companion.totalSessions} sessions already between you',
                      style: GoogleFonts.jost(
                        color: _muted.withValues(alpha: 0.72),
                        fontSize: 11.5,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            companion.summary.isEmpty
                ? 'this should feel like opening a real thread, not configuring anything'
                : companion.summary,
            style: GoogleFonts.jost(
              color: _cream.withValues(alpha: 0.76),
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEncounterButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _isStarting ? null : _beginEncounter,
        style: FilledButton.styleFrom(
          backgroundColor: _amber,
          foregroundColor: const Color(0xFF0B0E16),
          disabledBackgroundColor: _amber.withValues(alpha: 0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _isStarting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0B0E16)),
                ),
              )
            : Text(
                _ctaLabel(),
                style: GoogleFonts.jost(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}

class _EncounterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < 48; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final radius = 0.8 + (rng.nextDouble() * 1.6);
      dotPaint.color = Colors.white.withValues(alpha: 0.02 + (rng.nextDouble() * 0.05));
      canvas.drawCircle(Offset(dx, dy), radius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
