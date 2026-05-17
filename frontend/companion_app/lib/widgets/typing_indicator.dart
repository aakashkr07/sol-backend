// =============================================================================
// widgets/typing_indicator.dart — Nova's "Typing..." Animation
// =============================================================================
//
// PURPOSE:
//   Shows three animated dots while Nova is generating a response.
//   This is a CRITICAL UX element — it creates the illusion that Nova
//   is "thinking" in real-time, which dramatically increases the human feel.
//
// DESIGN:
//   Three dots that pulse in sequence (not all at once).
//   Sequence: dot1 → dot2 → dot3 → dot1 → ...
//   Color: matches Nova's message bubble background.
//   Position: left-aligned (same as Nova's messages).
//
// ANIMATION DETAILS:
//   Each dot has a staggered start delay (0ms, 200ms, 400ms).
//   Animation: scale from 0.5 → 1.0 → 0.5 (breathing pulse).
//   Total loop: 1200ms (feels natural, not too fast or slow).
//
// USAGE:
//   if (isTyping) const TypingIndicator()
// =============================================================================

import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  static const int _dotCount = 3;
  static const Duration _duration = Duration(milliseconds: 600);
  static const Duration _staggerDelay = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();

    // Create one controller per dot
    _controllers = List.generate(_dotCount, (i) {
      return AnimationController(vsync: this, duration: _duration);
    });

    // Each dot animates scale: 0.4 → 1.0 → 0.4
    _animations = _controllers.map((controller) {
      return Tween<double>(
        begin: 0.4,
        end: 1.0,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();

    // Start animations with staggered delays
    _startAnimations();
  }

  void _startAnimations() async {
    for (int i = 0; i < _dotCount; i++) {
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
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 2.0, bottom: 2.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_dotCount, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i < _dotCount - 1 ? 5.0 : 0),
              child: AnimatedBuilder(
                animation: _animations[i],
                builder: (context, child) {
                  return Transform.scale(
                    scale: _animations[i].value,
                    child: child,
                  );
                },
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
