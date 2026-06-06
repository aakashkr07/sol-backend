import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/onboarding_service.dart';
import '../widgets/atmosphere_background.dart';

// Sol Design System Constants
const Color _bgDeep = Color(0xFF080A0E);
const Color _surface = Color(0xFF10131A);
const Color _blue = Color(0xFF7DA2FF);
const Color _blueSoft = Color(0xFF8BA8FF);
const Color _violet = Color(0xFFA78BFA);
const Color _amber = Color(0xFFF2B8A0);
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);
const Color _dusty = Color(0xFF5A5568);
const Color _ink = Color(0xFF060810);

/// Direction the card transition travels.
enum _CardDirection { forward, backward }

class OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onComplete;
  final VoidCallback? onBack; // Called when user taps back on the first card

  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.onBack,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  String _preferredName = '';
  String _connectionStyle = '';
  String _presenceFrequency = '';
  String _depthPreference = '';
  String _behavioralGuardrail = '';

  String? _error;
  bool _apiSuccess = false;
  bool _cycleFinished = false;

  // --- Card transition state ---
  late final AnimationController _slideCtrl;
  late Animation<Offset> _slideIn;
  late Animation<Offset> _slideOut;
  late Animation<double> _fadeIn;
  late Animation<double> _fadeOut;

  Widget? _outgoingWidget;
  Widget? _incomingWidget;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _slideCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isAnimating = false;
          _outgoingWidget = null;
        });
        _slideCtrl.reset();
      }
    });

    _setAnimations(_CardDirection.forward);
  }

  void _setAnimations(_CardDirection dir) {
    final inBegin = dir == _CardDirection.forward
        ? const Offset(0.06, 0)
        : const Offset(-0.06, 0);
    const inEnd = Offset.zero;
    final outEnd = dir == _CardDirection.forward
        ? const Offset(-0.06, 0)
        : const Offset(0.06, 0);
    const outBegin = Offset.zero;

    _slideIn = Tween<Offset>(begin: inBegin, end: inEnd).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic),
    );
    _slideOut = Tween<Offset>(begin: outBegin, end: outEnd).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeInCubic),
    );
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _slideCtrl,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _slideCtrl,
          curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );
  }

  void _transitionToStep(int newStep,
      {_CardDirection dir = _CardDirection.forward}) {
    if (_isAnimating) return;

    _setAnimations(dir);

    setState(() {
      _outgoingWidget = _buildStepWidget(_currentStep);
      _currentStep = newStep;
      _incomingWidget = _buildStepWidget(newStep);
      _isAnimating = true;
    });

    _slideCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  // ─── API ────────────────────────────────────────────────────────────────────

  Future<void> _submitOnboarding() async {
    _transitionToStep(5);

    setState(() {
      _error = null;
      _apiSuccess = false;
      _cycleFinished = false;
    });

    try {
      final response = await ApiService.completeOnboarding(
        preferredName: _preferredName,
        connectionStyle: _connectionStyle,
        presenceFrequency: _presenceFrequency,
        depthPreference: _depthPreference,
        behavioralGuardrail: _behavioralGuardrail,
      );

      if (response == null) {
        throw const ChatException('Failed to match you. Try again.', -1);
      }

      if (!mounted) return;
      setState(() => _apiSuccess = true);

      if (_apiSuccess && _cycleFinished) _completeAndNavigate();
    } on ChatException catch (e) {
      setState(() {
        _error = e.message;
      });
      _transitionToStep(4, dir: _CardDirection.backward);
    } catch (_) {
      setState(() {
        _error = 'The matching system encountered an error. Try again.';
      });
      _transitionToStep(4, dir: _CardDirection.backward);
    }
  }

  Future<void> _completeAndNavigate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await OnboardingService.markComplete(uid);
    widget.onComplete();
  }

  void _onOptionSelected(int step, String backendValue) {
    HapticFeedback.lightImpact();

    if (step == 1) _connectionStyle = backendValue;
    if (step == 2) _presenceFrequency = backendValue;
    if (step == 3) _depthPreference = backendValue;
    if (step == 4) _behavioralGuardrail = backendValue;

    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (step < 4) {
        _transitionToStep(step + 1);
      } else {
        _submitOnboarding();
      }
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _bgDeep,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: _bgDeep,
      body: AtmosphereBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                child: _buildBackButton(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildAnimatedCard(),
                      if (_error != null && _currentStep < 5) ...[
                        const SizedBox(height: 20),
                        _buildErrorPanel(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCard() {
    if (!_isAnimating) {
      return _GlassCard(child: _buildStepWidget(_currentStep));
    }

    return Stack(
      children: [
        // Outgoing card
        if (_outgoingWidget != null)
          AnimatedBuilder(
            animation: _slideCtrl,
            builder: (_, __) => FadeTransition(
              opacity: _fadeOut,
              child: SlideTransition(
                position: _slideOut,
                child: _GlassCard(child: _outgoingWidget!),
              ),
            ),
          ),
        // Incoming card
        if (_incomingWidget != null)
          AnimatedBuilder(
            animation: _slideCtrl,
            builder: (_, __) => FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideIn,
                child: _GlassCard(child: _incomingWidget!),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBackButton() {
    if (_currentStep >= 5) return const SizedBox(height: 40);

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          if (_currentStep == 0) {
            widget.onBack?.call();
          } else {
            _transitionToStep(_currentStep - 1, dir: _CardDirection.backward);
          }
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.70),
            border:
                Border.all(color: _cream.withValues(alpha: 0.08), width: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.chevron_left, color: _cream, size: 20),
        ),
      ),
    );
  }

  // ─── Step widgets ────────────────────────────────────────────────────────────

  Widget _buildStepWidget(int step) {
    switch (step) {
      case 0:
        return _NameInputCard(
          key: const ValueKey('step-name'),
          onSubmitted: (name) {
            HapticFeedback.lightImpact();
            _preferredName = name;
            _transitionToStep(1);
          },
          onBack: widget.onBack,
        );
      case 1:
        return _QuestionCard(
          key: const ValueKey('step-q2'),
          header: 'When you meet someone new...',
          question: 'What usually makes you want to keep talking to them?',
          options: const [
            _QuestionOption('They take their time.', 'takes_their_time'),
            _QuestionOption("They're easy to talk to.", 'easy_to_talk_to'),
            _QuestionOption(
                "They say exactly what's on their mind.", 'says_whats_on_mind'),
            _QuestionOption('They make things fun.', 'makes_things_fun'),
            _QuestionOption('They make conversations feel meaningful.',
                'meaningful_conversations'),
          ],
          selectedValue: _connectionStyle,
          onSelected: (val) => _onOptionSelected(1, val),
        );
      case 2:
        return _QuestionCard(
          key: const ValueKey('step-q3'),
          header: 'The people you stay close to...',
          question: 'How do they usually show up in your life?',
          options: const [
            _QuestionOption('Every now and then.', 'every_now_and_then'),
            _QuestionOption('When it matters.', 'when_it_matters'),
            _QuestionOption('Fairly often.', 'fairly_often'),
            _QuestionOption("They're always around.", 'always_around'),
          ],
          selectedValue: _presenceFrequency,
          onSelected: (val) => _onOptionSelected(2, val),
        );
      case 3:
        return _QuestionCard(
          key: const ValueKey('step-q4'),
          header: 'When conversations become real...',
          question: 'What feels right to you?',
          options: const [
            _QuestionOption('Let it happen naturally.', 'let_it_happen'),
            _QuestionOption(
                'A little honesty goes a long way.', 'little_honesty'),
            _QuestionOption(
                "I don't mind getting personal.", 'dont_mind_personal'),
            _QuestionOption(
                "I'd rather skip the small talk.", 'skip_small_talk'),
          ],
          selectedValue: _depthPreference,
          onSelected: (val) => _onOptionSelected(3, val),
        );
      case 4:
        return _QuestionCard(
          key: const ValueKey('step-q5'),
          header: 'One thing that usually pushes you away?',
          question: 'What acts as a behavior guardrail?',
          options: const [
            _QuestionOption('Trying too hard.', 'trying_too_hard'),
            _QuestionOption('Being distant.', 'being_distant'),
            _QuestionOption('Talking too much.', 'talking_too_much'),
            _QuestionOption(
                'Reading into everything.', 'reading_into_everything'),
            _QuestionOption('Moving too fast.', 'moving_too_fast'),
          ],
          selectedValue: _behavioralGuardrail,
          onSelected: (val) => _onOptionSelected(4, val),
        );
      case 5:
        return _LoadingCard(
          key: const ValueKey('step-loading'),
          onFinished: () {
            if (mounted) {
              setState(() => _cycleFinished = true);
              if (_apiSuccess && _cycleFinished) _completeAndNavigate();
            }
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildErrorPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF331515).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFE08B8B).withValues(alpha: 0.22)),
      ),
      child: Text(
        _error!,
        style: GoogleFonts.jost(
            color: const Color(0xFFE08B8B), fontSize: 13, height: 1.45),
      ),
    );
  }
}

// ─── Glassmorphic Card Shell ──────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            // Layered glass look: a very subtle white tint over near-transparent dark
            color: const Color(0xFF10131A).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _cream.withValues(alpha: 0.07),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: _blue.withValues(alpha: 0.04),
                blurRadius: 48,
                spreadRadius: -4,
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: child,
        ),
      ),
    );
  }
}

