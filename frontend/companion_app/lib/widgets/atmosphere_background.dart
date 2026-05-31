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
    _blueOpacity = Tween<double>(begin: 0.6, end: 1.0).animate(_breatheAnim);
    _violetOpacity = Tween<double>(begin: 0.95, end: 0.55).animate(_breatheAnim);
    _amberOpacity = Tween<double>(begin: 0.55, end: 0.95).animate(_breatheAnim);
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
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const FractionalOffset(0.15, 0.12),
                          radius: 0.85,
                          colors: [
                            const Color(0xFF7DA2FF).withOpacity(0.08),
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
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const FractionalOffset(0.88, 0.72),
                          radius: 0.95,
                          colors: [
                            const Color(0xFFA78BFA).withOpacity(0.08),
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
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const FractionalOffset(0.50, 0.95),
                          radius: 0.80,
                          colors: [
                            const Color(0xFFF2B8A0).withOpacity(0.05),
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

        // ── Main content floating on top ──────────────────────────────
        if (widget.child != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: widget.child!,
            ),
          ),
      ],
    );
  }
}
