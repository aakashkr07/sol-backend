// lib/widgets/typing_indicator.dart
// Sol · TypingIndicator  [DESIGN SYSTEM ALIGNED]
//
// Changes (frontend/visual only — TypingIndicatorSpec model untouched):
//
//   · Avatar: amber gradient + Sol logo → initial letter on dark surface
//     with blue ring. Receives companionName for the initial.
//     Defaults to '?' if not provided (backward-compatible).
//
//   · Bubble background: 0xFF1A2035 → _surface (0xFF10131A).
//
//   · Dot colour: white 0.7 unchanged — works well against the dark bubble.
//
//   · Font: no text in dots, but companionName initial uses PlusJakartaSans.
//
//   · All logic (dot count, pulse duration, stagger delay, padding) untouched.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────

const Color _blue = Color(0xFF7DA2FF);
const Color _surface = Color(0xFF10131A);
const Color _cream = Color(0xFFE8DDD0);

// ─────────────────────────────────────────────────────────────────────────────
// TypingIndicatorSpec — untouched
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// TypingIndicator
// ─────────────────────────────────────────────────────────────────────────────

class TypingIndicator extends StatefulWidget {
  final TypingIndicatorSpec spec;
  final String companionName; // for initial letter in avatar

  const TypingIndicator({
    super.key,
    required this.spec,
    this.companionName = '',
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  // ── All spec logic unchanged ─────────────────────────────────────────────────

  int get _dotCount {
    if (widget.spec.isNetworkPending || widget.spec.pauseIntensity == 'long') {
      return 3;
    }
    return widget.spec.pauseIntensity == 'brief' ? 2 : 3;
  }

  Duration get _pulseDuration {
    final base = widget.spec.typingDurationMs.clamp(360, 1600);
    final divisor = _dotCount == 2 ? 2 : 3;
    return Duration(
      milliseconds: ((base / divisor).round().clamp(260, 720)),
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
        .map((c) => Tween<double>(begin: 0.38, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();
    _startAnimations();
  }

  Future<void> _startAnimations() async {
    for (var i = 0; i < _dotCount; i++) {
      await Future.delayed(_staggerDelay * i);
      if (mounted) _controllers[i].repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = widget.spec.pauseIntensity == 'long' ? 0.5 : 0.62;
    final initial = widget.companionName.isNotEmpty
        ? widget.companionName[0].toUpperCase()
        : '?';

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
          // ── Avatar — initial letter, blue ring ──────────────────────────
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _surface,
              border: Border.all(
                color: _blue.withValues(alpha: 0.40),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _blue.withValues(alpha: 0.14),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: GoogleFonts.plusJakartaSans(
                  color: _cream.withValues(alpha: 0.82),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // ── Dots bubble ─────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _surface,
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
            child: RepaintBoundary(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_dotCount, (i) {
                  return Padding(
                    padding: EdgeInsets.only(right: i < _dotCount - 1 ? 5 : 0),
                    child: AnimatedBuilder(
                      animation: _animations[i],
                      builder: (context, child) {
                        return Opacity(
                          opacity:
                              opacity + ((_animations[i].value - 0.38) * 0.28),
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
                          color: Colors.white.withValues(alpha: 0.70),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