// ─── Step 0 – Name Input ──────────────────────────────────────────────────────

class _NameInputCard extends StatefulWidget {
  final Function(String) onSubmitted;
  final VoidCallback? onBack;

  const _NameInputCard({
    super.key,
    required this.onSubmitted,
    this.onBack,
  });

  @override
  State<_NameInputCard> createState() => _NameInputCardState();
}

class _NameInputCardState extends State<_NameInputCard> {
  final _controller = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _canSubmit = _controller.text.trim().isNotEmpty);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header row with back-to-login button
        Text(
          'Before we start...',
          style: GoogleFonts.plusJakartaSans(
            color: _cream.withValues(alpha: 0.92),
            fontSize: 25,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'What should we call you?',
          style: GoogleFonts.plusJakartaSans(
            color: _sand.withValues(alpha: 0.72),
            fontSize: 16,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.60),
            border:
                Border.all(color: _cream.withValues(alpha: 0.08), width: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            controller: _controller,
            cursorColor: _blueSoft,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.jost(color: _cream, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Enter your preferred name',
              hintStyle: GoogleFonts.jost(color: _dusty, fontSize: 16),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: InputBorder.none,
            ),
            onSubmitted: (_) {
              if (_canSubmit) widget.onSubmitted(_controller.text.trim());
            },
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: AnimatedScale(
            scale: _canSubmit ? 1.0 : 0.98,
            duration: const Duration(milliseconds: 150),
            child: Opacity(
              opacity: _canSubmit ? 1.0 : 0.5,
              child: ElevatedButton(
                onPressed: _canSubmit
                    ? () => widget.onSubmitted(_controller.text.trim())
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: _ink,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  'Continue',
                  style: GoogleFonts.jost(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Question Card ────────────────────────────────────────────────────────────

class _QuestionOption {
  final String label;
  final String backendValue;
  const _QuestionOption(this.label, this.backendValue);
}

class _QuestionCard extends StatelessWidget {
  final String header;
  final String question;
  final List<_QuestionOption> options;
  final String selectedValue;
  final Function(String) onSelected;

  const _QuestionCard({
    super.key,
    required this.header,
    required this.question,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          header,
          style: GoogleFonts.plusJakartaSans(
            color: _cream.withValues(alpha: 0.92),
            fontSize: 24,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          question,
          style: GoogleFonts.plusJakartaSans(
            color: _sand.withValues(alpha: 0.72),
            fontSize: 15,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 28),
        ...options.map((opt) {
          final isSelected = selectedValue == opt.backendValue;
          return _OptionTile(
            text: opt.label,
            selected: isSelected,
            onTap: () => onSelected(opt.backendValue),
          );
        }),
      ],
    );
  }
}

// ─── Option Tile ──────────────────────────────────────────────────────────────

class _OptionTile extends StatefulWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile(
      {required this.text, required this.selected, required this.onTap});

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      width: double.infinity,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _scale = 0.970),
        onTapUp: (_) {
          setState(() => _scale = 1.0);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _scale = 1.0),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
            decoration: BoxDecoration(
              color: widget.selected
                  ? _blue.withValues(alpha: 0.14)
                  : _surface.withValues(alpha: 0.50),
              border: Border.all(
                color: widget.selected
                    ? _blueSoft.withValues(alpha: 0.38)
                    : _cream.withValues(alpha: 0.07),
                width: 0.7,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              widget.text,
              style: GoogleFonts.jost(
                color:
                    widget.selected ? _cream : _cream.withValues(alpha: 0.76),
                fontSize: 14.5,
                fontWeight: widget.selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Loading Card ─────────────────────────────────────────────────────────────

class _LoadingCard extends StatelessWidget {
  final VoidCallback onFinished;
  const _LoadingCard({super.key, required this.onFinished});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 32),
        const _BreathingSilhouettes(),
        const SizedBox(height: 44),
        _CyclingLoadingText(onFinished: onFinished),
        const SizedBox(height: 8),
        Text(
          "This shouldn't take long.",
          textAlign: TextAlign.center,
          style: GoogleFonts.jost(
            color: _sand.withValues(alpha: 0.72),
            fontSize: 14,
            fontWeight: FontWeight.w300,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }
}

// ─── Breathing Silhouettes (unchanged) ───────────────────────────────────────

class _BreathingSilhouettes extends StatefulWidget {
  const _BreathingSilhouettes();

  @override
  State<_BreathingSilhouettes> createState() => _BreathingSilhouettesState();
}

class _BreathingSilhouettesState extends State<_BreathingSilhouettes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final glow = 0.5 + (_pulse.value * 0.5);
          return SizedBox(
            width: 180,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: Offset(-35 + 4 * math.sin(_pulse.value * math.pi), 5),
                  child: Opacity(
                    opacity: 0.25 + 0.15 * _pulse.value,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _violet,
                        boxShadow: [
                          BoxShadow(
                              color: _violet.withValues(alpha: 0.1),
                              blurRadius: 12)
                        ],
                      ),
                      child: const Icon(Icons.person, color: _ink, size: 38),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(35 - 4 * math.sin(_pulse.value * math.pi), 5),
                  child: Opacity(
                    opacity: 0.25 + 0.15 * _pulse.value,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _amber,
                        boxShadow: [
                          BoxShadow(
                              color: _amber.withValues(alpha: 0.1),
                              blurRadius: 12)
                        ],
                      ),
                      child: const Icon(Icons.person, color: _ink, size: 38),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 1.0 + 0.04 * math.sin(_pulse.value * math.pi),
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _surface,
                      border: Border.all(
                        color: _blueSoft.withValues(alpha: 0.12 + 0.12 * glow),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _blue.withValues(alpha: 0.10 * glow),
                          blurRadius: 20 + 8 * _pulse.value,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.person_outline,
                        color:
                            _cream.withValues(alpha: 0.3 + 0.3 * _pulse.value),
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Cycling Loading Text (unchanged) ────────────────────────────────────────

class _CyclingLoadingText extends StatefulWidget {
  final VoidCallback onFinished;
  const _CyclingLoadingText({required this.onFinished});

  @override
  State<_CyclingLoadingText> createState() => _CyclingLoadingTextState();
}

class _CyclingLoadingTextState extends State<_CyclingLoadingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _phaseIndex = 0;
  final List<String> _phases = [
    "connecting to the grid...",
    "finding people around you...",
    "gathering presence...",
  ];
  Timer? _phaseTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _phaseTimer = Timer.periodic(const Duration(milliseconds: 1800), (timer) {
      if (_phaseIndex < _phases.length - 1) {
        setState(() => _phaseIndex++);
      } else {
        timer.cancel();
        widget.onFinished();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _phaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: Text(
        _phases[_phaseIndex],
        textAlign: TextAlign.center,
        style: GoogleFonts.plusJakartaSans(
          color: _cream.withValues(alpha: 0.92),
          fontSize: 22,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}
