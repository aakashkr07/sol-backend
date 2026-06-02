// =============================================================================
// settings_screen.dart — Sol Settings and Configurations
// =============================================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/notification_service.dart';
import '../widgets/atmosphere_background.dart';
import 'vault_screen.dart';

// Sol Palette
const Color _bgDeep = Color(0xFF080A0E);
const Color _surface = Color(0xFF10131A);
const Color _surfaceUp = Color(0xFF141720);
const Color _blue = Color(0xFF7DA2FF);
const Color _amber = Color(0xFFF2B8A0);
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);
const Color _dusty = Color(0xFF5A5568);
const Color _ink = Color(0xFF060810);
const Color _destructiveRed = Color(0xFFE07070);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  UserProfileResponse? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  bool _vaultLocked = false;
  bool _vibrateOnPresence = true;
  bool _playSolChimes = true;
  bool _showActiveRoomBanners = true;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

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
      final vault = await BiometricService.isVaultEnabled();
      final localPrefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _vaultLocked = vault;
        _vibrateOnPresence =
            localPrefs.getBool(solNotificationHapticsEnabledKey) ?? true;
        _playSolChimes =
            localPrefs.getBool(solNotificationSoundEnabledKey) ?? true;
        _showActiveRoomBanners =
            localPrefs.getBool(solNotificationBannersEnabledKey) ?? true;
        _isLoading = false;
      });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'could not pull app preferences. tap to retry.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updatePref(String key, dynamic value) async {
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

  Future<void> _updatePairPref(String pairId, String key, dynamic value) async {
    setState(() => _isSaving = true);
    try {
      await ApiService.updatePairPreferences(pairId, {key: value});
      await _load();
    } catch (e) {
      _showSnack('failed to update cadence preference.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateLocalNotificationPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (!mounted) return;
    setState(() {
      if (key == solNotificationHapticsEnabledKey) {
        _vibrateOnPresence = value;
      } else if (key == solNotificationSoundEnabledKey) {
        _playSolChimes = value;
      } else if (key == solNotificationBannersEnabledKey) {
        _showActiveRoomBanners = value;
      }
    });
  }

  Future<void> _pickQuietHour({required bool isStart}) async {
    final prefs = _profile?.preferences;
    if (prefs == null) return;
    final initialHour = isStart ? prefs.quietHoursStart : prefs.quietHoursEnd;

    // Styled in Sol dark/amber dialog
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _amber,
              surface: _surfaceUp,
              onSurface: _cream,
              secondary: _amber,
            ),
            dialogBackgroundColor: _surface,
          ),
          child: child!,
        );
      },
    );
    if (selected == null) return;
    await _updatePref(
      isStart ? 'quiet_hours_start' : 'quiet_hours_end',
      selected.hour,
    );
  }

  Future<void> _resetRelationship() async {
    final pair = _profile?.selectedPair;
    if (pair == null) return;

    // Level 1 Confirmation
    final confirmed = await _confirm(
      title: 'start this thread over?',
      body:
          'this clears the private continuity built with ${pair.name} and starts the thread fresh.',
      confirmLabel: 'start over',
    );
    if (!confirmed) return;

    // Level 2 Multi-level Confirmation for security
    if (!mounted) return;
    final finalConfirmed = await _confirm(
      title: 'are you absolutely sure?',
      body:
          'all semantic logs and relationship parameters with ${pair.name} will be permanently wiped. this action is irreversible.',
      confirmLabel: 'permanently wipe thread',
      destructive: true,
    );
    if (!finalConfirmed) return;

    try {
      await ApiService.resetPairMemory(pair.pairId);
      await _load();
      _showSnack('${pair.name}\'s thread memory has been cleared.');
    } catch (e) {
      _showSnack('failed to reset thread memory.');
    }
  }

  Future<void> _deleteAccount() async {
    // Level 1 Confirmation
    final confirmed = await _confirm(
      title: 'delete your sol account?',
      body:
          'this removes your inbox, thread history, and saved settings across the entire app.',
      confirmLabel: 'delete account',
      destructive: true,
    );
    if (!confirmed) return;

    // Level 2 Multi-level Confirmation for security
    if (!mounted) return;
    final finalConfirmed = await _confirm(
      title: 'permanently delete data?',
      body:
          'every memory and fact index tied to your Google firebase credentials will be wiped. we cannot restore your companion threads.',
      confirmLabel: 'permanently delete',
      destructive: true,
    );
    if (!finalConfirmed) return;

    try {
      await ApiService.deleteAccount();
      await AuthService.signOut();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showSnack('failed to delete account.');
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
      barrierColor: _ink.withValues(alpha: 0.80),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AlertDialog(
            backgroundColor: _surfaceUp,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: _cream.withValues(alpha: 0.06), width: 0.6),
            ),
            title: Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                color: _cream.withValues(alpha: 0.92),
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            content: Text(
              body,
              style: GoogleFonts.jost(
                color: _sand.withValues(alpha: 0.72),
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
                    color: _sand.withValues(alpha: 0.55),
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
                        ? _destructiveRed.withValues(alpha: 0.85)
                        : _blue.withValues(alpha: 0.85),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          message,
          style: GoogleFonts.jost(color: _sand.withValues(alpha: 0.85), fontSize: 13),
        ),
      ),
    );
  }

  String _hourLabel(int hour) {
    final suffix = hour >= 12 ? 'pm' : 'am';
    final normalized = hour % 12 == 0 ? 12 : hour % 12;
    return '$normalized $suffix';
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
                        color: _blue.withValues(alpha: 0.70),
                        boxShadow: [
                          BoxShadow(
                            color: _blue.withValues(alpha: 0.55),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'SETTINGS',
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
                  'app preferences.',
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
    final pair = _profile?.selectedPair;
    final pairPrefs = _profile?.pairPreferences;

    if (prefs == null) return _buildErrorState();

    return FadeTransition(
      opacity: _fadeAnim,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        children: [
          // ── Quiet Hours Card ──
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
                  'quiet hours',
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withValues(alpha: 0.90),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'configure time brackets where companions will hold back proactive outreach to match your rhythm.',
                  style: GoogleFonts.jost(
                    color: _sand.withValues(alpha: 0.68),
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
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
          ),

          const SizedBox(height: 20),

          // ── Cadence Card ──
          if (pair != null && pairPrefs != null) ...[
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
                    'reach-out frequency',
                    style: GoogleFonts.plusJakartaSans(
                      color: _cream.withValues(alpha: 0.90),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'adjust how often ${pair.name} organically initiates encounters outside conversational threads.',
                    style: GoogleFonts.jost(
                      color: _sand.withValues(alpha: 0.68),
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildDropdownRow(
                    label: 'active cadence',
                    value: pairPrefs.proactiveCadence,
                    items: ['gentle', 'balanced', 'frequent'],
                    onChanged: (val) {
                      if (val != null) {
                        _updatePairPref(pair.pairId, 'proactive_cadence', val);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

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
                  'presence signals',
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withValues(alpha: 0.90),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'shape how companion arrivals feel while you are inside sol.',
                  style: GoogleFonts.jost(
                    color: _sand.withValues(alpha: 0.68),
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                _buildToggleRow(
                  title: 'Vibrate on companion presence',
                  subtitle: 'a delicate tactile pulse when someone reaches in.',
                  value: _vibrateOnPresence,
                  onChanged: (v) => _updateLocalNotificationPref(
                    solNotificationHapticsEnabledKey,
                    v,
                  ),
                ),
                _buildDivider(),
                _buildToggleRow(
                  title: 'Play Sol chime tones',
                  subtitle: 'soft system chimes for warm in-app arrivals.',
                  value: _playSolChimes,
                  onChanged: (v) => _updateLocalNotificationPref(
                    solNotificationSoundEnabledKey,
                    v,
                  ),
                ),
                _buildDivider(),
                _buildToggleRow(
                  title: 'Show banners while active in other rooms',
                  subtitle:
                      'surface companion messages when you are outside their thread.',
                  value: _showActiveRoomBanners,
                  onChanged: (v) => _updateLocalNotificationPref(
                    solNotificationBannersEnabledKey,
                    v,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Vault settings ──
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
                  'biometric vault security',
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withValues(alpha: 0.90),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                _buildToggleRow(
                  title: 'vault lock protection',
                  subtitle:
                      'require biometric credentials or fallback PIN on app startup.',
                  value: _vaultLocked,
                  onChanged: (v) async {
                    if (v) {
                      final hasPin = await BiometricService.hasVaultPin();
                      if (!hasPin) {
                        if (!mounted) return;
                        final setupSuccess =
                            await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (context) =>
                                const VaultScreen(mode: VaultMode.setup),
                          ),
                        );
                        if (setupSuccess == true) {
                          await BiometricService.setVaultEnabled(true);
                          _showSnack('vault security enabled.');
                          _load();
                        }
                      } else {
                        await BiometricService.setVaultEnabled(true);
                        _showSnack('vault security enabled.');
                        _load();
                      }
                    } else {
                      if (!mounted) return;
                      final verified = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (context) =>
                              const VaultScreen(mode: VaultMode.verify),
                        ),
                      );
                      if (verified == true) {
                        await BiometricService.setVaultEnabled(false);
                        _showSnack('vault security disabled.');
                        _load();
                      }
                    }
                  },
                ),
                if (_vaultLocked) ...[
                  _buildDivider(),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final success =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (context) => const VaultScreen(
                                    mode: VaultMode.changePin),
                              ),
                            );
                            if (success == true) {
                              _showSnack('security PIN changed.');
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _cream.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _cream.withValues(alpha: 0.08), width: 0.6),
                            ),
                            child: Center(
                              child: Text(
                                'change fallback PIN',
                                style: GoogleFonts.jost(
                                  color: _cream.withValues(alpha: 0.80),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Destructive Resets Panel (Redesigned with multi-level confirmation) ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF2A0E0E).withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _destructiveRed.withValues(alpha: 0.18),
                width: 0.6,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.report_problem_outlined,
                        size: 16, color: _destructiveRed.withValues(alpha: 0.80)),
                    const SizedBox(width: 8),
                    Text(
                      'danger parameter control',
                      style: GoogleFonts.plusJakartaSans(
                        color: _destructiveRed.withValues(alpha: 0.85),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'the triggers below modify secure databases and relationship vectors. operate with caution.',
                  style: GoogleFonts.jost(
                    color: _destructiveRed.withValues(alpha: 0.58),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _buildActionRow(
                  label: pair == null
                      ? 'no active thread'
                      : 'start ${pair.name}\'s thread over',
                  onTap: pair == null ? null : _resetRelationship,
                  enabled: pair != null,
                ),
                _buildDivider(isDestructive: true),
                _buildActionRow(
                  label: 'permanently delete sol account',
                  onTap: _deleteAccount,
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
                _blue.withValues(alpha: 0.62),
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

  Widget _buildDropdownRow({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    // Defensive check to avoid Flutter DropdownButton value assertion crashes
    final safeValue = items.contains(value) ? value : 'balanced';
    return Container(
      decoration: BoxDecoration(
        color: _surfaceUp.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _cream.withValues(alpha: 0.07),
          width: 0.6,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          dropdownColor: _surfaceUp,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: _sand.withValues(alpha: 0.45),
          ),
          isExpanded: true,
          style: GoogleFonts.jost(
            color: _cream.withValues(alpha: 0.82),
            fontSize: 13.5,
          ),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: GoogleFonts.jost(
                  color: _cream.withValues(alpha: 0.82),
                  fontSize: 13.5,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required String label,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final active = enabled && onTap != null;
    final textCol = _destructiveRed.withValues(alpha: active ? 0.85 : 0.30);
    return InkWell(
      onTap: active ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.jost(
                color: textCol,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: textCol,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider({bool isDestructive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Container(
        height: 0.4,
        color: isDestructive
            ? _destructiveRed.withValues(alpha: 0.12)
            : _cream.withValues(alpha: 0.06),
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surfaceUp.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cream.withValues(alpha: 0.06), width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.jost(color: _dusty, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: GoogleFonts.plusJakartaSans(
                color: _sand,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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
