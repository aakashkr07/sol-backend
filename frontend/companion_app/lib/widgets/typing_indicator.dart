import 'package:flutter/material.dart';

class TypingIndicatorSpec {
  final int typingDurationMs;
  final String pauseIntensity;
  final bool isFollowUp;
  final bool isNetworkPending;

  const TypingIndicatorSpec({
    required this.typingDurationMs,
    required this.pauseIntensity,
    required this.isFollowUp,
    required this.isNetworkPending,
  });

  factory TypingIndicatorSpec.network() {
    return const TypingIndicatorSpec(
      typingDurationMs: 780,
      pauseIntensity: 'medium',
      isFollowUp: false,
      isNetworkPending: true,
    );
  }
}

class TypingIndicator extends StatefulWidget {
  final TypingIndicatorSpec spec;

  const TypingIndicator({
    super.key,
    required this.spec,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  int get _dotCount {
    if (widget.spec.isNetworkPending || widget.spec.pauseIntensity == 'long') {
      return 3;
    }
    return widget.spec.pauseIntensity == 'brief' ? 2 : 3;
  }

  Duration get _pulseDuration {
    final base = widget.spec.typingDurationMs.clamp(360, 1600) as int;
    final divisor = _dotCount == 2 ? 2 : 3;
    return Duration(
      milliseconds: ((base / divisor).round().clamp(260, 720)) as int,
    );
  }

  Duration get _staggerDelay {
    switch (widget.spec.pauseIntensity) {
      case 'long':
        return const Duration(milliseconds: 220);
      case 'medium':
        return const Duration(milliseconds: 170);
      default:
        return const Duration(milliseconds: 120);
    }
  }

  double get _horizontalPadding => widget.spec.isFollowUp ? 14 : 16;
  double get _verticalPadding => widget.spec.pauseIntensity == 'long' ? 15 : 14;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _dotCount,
      (_) => AnimationController(vsync: this, duration: _pulseDuration),
    );
    _animations = _controllers
        .map(
          (controller) => Tween<double>(begin: 0.38, end: 1.0).animate(
            CurvedAnimation(parent: controller, curve: Curves.easeInOut),
          ),
        )
        .toList();
    _startAnimations();
  }

  Future<void> _startAnimations() async {
    for (var i = 0; i < _dotCount; i++) {
      await Future.delayed(_staggerDelay * i);
      if (mounted) {
        _controllers[i].repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = widget.spec.pauseIntensity == 'long' ? 0.5 : 0.62;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 72,
        top: widget.spec.isFollowUp ? 10 : 6,
        bottom: 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFFF5A623), Color(0xFF3D2A00)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF5A623).withValues(alpha: 0.22),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Center(
              child: Image(
                image: AssetImage('assets/images/sol_logo.png'),
                width: 14,
                height: 14,
              ),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: const Color(0xFF1A2035),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(widget.spec.isFollowUp ? 18 : 16),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(widget.spec.isFollowUp ? 10 : 4),
                bottomRight: const Radius.circular(18),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
                width: 0.6,
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: _horizontalPadding,
              vertical: _verticalPadding,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_dotCount, (i) {
                return Padding(
                  padding: EdgeInsets.only(right: i < _dotCount - 1 ? 5 : 0),
                  child: AnimatedBuilder(
                    animation: _animations[i],
                    builder: (context, child) {
                      return Opacity(
                        opacity: opacity + ((_animations[i].value - 0.38) * 0.28),
                        child: Transform.scale(
                          scale: _animations[i].value,
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      width: widget.spec.pauseIntensity == 'long' ? 6 : 7,
                      height: widget.spec.pauseIntensity == 'long' ? 6 : 7,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
