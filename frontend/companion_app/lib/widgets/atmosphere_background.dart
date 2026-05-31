import 'dart:ui';
import 'package:flutter/material.dart';

/// Unified, slowly breathing atmospheric background for the Sol app.
/// Implements three slow-oscillating radial gradients representing:
/// - Presence Blue (top-left)
/// - Warm Violet (bottom-right)
/// - Human Warmth (bottom-center)
///
/// Features high performance optimizations such as wrapping the gradients
/// in a RepaintBoundary to avoid unnecessary paint cycles.
class AtmosphereBackground extends StatefulWidget {
  final Widget? child;

  const AtmosphereBackground({super.key, this.child});

  @override
  State<AtmosphereBackground> createState() => _AtmosphereBackgroundState();
}

class _AtmosphereBackgroundState extends State<AtmosphereBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _breatheCtrl;
  late Animation<double> _breatheAnim;

  late final Animation<double> _blueOpacity;
  late final Animation<double> _violetOpacity;
  late final Animation<double> _amberOpacity;

  @override
  void initState() {
    super.initState();

    // Breathing background controller oscillates slowly over 7 seconds
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);

    _breatheAnim = CurvedAnimation(
      parent: _breatheCtrl,
      curve: Curves.easeInOut,
    );

    // Fade bounds tailored to keep the background deep, atmospheric, and legible
    _blueOpacity = Tween<double>(begin: 0.028, end: 0.046).animate(_breatheAnim);
    _violetOpacity = Tween<double>(begin: 0.038, end: 0.022).animate(_breatheAnim);
    _amberOpacity = Tween<double>(begin: 0.014, end: 0.024).animate(_breatheAnim);
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Breathing base layer (highly performant repaint boundary) ──────
        Positioned.fill(
          child: RepaintBoundary(
            child: Stack(
              children: [
                // Base deep background fill
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF080A0E),
                  ),
                ),
                // Orb 1 — presence blue (top-left)
                Positioned.fill(
                  child: FadeTransition(
                    opacity: _blueOpacity,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: FractionalOffset(0.15, 0.12),
                          radius: 0.65,
                          colors: [
                            Color(0xFF7DA2FF),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Orb 2 — warm violet (bottom-right)
                Positioned.fill(
                  child: FadeTransition(
                    opacity: _violetOpacity,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: FractionalOffset(0.88, 0.72),
                          radius: 0.75,
                          colors: [
                            Color(0xFFA78BFA),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Orb 3 — center-bottom, human warmth (bottom-center)
                Positioned.fill(
                  child: FadeTransition(
                    opacity: _amberOpacity,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: FractionalOffset(0.50, 0.95),
                          radius: 0.55,
                          colors: [
                            Color(0xFFF2B8A0),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Global glassmorphic blur overlay ──────────────────────────
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const SizedBox.shrink(),
          ),
        ),

        // ── Main content floating on top ──────────────────────────────
        if (widget.child != null) widget.child!,
      ],
    );
  }
}
