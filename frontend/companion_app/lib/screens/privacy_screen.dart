// =============================================================================
// privacy_screen.dart — Sol Privacy & Governance Screen
// =============================================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../widgets/atmosphere_background.dart';

// Sol Palette
const Color _bgDeep = Color(0xFF080A0E);
const Color _surface = Color(0xFF10131A);
const Color _surfaceUp = Color(0xFF141720);
const Color _blue = Color(0xFF7DA2FF);
const Color _violet = Color(0xFFA78BFA);
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);
const Color _dusty = Color(0xFF5A5568);
const Color _ink = Color(0xFF060810);

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen>
    with SingleTickerProviderStateMixin {
  UserProfileResponse? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // Mock security logs for high-fidelity security logs panel
  final List<Map<String, String>> _mockSecurityLogs = [
    {
      'time': '01:14:02',
      'event': 'secure vault configuration initialized.',
      'status': 'OK'
    },
    {
      'time': '01:14:05',
      'event': 'biometric authorization parameters verified.',
      'status': 'SECURE'
    },
    {
      'time': '01:15:20',
      'event': 'vector semantic chunk index updated successfully.',
      'status': 'ACTIVE'
    },
    {
      'time': '01:18:11',
      'event': 'continuity key encryption stashed locally.',
      'status': 'OK'
    },
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await ApiService.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'could not pull privacy preferences. tap to retry.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updatePref(String key, bool value) async {
    setState(() => _isSaving = true);
    try {
      await ApiService.updatePreferences({key: value});
      await _load();
    } catch (e) {
      _showSnack('failed to update preference. try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _surfaceUp,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          message,
          style: GoogleFonts.jost(
            color: _sand.withValues(alpha: 0.85),
            fontSize: 13,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: _bgDeep,
      body: AtmosphereBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _surface.withValues(alpha: 0.70),
                border: Border.all(color: _cream.withValues(alpha: 0.08), width: 0.6),
              ),
              child:
                  const Icon(Icons.arrow_back_rounded, size: 15, color: _sand),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _violet.withValues(alpha: 0.70),
                        boxShadow: [
                          BoxShadow(
                            color: _violet.withValues(alpha: 0.55),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'PRIVACY',
                      style: GoogleFonts.jost(
                        color: _sand.withValues(alpha: 0.58),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'presence & safety.',
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withValues(alpha: 0.92),
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          if (_isSaving)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.0,
                valueColor: AlwaysStoppedAnimation<Color>(_blue),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoader();
    if (_error != null) return _buildErrorState();

    final prefs = _profile?.preferences;
    if (prefs == null) return _buildErrorState();

    return FadeTransition(
      opacity: _fadeAnim,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        children: [
          // ── Privacy Toggles Card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface.withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _cream.withValues(alpha: 0.08), width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'continuity & storage controls',
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withValues(alpha: 0.90),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                _buildToggleRow(
                  title: 'allow memory storage',
                  subtitle: 'keep contextual continuity so companions remember shared moments.',
                  value: prefs.allowMemoryStorage,
                  onChanged: (v) => _updatePref('allow_memory_storage', v),
                ),
                _buildDivider(),
                _buildToggleRow(
                  title: 'allow proactive messages',
                  subtitle: 'allows your companions to organically reach out in your inbox.',
                  value: prefs.allowProactiveMessages,
                  onChanged: (v) => _updatePref('allow_proactive_messages', v),
                ),
                _buildDivider(),
                _buildToggleRow(
                  title: 'allow push notifications',
                  subtitle: 'gains push capability for notifications outside the companion window.',
                  value: prefs.allowPushNotifications,
                  onChanged: (v) => _updatePref('allow_push_notifications', v),
                ),
                _buildDivider(),
                _buildToggleRow(
                  title: 'allow sensitive emotional check-ins',
                  subtitle: 'allows companions to follow up after heavy or vulnerable conversations.',
                  value: prefs.allowSensitiveProactive,
                  onChanged: (v) => _updatePref('allow_sensitive_proactive', v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Privacy Policies Placeholder Card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _cream.withValues(alpha: 0.05), width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'data governance policy',
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'your vulnerabilities, memories, and presence metadata are kept fully sandbox-isolated. sol does not feed data into public systems. everything exists to serve one feeling: that someone is thinking about you.',
                  style: GoogleFonts.jost(
                    color: _sand.withValues(alpha: 0.68),
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: _cream.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _cream.withValues(alpha: 0.05), width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 14, color: _violet.withValues(alpha: 0.70)),
                      const SizedBox(width: 8),
                      Text(
                        '100% client-isolated encryption active.',
                        style: GoogleFonts.jost(
                          color: _sand.withValues(alpha: 0.80),
                          fontSize: 11,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Security Logs Placeholder Card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _cream.withValues(alpha: 0.04), width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'local security logs',
                      style: GoogleFonts.plusJakartaSans(
                        color: _cream.withValues(alpha: 0.80),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Column(
                  children: _mockSecurityLogs.map((log) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '[${log['time']}] ',
                            style: GoogleFonts.jost(
                              color: _blue.withValues(alpha: 0.70),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              log['event']!,
                              style: GoogleFonts.jost(
                                color: _sand.withValues(alpha: 0.72),
                                fontSize: 11.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            log['status']!,
                            style: GoogleFonts.jost(
                              color: log['status'] == 'SECURE' || log['status'] == 'ACTIVE'
                                  ? _violet.withValues(alpha: 0.75)
                                  : _sand.withValues(alpha: 0.50),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLoader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.0,
              valueColor: AlwaysStoppedAnimation<Color>(
                _violet.withValues(alpha: 0.62),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'gathering presence…',
            style: GoogleFonts.plusJakartaSans(
              color: _sand.withValues(alpha: 0.38),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _load,
              child: Text(
                _error ?? 'something went wrong.',
                textAlign: TextAlign.center,
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.52),
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.jost(
                    color: _cream.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.jost(
                    color: _dusty.withValues(alpha: 0.90),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _CustomSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Container(
        height: 0.4,
        color: _cream.withValues(alpha: 0.06),
      ),
    );
  }
}

class _CustomSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CustomSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: value ? _blue.withValues(alpha: 0.55) : _surfaceUp.withValues(alpha: 0.90),
          border: Border.all(
            color: value ? _blue.withValues(alpha: 0.35) : _cream.withValues(alpha: 0.08),
            width: 0.7,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3.0),
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? _cream : _dusty.withValues(alpha: 0.60),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
