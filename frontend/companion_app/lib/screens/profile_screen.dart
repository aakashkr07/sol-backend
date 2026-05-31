import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — Sol Design System (mirrored from InboxScreen)
// ─────────────────────────────────────────────────────────────────────────────

const Color _bgDeep = Color(0xFF080A0E);
const Color _surface = Color(0xFF10131A);
const Color _surfaceUp = Color(0xFF141720);

const Color _blue = Color(0xFF7DA2FF);
const Color _violet = Color(0xFFA78BFA);
const Color _amber = Color(0xFFF2B8A0);

const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);
const Color _dusty = Color(0xFF5A5568);
const Color _ink = Color(0xFF060810);

// ─────────────────────────────────────────────────────────────────────────────
// ProfileScreen
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  final String? initialPairId;

  const ProfileScreen({
    super.key,
    this.initialPairId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  // ── State (untouched) ─────────────────────────────────────────────────────
  UserProfileResponse? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _selectedPairId;

  // ── Animation controllers ─────────────────────────────────────────────────
  late AnimationController _breatheCtrl;
  late AnimationController _fadeInCtrl;
  late Animation<double> _breatheAnim;
  late Animation<double> _fadeInAnim;

  late final Animation<double> _blueOpacity;
  late final Animation<double> _violetOpacity;
  late final Animation<double> _amberOpacity;

  @override
  void initState() {
    super.initState();
    _selectedPairId = widget.initialPairId;

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _breatheAnim = CurvedAnimation(
      parent: _breatheCtrl,
      curve: Curves.easeInOut,
    );

    _violetOpacity =
        Tween<double>(begin: 0.028, end: 0.046).animate(_breatheAnim);
    _blueOpacity =
        Tween<double>(begin: 0.030, end: 0.018).animate(_breatheAnim);
    _amberOpacity =
        Tween<double>(begin: 0.012, end: 0.020).animate(_breatheAnim);

    _fadeInCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeInAnim = CurvedAnimation(
      parent: _fadeInCtrl,
      curve: Curves.easeOut,
    );

    _load();
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _fadeInCtrl.dispose();
    super.dispose();
  }

  // ── Data (untouched logic) ────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await ApiService.getMyProfile(pairId: _selectedPairId);
      if (profile == null) throw Exception('Could not load your Sol profile.');
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _selectedPairId = profile.selectedPair?.pairId ?? _selectedPairId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    _fadeInCtrl.forward(from: 0);
  }

  Future<void> _updatePreferences(Map<String, dynamic> updates) async {
    setState(() => _isSaving = true);
    try {
      await ApiService.updatePreferences(updates);
      await _load();
    } on ChatException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updatePairPreferences(Map<String, dynamic> updates) async {
    final pairId = _profile?.selectedPair?.pairId;
    if (pairId == null) return;
    setState(() => _isSaving = true);
    try {
      await ApiService.updatePairPreferences(pairId, updates);
      await _load();
    } on ChatException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickQuietHour({required bool isStart}) async {
    final prefs = _profile?.preferences;
    if (prefs == null) return;
    final initialHour = isStart ? prefs.quietHoursStart : prefs.quietHoursEnd;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: _blue,
              surface: _surfaceUp,
            ),
          ),
          child: child!,
        );
      },
    );
    if (selected == null) return;
    await _updatePreferences({
      isStart ? 'quiet_hours_start' : 'quiet_hours_end': selected.hour,
    });
  }

  Future<void> _resetRelationship() async {
    final pair = _profile?.selectedPair;
    if (pair == null) return;
    final confirmed = await _confirm(
      title: 'start this thread over?',
      body:
          'this clears the private continuity built with ${pair.name} and starts the thread fresh.',
      confirmLabel: 'start over',
    );
    if (!confirmed) return;
    try {
      await ApiService.resetPairMemory(pair.pairId);
      await _load();
      _showSnack('${pair.name} has been reset.');
    } on ChatException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirm(
      title: 'delete your sol account?',
      body:
          'this removes your inbox, thread history, and saved settings across the app.',
      confirmLabel: 'delete account',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ApiService.deleteAccount();
      await AuthService.signOut();
    } on ChatException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: _ink.withOpacity(0.80),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AlertDialog(
            backgroundColor: _surfaceUp,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: _cream.withOpacity(0.06), width: 0.6),
            ),
            title: Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                color: _cream.withOpacity(0.92),
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            content: Text(
              body,
              style: GoogleFonts.jost(
                color: _sand.withOpacity(0.72),
                fontSize: 14,
                height: 1.55,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'cancel',
                  style: GoogleFonts.jost(
                    color: _sand.withOpacity(0.55),
                    fontSize: 13.5,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  confirmLabel,
                  style: GoogleFonts.jost(
                    color: destructive
                        ? const Color(0xFFE07070).withOpacity(0.85)
                        : _blue.withOpacity(0.85),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    return result == true;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _surfaceUp,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _cream.withOpacity(0.06), width: 0.6),
        ),
        content: Text(
          message,
          style: GoogleFonts.jost(
            color: _sand.withOpacity(0.80),
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _hourLabel(int hour) {
    final suffix = hour >= 12 ? 'pm' : 'am';
    final normalized = hour % 12 == 0 ? 12 : hour % 12;
    return '$normalized $suffix';
  }

  // ── Build ─────────────────────────────────────────────────────────────────
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
      body: Stack(
        children: [
          // ── Atmospheric breathing background ──────────────────────────
          _buildAtmosphere(),

          // ── Global glassmorphic blur overlay ──────────────────────────
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: const SizedBox.shrink(),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Atmosphere ────────────────────────────────────────────────────────────
  Widget _buildAtmosphere() {
    return Stack(
      children: [
        // Base deep background fill
        Positioned.fill(
          child: Container(
            color: const Color(0xFF080A0E),
          ),
        ),
        // Orb 1 — warm violet (top-right)
        Positioned.fill(
          child: FadeTransition(
            opacity: _violetOpacity,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: FractionalOffset(0.85, 0.12),
                  radius: 0.65,
                  colors: [
                    Color(0xFFA78BFA),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Orb 2 — presence blue (center-left)
        Positioned.fill(
          child: FadeTransition(
            opacity: _blueOpacity,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: FractionalOffset(0.12, 0.60),
                  radius: 0.75,
                  colors: [
                    Color(0xFF7DA2FF),
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
                  center: FractionalOffset(0.50, 0.96),
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
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 18, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Back button — glassmorphic, same as icon buttons in Inbox
          _iconBtn(Icons.arrow_back_rounded, () => Navigator.of(context).pop()),
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
                        color: _violet.withOpacity(0.70),
                        boxShadow: [
                          BoxShadow(
                            color: _violet.withOpacity(0.55),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'sol',
                      style: GoogleFonts.jost(
                        color: _sand.withOpacity(0.58),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'presence & privacy.',
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withOpacity(0.92),
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.3,
                    height: 1.12,
                  ),
                ),
              ],
            ),
          ),
          // Saving indicator
          if (_isSaving)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.0,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _blue.withOpacity(0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_isLoading) return _buildLoader();
    if (_error != null) return _buildErrorState();

    return FadeTransition(
      opacity: _fadeInAnim,
      child: RefreshIndicator(
        color: _amber,
        backgroundColor: _surface,
        displacement: 20,
        onRefresh: _load,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 60),
          children: [
            _buildIdentityCard(),
            _buildSectionGap(),
            _buildConversationCard(),
            _buildSectionGap(),
            _buildPrivacyCard(),
            _buildSectionGap(),
            _buildNotificationCard(),
            _buildSectionGap(),
            _buildDestructiveCard(),
          ],
        ),
      ),
    );
  }

  // ── Loader ────────────────────────────────────────────────────────────────
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
                _violet.withOpacity(0.62),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'loading your presence…',
            style: GoogleFonts.plusJakartaSans(
              color: _sand.withOpacity(0.38),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE07070).withOpacity(0.60),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'something went wrong.',
              textAlign: TextAlign.center,
              style: GoogleFonts.jost(
                color: _sand.withOpacity(0.52),
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section gap (replaces SizedBox(height:14)) ────────────────────────────
  Widget _buildSectionGap() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        height: 0.4,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              _cream.withOpacity(0.06),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  // ── Card wrapper ──────────────────────────────────────────────────────────
  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: _surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _cream.withOpacity(0.08),
          width: 0.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                color: _cream.withOpacity(0.90),
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: GoogleFonts.jost(
                color: _sand.withOpacity(0.52),
                fontSize: 12.5,
                height: 1.50,
                letterSpacing: 0.1,
              ),
            ),
            // Hairline rule
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Container(
                height: 0.4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _cream.withOpacity(0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }

  // ── Toggle row ────────────────────────────────────────────────────────────
  Widget _toggleRow({
    required String title,
    String? subtitle,
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
                    color: _cream.withOpacity(0.82),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.jost(
                      color: _dusty.withOpacity(0.80),
                      fontSize: 12,
                      height: 1.45,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _SolSwitch(
            value: value,
            onChanged: _isSaving ? null : onChanged,
          ),
        ],
      ),
    );
  }

  // ── Section cards (untouched logic) ───────────────────────────────────────

  Widget _buildIdentityCard() {
    final user = _profile?.user ?? const {};
    final pair = _profile?.selectedPair;

    return _sectionCard(
      title: 'you and sol.',
      subtitle:
          'the person you are currently talking to and the threads tied to your account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User name
          Text(
            user['name'] as String? ?? user['display_name'] as String? ?? 'you',
            style: GoogleFonts.plusJakartaSans(
              color: _cream.withOpacity(0.92),
              fontSize: 20,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            pair == null
                ? 'no active thread selected yet.'
                : 'you are in ${pair.name}\'s thread right now.',
            style: GoogleFonts.jost(
              color: _sand.withOpacity(0.55),
              fontSize: 13,
              letterSpacing: 0.1,
            ),
          ),

          // Pair summary
          if (pair != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surfaceUp.withOpacity(0.60),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _cream.withOpacity(0.04),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pair.summary.ifEmpty('a thread that keeps its own pace.'),
                    style: GoogleFonts.jost(
                      color: _sand.withOpacity(0.72),
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _violet.withOpacity(0.45),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'each thread stays private to that person.',
                        style: GoogleFonts.jost(
                          color: _dusty.withOpacity(0.80),
                          fontSize: 11.5,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Thread switcher
          if ((_profile?.pairs.length ?? 0) > 1) ...[
            const SizedBox(height: 16),
            _SolDropdown<String>(
              label: 'view another thread',
              value: _selectedPairId,
              items: _profile!.pairs
                  .map((p) => DropdownMenuItem<String>(
                        value: p.pairId,
                        child: Text(
                          p.name,
                          style: GoogleFonts.jost(
                            color: _cream.withOpacity(0.82),
                            fontSize: 13.5,
                          ),
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedPairId = value);
                _load();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConversationCard() {
    final pair = _profile?.selectedPair;
    final pairPrefs = _profile?.pairPreferences;
    if (pair == null || pairPrefs == null) return const SizedBox.shrink();

    return _sectionCard(
      title: 'thread behavior.',
      subtitle:
          'shape how this specific person reaches out without exposing the machinery underneath.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pair.name} can feel more present here than someone else in your inbox. these controls stay local to this thread.',
            style: GoogleFonts.jost(
              color: _sand.withOpacity(0.58),
              fontSize: 13,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 16),
          _toggleRow(
            title: 'let ${pair.name} start the conversation',
            value: pairPrefs.proactiveEnabled,
            onChanged: (v) => _updatePairPreferences({'proactive_enabled': v}),
          ),
          _dividerLine(),
          _toggleRow(
            title: 'allow more emotionally aware check-ins',
            subtitle:
                'lets ${pair.name} follow up after heavier moments, not just silence.',
            value: pairPrefs.proactiveEmotionalCallbacksEnabled,
            onChanged: (v) => _updatePairPreferences(
                {'proactive_emotional_callbacks_enabled': v}),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyCard() {
    final prefs = _profile?.preferences;
    if (prefs == null) return const SizedBox.shrink();

    return _sectionCard(
      title: 'privacy & presence.',
      subtitle:
          'quiet controls for storage, notifications, and when the app should leave you alone.',
      child: Column(
        children: [
          _toggleRow(
            title: 'allow continuity across conversations',
            subtitle: 'keep context so threads feel consistent over time.',
            value: prefs.allowMemoryStorage,
            onChanged: (v) => _updatePreferences({'allow_memory_storage': v}),
          ),
          _dividerLine(),
          _toggleRow(
            title: 'allow proactive messages',
            subtitle: 'let sol start the conversation sometimes.',
            value: prefs.allowProactiveMessages,
            onChanged: (v) =>
                _updatePreferences({'allow_proactive_messages': v}),
          ),
          _dividerLine(),
          _toggleRow(
            title: 'allow push notification hooks',
            subtitle: 'needed for proactive messages outside the app.',
            value: prefs.allowPushNotifications,
            onChanged: (v) =>
                _updatePreferences({'allow_push_notifications': v}),
          ),
          _dividerLine(),
          _toggleRow(
            title: 'allow sensitive emotional check-ins',
            subtitle: 'lets sol follow up after heavier emotional moments.',
            value: prefs.allowSensitiveProactive,
            onChanged: (v) =>
                _updatePreferences({'allow_sensitive_proactive': v}),
          ),
          const SizedBox(height: 18),
          // Quiet hours — inline pill buttons
          Row(
            children: [
              Expanded(
                child: _quietHourBtn(
                  label: 'quiet starts',
                  time: _hourLabel(prefs.quietHoursStart),
                  onTap: () => _pickQuietHour(isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quietHourBtn(
                  label: 'quiet ends',
                  time: _hourLabel(prefs.quietHoursEnd),
                  onTap: () => _pickQuietHour(isStart: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard() {
    final pair = _profile?.selectedPair;
    final pairPrefs = _profile?.pairPreferences;
    final prefs = _profile?.preferences;
    if (pair == null || pairPrefs == null || prefs == null) {
      return const SizedBox.shrink();
    }

    return _sectionCard(
      title: 'notification style.',
      subtitle:
          'fine-tune how this thread should feel when it reaches back out.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceUp.withOpacity(0.60),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: prefs.allowPushNotifications
                    ? _blue.withOpacity(0.12)
                    : _cream.withOpacity(0.04),
                width: 0.6,
              ),
            ),
            child: Text(
              prefs.allowPushNotifications
                  ? '${pair.name} can appear quietly when the moment feels right.'
                  : 'push is off, so ${pair.name} will only wait inside the inbox.',
              style: GoogleFonts.jost(
                color: prefs.allowPushNotifications
                    ? _sand.withOpacity(0.78)
                    : _dusty.withOpacity(0.82),
                fontSize: 13,
                height: 1.55,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Cadence picker
          _SolDropdown<String>(
            label: 'reach-out frequency',
            value: pairPrefs.proactiveCadence,
            items: [
              DropdownMenuItem(
                value: 'gentle',
                child: Text('gentle',
                    style: GoogleFonts.jost(
                        color: _cream.withOpacity(0.82), fontSize: 13.5)),
              ),
              DropdownMenuItem(
                value: 'balanced',
                child: Text('balanced',
                    style: GoogleFonts.jost(
                        color: _cream.withOpacity(0.82), fontSize: 13.5)),
              ),
              DropdownMenuItem(
                value: 'frequent',
                child: Text('frequent',
                    style: GoogleFonts.jost(
                        color: _cream.withOpacity(0.82), fontSize: 13.5)),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              _updatePairPreferences({'proactive_cadence': v});
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _amber.withOpacity(0.38),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'quiet hours make every thread hold off until you are more likely to want it.',
                  style: GoogleFonts.jost(
                    color: _dusty.withOpacity(0.82),
                    fontSize: 12,
                    height: 1.45,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDestructiveCard() {
    final pair = _profile?.selectedPair;

    return _sectionCard(
      title: 'reset & delete.',
      subtitle:
          'use these only if you want to clear a thread or leave sol entirely.',
      child: Column(
        children: [
          // Reset thread button
          _SolActionButton(
            label: pair == null
                ? 'no thread selected'
                : 'start ${pair.name}\'s thread over',
            enabled: pair != null,
            onTap: _resetRelationship,
          ),
          const SizedBox(height: 10),
          // Delete account button — destructive
          _SolActionButton(
            label: 'delete sol account',
            destructive: true,
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }

  // ── Micro-components ──────────────────────────────────────────────────────

  Widget _dividerLine() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        height: 0.4,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _cream.withOpacity(0.055),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _quietHourBtn({
    required String label,
    required String time,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        decoration: BoxDecoration(
          color: _surfaceUp.withOpacity(0.70),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _cream.withOpacity(0.06),
            width: 0.6,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.jost(
                color: _dusty.withOpacity(0.80),
                fontSize: 11,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              time,
              style: GoogleFonts.plusJakartaSans(
                color: _sand.withOpacity(0.82),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _surface.withOpacity(0.70),
          border: Border.all(
            color: _cream.withOpacity(0.08),
            width: 0.6,
          ),
        ),
        child: Icon(
          icon,
          size: 15,
          color: _sand.withOpacity(0.72),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SolSwitch — custom switch matching Sol palette
// ─────────────────────────────────────────────────────────────────────────────

class _SolSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SolSwitch({required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        width: 42,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: value ? _blue.withOpacity(0.55) : _surfaceUp.withOpacity(0.90),
          border: Border.all(
            color: value ? _blue.withOpacity(0.35) : _cream.withOpacity(0.08),
            width: 0.7,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: _blue.withOpacity(0.18),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    value ? _cream.withOpacity(0.92) : _dusty.withOpacity(0.60),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SolDropdown — dropdown styled to Sol palette
// ─────────────────────────────────────────────────────────────────────────────

class _SolDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _SolDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceUp.withOpacity(0.70),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _cream.withOpacity(0.07),
          width: 0.6,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: _surfaceUp,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: _sand.withOpacity(0.45),
          ),
          hint: Text(
            label,
            style: GoogleFonts.jost(
              color: _dusty.withOpacity(0.80),
              fontSize: 13,
            ),
          ),
          isExpanded: true,
          style: GoogleFonts.jost(
            color: _cream.withOpacity(0.82),
            fontSize: 13.5,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SolActionButton — action button (neutral or destructive)
// ─────────────────────────────────────────────────────────────────────────────

class _SolActionButton extends StatefulWidget {
  final String label;
  final bool destructive;
  final bool enabled;
  final VoidCallback onTap;

  const _SolActionButton({
    required this.label,
    this.destructive = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  State<_SolActionButton> createState() => _SolActionButtonState();
}

class _SolActionButtonState extends State<_SolActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;

    final borderColor = widget.destructive
        ? const Color(0xFFE07070).withOpacity(active ? 0.28 : 0.10)
        : _cream.withOpacity(active ? 0.09 : 0.04);

    final textColor = widget.destructive
        ? const Color(0xFFE07070).withOpacity(active ? 0.72 : 0.28)
        : _sand.withOpacity(active ? 0.65 : 0.28);

    final fillColor = _pressed
        ? (widget.destructive
            ? const Color(0xFFE07070).withOpacity(0.05)
            : _cream.withOpacity(0.02))
        : Colors.transparent;

    return GestureDetector(
      onTapDown: active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: active
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: widget.destructive
              ? const Color(0xFF2A0E0E).withOpacity(active ? 0.45 : 0.20)
              : fillColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 0.6),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: GoogleFonts.jost(
              color: textColor,
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AtmospherePainter — identical to InboxScreen
// ─────────────────────────────────────────────────────────────────────────────

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
