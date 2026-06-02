import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/atmosphere_background.dart';

const Color _bg = Color(0xFF080A0E);
const Color _surface = Color(0xFF10131A);
const Color _surfaceUp = Color(0xFF141720);
const Color _blue = Color(0xFF7DA2FF);
const Color _violet = Color(0xFFA78BFA);
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
      body: AtmosphereBackground(
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              SliverToBoxAdapter(
                child: _section(
                  eyebrow: 'intent',
                  title: 'a companion system with continuity',
                  body:
                      'Sol is built around a simple idea: conversations feel more real when every character has a separate memory, rhythm, and relationship record.',
                ),
              ),
              SliverToBoxAdapter(
                child: _section(
                  eyebrow: 'engineering',
                  title: 'what the project demonstrates',
                  body:
                      'The app connects mobile UI, authentication, a FastAPI backend, structured memory, character state, push notifications, and LLM response orchestration into one product flow.',
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    children: const [
                      _ProofPoint(
                        icon: Icons.memory_outlined,
                        title: 'separate character memory',
                        body: 'Each relationship has its own facts, moments, and state.',
                      ),
                      _ProofPoint(
                        icon: Icons.forum_outlined,
                        title: 'chat that keeps moving',
                        body: 'Typing, bursts, delivery, and proactive replies are coordinated across screens.',
                      ),
                      _ProofPoint(
                        icon: Icons.tune_rounded,
                        title: 'user control',
                        body: 'Users can inspect, correct, and erase what the system remembers.',
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _surface.withValues(alpha: 0.70),
                    border: Border.all(
                      color: _cream.withValues(alpha: 0.08),
                      width: 0.6,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: _sand,
                    size: 16,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'ABOUT',
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.58),
                  fontSize: 10,
                  letterSpacing: 2.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            'Sol',
            style: GoogleFonts.plusJakartaSans(
              color: _cream,
              fontSize: 42,
              fontWeight: FontWeight.w700,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'A production-minded companion app for persistent, believable AI relationships.',
            style: GoogleFonts.jost(
              color: _sand.withValues(alpha: 0.78),
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String eyebrow,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _panelDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: GoogleFonts.jost(
                color: _blue.withValues(alpha: 0.70),
                fontSize: 10,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                color: _cream.withValues(alpha: 0.94),
                fontSize: 19,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              body,
              style: GoogleFonts.jost(
                color: _sand.withValues(alpha: 0.78),
                fontSize: 13.5,
                height: 1.52,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProofPoint extends StatelessWidget {
  const _ProofPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: _panelDecoration(alpha: 0.48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _violet.withValues(alpha: 0.78), size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withValues(alpha: 0.90),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.jost(
                    color: _sand.withValues(alpha: 0.70),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _panelDecoration({double alpha = 0.56}) {
  return BoxDecoration(
    color: _surfaceUp.withValues(alpha: alpha),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: _cream.withValues(alpha: 0.06), width: 0.6),
  );
}
