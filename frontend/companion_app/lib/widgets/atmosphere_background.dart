import 'package:flutter/material.dart';

/// Shared Sol background. Static by design so text entry, scrolling, and route
/// transitions do not compete with a full-screen repeating animation.
class AtmosphereBackground extends StatelessWidget {
  final Widget? child;

  const AtmosphereBackground({super.key, this.child});

  static const Color _bgDeep = Color(0xFF080A0E);
  static const Color _blueAtmosphere = Color(0x147DA2FF);
  static const Color _violetAtmosphere = Color(0x14A78BFA);
  static const Color _amberAtmosphere = Color(0x0DF2B8A0);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: _bgDeep,
              backgroundBlendMode: BlendMode.srcOver,
              gradient: RadialGradient(
                center: FractionalOffset(0.15, 0.12),
                radius: 0.85,
                colors: [_blueAtmosphere, Colors.transparent],
              ),
            ),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: FractionalOffset(0.88, 0.72),
                  radius: 0.95,
                  colors: [_violetAtmosphere, Colors.transparent],
                ),
                backgroundBlendMode: BlendMode.srcOver,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: FractionalOffset(0.50, 0.95),
                    radius: 0.80,
                    colors: [_amberAtmosphere, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (child != null) Positioned.fill(child: child!),
      ],
    );
  }
}
