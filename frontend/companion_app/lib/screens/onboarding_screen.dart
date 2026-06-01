import 'dart:async';
import 'dart:math' as math;

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

class OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onComplete;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0;
  String _preferredName = '';
  String _connectionStyle = '';
  String _presenceFrequency = '';
  String _depthPreference = '';
  String _behavioralGuardrail = '';

  OnboardingCompleteResponse? _matchedResponse;
  bool _isStarting = false;
  String? _error;
  bool _apiSuccess = false;
  bool _cycleFinished = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _submitOnboarding() async {
    setState(() {
      _currentStep = 5; // Finding your people loading state
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
      setState(() {
        _matchedResponse = response;
        _apiSuccess = true;
      });

      if (_apiSuccess && _cycleFinished) {
        _completeAndNavigate();
      }
    } on ChatException catch (e) {
      setState(() {
        _error = e.message;
        _currentStep = 4; // Go back to Q5 to retry
      });
    } catch (_) {
      setState(() {
        _error = 'The matching system encountered an error. Try again.';
        _currentStep = 4; // Go back to Q5 to retry
      });
    }
  }

  Future<void> _completeAndNavigate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await OnboardingService.markComplete(uid);
    }
    widget.onComplete();
  }

  void _onOptionSelected(int step, String backendValue) {
    HapticFeedback.lightImpact();

    // Assign values depending on step
    if (step == 1) _connectionStyle = backendValue;
    if (step == 2) _presenceFrequency = backendValue;
    if (step == 3) _depthPreference = backendValue;
    if (step == 4) _behavioralGuardrail = backendValue;

    // Small delay (350ms) to allow the user to see the selected state before moving
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (step < 4) {
        setState(() {
          _currentStep = step + 1;
        });
      } else {
        _submitOnboarding();
      }
    });
  }

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
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0.0, 0.06),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: _buildCurrentStepWidget(),
                      ),
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

  Widget _buildBackButton() {
    if (_currentStep == 0 || _currentStep >= 5) {
      return const SizedBox(height: 40);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _currentStep--;
          });
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _surface.withOpacity(0.70),
            border: Border.all(color: _cream.withOpacity(0.08), width: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.chevron_left,
            color: _cream,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepWidget() {
    switch (_currentStep) {
      case 0:
        return _NameInputCard(
          key: const ValueKey('step-name'),
          onSubmitted: (name) {
            HapticFeedback.lightImpact();
            setState(() {
              _preferredName = name;
              _currentStep = 1;
            });
          },
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
        return _buildLoadingState();

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLoadingState() {
    return Center(
      key: const ValueKey('step-loading'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          // Subtle animated profile silhouettes
          const _BreathingSilhouettes(),
          const SizedBox(height: 48),
          _CyclingLoadingText(
            onFinished: () {
              if (mounted) {
                setState(() {
                  _cycleFinished = true;
                });
                if (_apiSuccess && _cycleFinished) {
                  _completeAndNavigate();
                }
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            "This shouldn't take long.",
            textAlign: TextAlign.center,
            style: GoogleFonts.jost(
              color: _sand.withOpacity(0.72),
              fontSize: 14,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildErrorPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF331515).withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE08B8B).withOpacity(0.22),
        ),
      ),
      child: Text(
        _error!,
        style: GoogleFonts.jost(
          color: const Color(0xFFE08B8B),
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}

class _NameInputCard extends StatefulWidget {
  final Function(String) onSubmitted;
  const _NameInputCard({super.key, required this.onSubmitted});

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
      setState(() {
        _canSubmit = _controller.text.trim().isNotEmpty;
      });
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
        Text(
          'Before we start...',
          style: GoogleFonts.plusJakartaSans(
            color: _cream.withOpacity(0.92),
            fontSize: 25,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'What should we call you?',
          style: GoogleFonts.plusJakartaSans(
            color: _sand.withOpacity(0.72),
            fontSize: 16,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 36),
        Container(
          decoration: BoxDecoration(
            color: _surface.withOpacity(0.70),
            border: Border.all(color: _cream.withOpacity(0.08), width: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            controller: _controller,
            cursorColor: _blueSoft,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.jost(
              color: _cream,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: 'Enter your preferred name',
              hintStyle: GoogleFonts.jost(
                color: _dusty,
                fontSize: 16,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: InputBorder.none,
            ),
            onSubmitted: (_) {
              if (_canSubmit) widget.onSubmitted(_controller.text.trim());
            },
          ),
        ),
        const SizedBox(height: 48),
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
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Continue',
                  style: GoogleFonts.jost(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
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
            color: _cream.withOpacity(0.92),
            fontSize: 24,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          question,
          style: GoogleFonts.plusJakartaSans(
            color: _sand.withOpacity(0.72),
            fontSize: 15,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 36),
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

class _OptionTile extends StatefulWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: widget.selected
                  ? _blue.withOpacity(0.15)
                  : _surface.withOpacity(0.70),
              border: Border.all(
                color: widget.selected
                    ? _blueSoft.withOpacity(0.4)
                    : _cream.withOpacity(0.08),
                width: 0.6,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              widget.text,
              style: GoogleFonts.jost(
                color: widget.selected ? _cream : _cream.withOpacity(0.78),
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

class _BreathingText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _BreathingText({required this.text, required this.style});

  @override
  State<_BreathingText> createState() => _BreathingTextState();
}

class _BreathingTextState extends State<_BreathingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_ctrl),
      child: Text(widget.text, style: widget.style),
    );
  }
}

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
                // Silhouette 1 (Back left)
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
                            color: _violet.withOpacity(0.1),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        color: _ink,
                        size: 38,
                      ),
                    ),
                  ),
                ),
                // Silhouette 2 (Back right)
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
                            color: _amber.withOpacity(0.1),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        color: _ink,
                        size: 38,
                      ),
                    ),
                  ),
                ),
                // Silhouette 3 (Foreground center glowing)
                Transform.scale(
                  scale: 1.0 + 0.04 * math.sin(_pulse.value * math.pi),
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _surface,
                      border: Border.all(
                        color: _blueSoft.withOpacity(0.12 + 0.12 * glow),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _blue.withOpacity(0.10 * glow),
                          blurRadius: 20 + 8 * _pulse.value,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.person_outline,
                        color: _cream.withOpacity(0.3 + 0.3 * _pulse.value),
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
        setState(() {
          _phaseIndex++;
        });
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
          color: _cream.withOpacity(0.92),
          fontSize: 22,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}
