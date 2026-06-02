// =============================================================================
// memory_vault_screen.dart — Sol Secure Memory Vault
// =============================================================================

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../widgets/atmosphere_background.dart';

// Sol Palette
const Color _bgDeep = Color(0xFF080A0E);
const Color _surface = Color(0xFF10131A);
const Color _surfaceUp = Color(0xFF141720);
const Color _blue = Color(0xFF7DA2FF);
const Color _violet = Color(0xFFA78BFA);
const Color _amber = Color(0xFFF2B8A0);
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);
const Color _ink = Color(0xFF060810);
const Color _destructiveRed = Color(0xFFE07070);

class MemoryVaultScreen extends StatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  State<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends State<MemoryVaultScreen>
    with TickerProviderStateMixin {
  // Authentication states
  bool _isAuthenticated = false;
  bool _isAuthenticatingBiometrics = false;
  bool _isBiometricsAvailable = false;
  String _pinInput = '';
  bool _isShaking = false;
  String _lockTitle = 'authenticate to access your vault';
  String _lockSubtext = 'Face ID / Fingerprint or PIN fallback';

  // Animation controller for PIN shake error
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  // Main UI Data States
  List<CompanionSummary> _pairs = const [];
  CompanionSummary? _selectedPair;
  UserProfileResponse? _selectedPairProfile;
  bool _isLoadingPairs = true;
  bool _isLoadingDetails = false;
  String? _pairsError;
  String? _detailsError;

  // Hub Navigation
  int _selectedTab = 0; // 0 = metrics., 1 = facts., 2 = moments., 3 = stats.

  @override
  void initState() {
    super.initState();

    // ── Shake animation setup ───────────────────────────────────────────────
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 4.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 4.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeIn));

    _shakeCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isShaking = false;
          _pinInput = '';
        });
        _shakeCtrl.reset();
      }
    });

    // Start secure biometric/PIN verification sequence
    _checkVaultAuthentication();
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ── Authentication Engine ──────────────────────────────────────────────────

  Future<void> _checkVaultAuthentication() async {
    final bioAvail = await BiometricService.canAuthenticate();
    setState(() {
      _isBiometricsAvailable = bioAvail;
      _lockSubtext = bioAvail
          ? 'Face ID / Fingerprint or PIN fallback'
          : 'enter your 4-digit PIN';
    });

    if (bioAvail) {
      _triggerBiometrics();
    }
  }

  Future<void> _triggerBiometrics() async {
    setState(() {
      _isAuthenticatingBiometrics = true;
    });

    final authenticated = await BiometricService.authenticate();
    if (!mounted) return;

    if (authenticated) {
      setState(() {
        _isAuthenticated = true;
        _isAuthenticatingBiometrics = false;
      });
      _loadInitialData();
    } else {
      setState(() {
        _isAuthenticatingBiometrics = false;
        _lockSubtext = 'biometrics failed. enter fallback PIN.';
      });
    }
  }

  void _onKeyPress(String digit) {
    if (_isShaking || _pinInput.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pinInput += digit;
    });

    if (_pinInput.length == 4) {
      Future.delayed(const Duration(milliseconds: 180), () {
        _verifyPIN();
      });
    }
  }

  void _onBackspace() {
    if (_isShaking || _pinInput.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pinInput = _pinInput.substring(0, _pinInput.length - 1);
    });
  }

  Future<void> _verifyPIN() async {
    final correct = await BiometricService.verifyVaultPin(_pinInput);
    if (!mounted) return;

    if (correct) {
      setState(() {
        _isAuthenticated = true;
      });
      _loadInitialData();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _isShaking = true;
        _lockSubtext = 'incorrect security code. try again.';
      });
      _shakeCtrl.forward();
    }
  }

  // ── Data Loading & State Isolation ─────────────────────────────────────────

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingPairs = true;
      _pairsError = null;
    });

    try {
      final profile = await ApiService.getMyProfile();
      if (!mounted) return;

      if (profile == null || profile.pairs.isEmpty) {
        setState(() {
          _pairsError = 'no active companion connections found.';
          _isLoadingPairs = false;
        });
        return;
      }

      setState(() {
        _pairs = profile.pairs;
        // Default to primary pair or first pair
        _selectedPair = profile.selectedPair ?? profile.pairs.first;
        _isLoadingPairs = false;
      });

      if (_selectedPair != null) {
        _loadCompanionDetails(_selectedPair!.pairId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pairsError = 'could not connect to memory registry. tap to retry.';
          _isLoadingPairs = false;
        });
      }
    }
  }

  Future<void> _loadCompanionDetails(String pairId) async {
    setState(() {
      _isLoadingDetails = true;
      _detailsError = null;
    });

    try {
      final pairProfile = await ApiService.getMyProfile(pairId: pairId);
      if (!mounted) return;

      setState(() {
        _selectedPairProfile = pairProfile;
        _isLoadingDetails = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _detailsError = 'could not retrieve isolated memories. tap to retry.';
          _isLoadingDetails = false;
        });
      }
    }
  }

  Future<void> _deleteMemory(String memoryId) async {
    final pairId = _selectedPair?.pairId;
    if (pairId == null) return;

    final confirmed = await _confirmDeleteMoment();
    if (!confirmed) return;

    try {
      await ApiService.deleteMemory(pairId, memoryId);
      _showSnack('moment erased from continuity indices.');
      _loadCompanionDetails(pairId);
    } catch (e) {
      _showSnack('failed to erase memory.');
    }
  }

  Future<bool> _confirmDeleteMoment() async {
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
              'erase this moment?',
              style: GoogleFonts.plusJakartaSans(
                color: _cream.withValues(alpha: 0.92),
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            content: Text(
              'this permanently wipes the memory chunk from your companion\'s vector continuity indices. this action is irreversible.',
              style: GoogleFonts.jost(
                color: _sand.withValues(alpha: 0.72),
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'keep',
                  style: GoogleFonts.jost(
                    color: _sand.withValues(alpha: 0.55),
                    fontSize: 13.5,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'erase permanently',
                  style: GoogleFonts.jost(
                    color: _destructiveRed.withValues(alpha: 0.85),
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

  // ── Gradient Generator ─────────────────────────────────────────────────────

  LinearGradient _getCompanionGradient(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('nova')) {
      return const LinearGradient(
        colors: [Color(0xFF2A3E6B), Color(0xFF5A3B82)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (lower.contains('atlas')) {
      return const LinearGradient(
        colors: [Color(0xFF6B4E2A), Color(0xFF3E3025)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    } else if (lower.contains('clara') || lower.contains('seraphina')) {
      return const LinearGradient(
        colors: [Color(0xFF5A2A3D), Color(0xFF2E2235)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    // Deterministic HSL gradient fallback
    final sum = name.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    final color1 = HSLColor.fromAHSL(1.0, (sum * 75) % 360, 0.35, 0.22).toColor();
    final color2 = HSLColor.fromAHSL(1.0, ((sum * 75) + 120) % 360, 0.30, 0.15).toColor();
    return LinearGradient(
      colors: [color1, color2],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  // ── Render Tree ────────────────────────────────────────────────────────────

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
          child: Stack(
            children: [
              // Main authenticated view
              if (_isAuthenticated) _buildAuthenticatedContent(),

              // Biometric loading state
              if (!_isAuthenticated && _isAuthenticatingBiometrics)
                _buildBiometricBreathingOverlay(),

              // PIN lockpad screen fallback
              if (!_isAuthenticated && !_isAuthenticatingBiometrics)
                _buildPinLockpadOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Breathing Biometric Overlay ────────────────────────────────────────────

  Widget _buildBiometricBreathingOverlay() {
    return Container(
      color: _bgDeep.withValues(alpha: 0.95),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Breathing animation container
            _BreathingRing(),
            const SizedBox(height: 32),
            Text(
              'unlocking your memory vault…',
              style: GoogleFonts.plusJakartaSans(
                color: _cream.withValues(alpha: 0.85),
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'gathering local presence signature.',
              style: GoogleFonts.jost(
                color: _sand.withValues(alpha: 0.45),
                fontSize: 12,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Fallback PIN Entry Lockpad ─────────────────────────────────────────────

  Widget _buildPinLockpadOverlay() {
    return Container(
      color: _bgDeep.withValues(alpha: 0.92),
      child: Column(
        children: [
          // Header balance
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
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
                      Icons.close_rounded,
                      size: 15,
                      color: _sand,
                    ),
                  ),
                ),
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
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'SECURE VAULT',
                      style: GoogleFonts.jost(
                        color: _sand.withValues(alpha: 0.58),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 38), // balancer
              ],
            ),
          ),

          const Spacer(flex: 3),

          // Title & text prompt
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                Text(
                  _lockTitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withValues(alpha: 0.92),
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _lockSubtext,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jost(
                    color: _isShaking ? _amber : _sand.withValues(alpha: 0.55),
                    fontSize: 13,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 38),

          // PIN indicator dots (animated shake)
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_shakeAnim.value, 0),
                child: child,
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final isFilled = _pinInput.length > index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled ? _blue.withValues(alpha: 0.85) : Colors.transparent,
                    border: Border.all(
                      color: isFilled ? _blue.withValues(alpha: 0.85) : _cream.withValues(alpha: 0.20),
                      width: 1.5,
                    ),
                    boxShadow: isFilled
                        ? [
                            BoxShadow(
                              color: _blue.withValues(alpha: 0.40),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                );
              }),
            ),
          ),

          const Spacer(flex: 3),

          // Keypad grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56),
            child: Table(
              children: [
                TableRow(
                  children: [
                    _buildPINPadKey('1'),
                    _buildPINPadKey('2'),
                    _buildPINPadKey('3'),
                  ],
                ),
                TableRow(
                  children: [
                    const TableCell(child: SizedBox(height: 16)),
                    const TableCell(child: SizedBox(height: 16)),
                    const TableCell(child: SizedBox(height: 16)),
                  ],
                ),
                TableRow(
                  children: [
                    _buildPINPadKey('4'),
                    _buildPINPadKey('5'),
                    _buildPINPadKey('6'),
                  ],
                ),
                TableRow(
                  children: [
                    const TableCell(child: SizedBox(height: 16)),
                    const TableCell(child: SizedBox(height: 16)),
                    const TableCell(child: SizedBox(height: 16)),
                  ],
                ),
                TableRow(
                  children: [
                    _buildPINPadKey('7'),
                    _buildPINPadKey('8'),
                    _buildPINPadKey('9'),
                  ],
                ),
                TableRow(
                  children: [
                    const TableCell(child: SizedBox(height: 16)),
                    const TableCell(child: SizedBox(height: 16)),
                    const TableCell(child: SizedBox(height: 16)),
                  ],
                ),
                TableRow(
                  children: [
                    TableCell(
                      child: _isBiometricsAvailable
                          ? _buildPINPadKey(
                              '',
                              icon: Icons.fingerprint_rounded,
                              customTap: _triggerBiometrics,
                            )
                          : const SizedBox.shrink(),
                    ),
                    _buildPINPadKey('0'),
                    TableCell(
                      child: _buildPINPadKey(
                        '',
                        icon: Icons.keyboard_backspace_rounded,
                        customTap: _onBackspace,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _buildPINPadKey(String label, {IconData? icon, VoidCallback? customTap}) {
    return _PINKeyButton(
      label: label,
      icon: icon,
      onTap: customTap ?? () => _onKeyPress(label),
    );
  }

  // ── Main Content Dashboard ─────────────────────────────────────────────────

  Widget _buildAuthenticatedContent() {
    return Column(
      children: [
        _buildContentHeader(),
        Expanded(child: _buildVaultBody()),
      ],
    );
  }

  Widget _buildContentHeader() {
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
              child: const Icon(Icons.arrow_back_rounded, size: 15, color: _sand),
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
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'MEMORIES',
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
                  'your memory vault.',
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
        ],
      ),
    );
  }

  Widget _buildVaultBody() {
    if (_isLoadingPairs) return _buildGatheringPresenceLoader();
    if (_pairsError != null) return _buildErrorState(_pairsError!, _loadInitialData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),

        // Companion Swipe Carousel
        _buildCompanionSelector(),

        const SizedBox(height: 16),

        // Divider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            height: 0.5,
            color: _cream.withValues(alpha: 0.06),
          ),
        ),

        const SizedBox(height: 16),

        // Hub Navigation Tabs
        _buildHubTabs(),

        const SizedBox(height: 18),

        // Tab Isolated Panel Content
        Expanded(
          child: _isLoadingDetails
              ? _buildGatheringPresenceLoader()
              : _detailsError != null
                  ? _buildErrorState(_detailsError!, () {
                      if (_selectedPair != null) {
                        _loadCompanionDetails(_selectedPair!.pairId);
                      }
                    })
                  : _buildSelectedTabContent(),
        ),
      ],
    );
  }

  // ── Swipeable Companion Selector ───────────────────────────────────────────

  Widget _buildCompanionSelector() {
    return SizedBox(
      height: 125,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: _pairs.length,
        itemBuilder: (context, index) {
          final companion = _pairs[index];
          final isSelected = _selectedPair?.pairId == companion.pairId;
          final gradient = _getCompanionGradient(companion.name);

          return GestureDetector(
            onTap: () {
              if (isSelected) return;
              HapticFeedback.selectionClick();
              setState(() {
                _selectedPair = companion;
                _selectedPairProfile = null;
              });
              _loadCompanionDetails(companion.pairId);
            },
            child: AnimatedScale(
              scale: isSelected ? 1.0 : 0.94,
              duration: const Duration(milliseconds: 180),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 175,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _surface.withValues(alpha: 0.85)
                      : _surface.withValues(alpha: 0.40),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? _blue.withValues(alpha: 0.45)
                        : _cream.withValues(alpha: 0.04),
                    width: isSelected ? 1.0 : 0.6,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _blue.withValues(alpha: 0.06),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    // Avatar Circle with Gradient
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: gradient,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: gradient.colors.first.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          companion.name.isNotEmpty
                              ? companion.name[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                            color: _cream.withValues(alpha: 0.92),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Info details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            companion.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: _cream.withValues(alpha: 0.90),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            companion.currentStage.toLowerCase(),
                            style: GoogleFonts.jost(
                              color: _stageColor(companion.currentStage),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${companion.totalMessages} messages',
                            style: GoogleFonts.jost(
                              color: _sand.withValues(alpha: 0.45),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _stageColor(String stage) {
    switch (stage.toLowerCase()) {
      case 'new':
        return _sand.withValues(alpha: 0.60);
      case 'warming':
        return _amber.withValues(alpha: 0.85);
      case 'settled':
        return _blue.withValues(alpha: 0.85);
      case 'close':
        return _violet.withValues(alpha: 0.85);
      case 'bonded':
        return const Color(0xFFC084FC); // Purple bonded
      default:
        return _sand;
    }
  }

  // ── Hub Selector Tabs ──────────────────────────────────────────────────────

  Widget _buildHubTabs() {
    final tabs = ['metrics.', 'facts.', 'moments.', 'stats.'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(tabs.length, (idx) {
          final isSelected = _selectedTab == idx;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedTab = idx;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? _cream.withValues(alpha: 0.04) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? _cream.withValues(alpha: 0.06) : Colors.transparent,
                  width: 0.6,
                ),
              ),
              child: Text(
                tabs[idx],
                style: GoogleFonts.jost(
                  color: isSelected ? _cream.withValues(alpha: 0.92) : _sand.withValues(alpha: 0.40),
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Hub Content Switcher ───────────────────────────────────────────────────

  Widget _buildSelectedTabContent() {
    if (_selectedPairProfile == null) return const SizedBox.shrink();

    switch (_selectedTab) {
      case 0:
        return _buildMetricsTab();
      case 1:
        return _buildFactsTab();
      case 2:
        return _buildMomentsTab();
      case 3:
        return _buildStatsTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Tab 0: Milestones & Metrics ──

  Widget _buildMetricsTab() {
    final snapshot = _selectedPairProfile!.relationshipState;
    final narrative = _selectedPairProfile!.currentNarrative;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      children: [
        // Grid metrics
        if (snapshot != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: _surface.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _cream.withValues(alpha: 0.05), width: 0.6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCircularMetric('closeness', snapshot.closeness, _blue),
                _buildCircularMetric('trust', snapshot.trust, _violet),
                _buildCircularMetric('openness', snapshot.openness, _amber),
                _buildCircularMetric('comfort', snapshot.comfort, const Color(0xFFC084FC)),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Narrative Summary
        if (narrative != null && narrative.isNotEmpty) ...[
          Text(
            'narrative connection.',
            style: GoogleFonts.jost(
              color: _sand.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
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
                Icon(
                  Icons.format_quote_rounded,
                  size: 20,
                  color: _amber.withValues(alpha: 0.50),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 10),
                  child: Text(
                    narrative,
                    style: GoogleFonts.jost(
                      color: _cream.withValues(alpha: 0.85),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w300,
                      fontStyle: FontStyle.italic,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    Icons.format_quote_rounded,
                    size: 20,
                    color: _amber.withValues(alpha: 0.50),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildCircularMetric(String label, double value, Color color) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Background thin track
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _cream.withValues(alpha: 0.04), width: 3),
              ),
            ),
            // Glow effect
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            // Progress track
            SizedBox(
              width: 58,
              height: 58,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 3.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.80)),
              ),
            ),
            // Inside percentage
            Text(
              '${(value * 100).toInt()}%',
              style: GoogleFonts.jost(
                color: _cream.withValues(alpha: 0.90),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.jost(
            color: _sand.withValues(alpha: 0.68),
            fontSize: 11,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  // ── Tab 1: What I Know (Extracted Facts) ──

  Widget _buildFactsTab() {
    final rows = _selectedPairProfile!.factRows;

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bubble_chart_outlined, size: 28, color: _sand.withValues(alpha: 0.20)),
              const SizedBox(height: 12),
              Text(
                'nothing cataloged yet.',
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'keep conversing to build presence continuity.',
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.30),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group active facts dynamically by category
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final category = row['category']?.toString().toLowerCase().trim() ?? 'general';
      grouped.putIfAbsent(category, () => []).add(row);
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      children: grouped.entries.map((group) {
        final categoryTitle = '${group.key}.';
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _cream.withValues(alpha: 0.04), width: 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category Eyebrow Header
              Text(
                categoryTitle,
                style: GoogleFonts.jost(
                  color: _blue.withValues(alpha: 0.70),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),

              // Fact list
              Column(
                children: group.value.map((fact) {
                  final key = fact['fact_key']?.toString().toLowerCase() ?? '';
                  final val = fact['fact_value']?.toString().toLowerCase() ?? '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _violet.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.jost(
                                color: _sand.withValues(alpha: 0.85),
                                fontSize: 13,
                                height: 1.45,
                              ),
                              children: [
                                TextSpan(
                                  text: '$key: ',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                TextSpan(
                                  text: val,
                                  style: TextStyle(color: _cream.withValues(alpha: 0.80)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Tab 2: Moments Vault ──

  Widget _buildMomentsTab() {
    final memories = _selectedPairProfile!.memories;

    if (memories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_outlined, size: 28, color: _sand.withValues(alpha: 0.20)),
              const SizedBox(height: 12),
              Text(
                'no core moments cataloged yet.',
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'moments are generated from deeply personal threads.',
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.30),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final moment = memories[index];
        final cleanTag = moment.emotionTag.toLowerCase().trim();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cream.withValues(alpha: 0.04), width: 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      moment.title.toLowerCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: _cream.withValues(alpha: 0.85),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Delete Moment Trash Trigger
                  GestureDetector(
                    onTap: () => _deleteMemory(moment.id),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: _destructiveRed.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                moment.content,
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.72),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Emotion Chip
                  if (cleanTag.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _blue.withValues(alpha: 0.16), width: 0.5),
                      ),
                      child: Text(
                        cleanTag,
                        style: GoogleFonts.jost(
                          color: _blue,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),

                  // Strength Weight bar
                  Row(
                    children: [
                      Text(
                        'strength: ',
                        style: GoogleFonts.jost(
                          color: _sand.withValues(alpha: 0.35),
                          fontSize: 9.5,
                        ),
                      ),
                      Container(
                        width: 44,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: _cream.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: moment.strength.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _violet.withValues(alpha: 0.70),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 3: Statistics ──

  Widget _buildStatsTab() {
    final companion = _selectedPairProfile!.selectedPair;
    if (companion == null) return const SizedBox.shrink();

    // Days known calculation fallback
    final daysKnown = _calculateDaysKnown();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _cream.withValues(alpha: 0.04), width: 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'presence metrics.',
                style: GoogleFonts.plusJakartaSans(
                  color: _cream.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _buildStatsRow('total sessions', '${companion.totalSessions} sessions'),
              _buildStatsDivider(),
              _buildStatsRow('total messages', '${companion.totalMessages} exchanged'),
              _buildStatsDivider(),
              _buildStatsRow('relationship stage', companion.currentStage.toLowerCase()),
              _buildStatsDivider(),
              _buildStatsRow('duration known', '$daysKnown days'),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStatsRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.jost(
            color: _sand.withValues(alpha: 0.65),
            fontSize: 13,
          ),
        ),
        Text(
          val,
          style: GoogleFonts.jost(
            color: _cream.withValues(alpha: 0.82),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        height: 0.4,
        color: _cream.withValues(alpha: 0.06),
      ),
    );
  }

  int _calculateDaysKnown() {
    final createdStr = _selectedPairProfile!.user['created_at']?.toString();
    if (createdStr == null) return 1;
    try {
      final created = DateTime.parse(createdStr);
      final diff = DateTime.now().difference(created).inDays;
      return diff <= 0 ? 1 : diff;
    } catch (_) {
      return 1;
    }
  }

  // ── Loading & Errors ──

  Widget _buildGatheringPresenceLoader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.0,
              valueColor: AlwaysStoppedAnimation<Color>(_violet.withValues(alpha: 0.65)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'gathering presence…',
            style: GoogleFonts.plusJakartaSans(
              color: _sand.withValues(alpha: 0.38),
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String msg, VoidCallback retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: GestureDetector(
          onTap: retry,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                msg,
                textAlign: TextAlign.center,
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.52),
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Inside-file micro-components ──

class _BreathingRing extends StatefulWidget {
  @override
  State<_BreathingRing> createState() => _BreathingRingState();
}

class _BreathingRingState extends State<_BreathingRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.70, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        final scale = _pulseAnim.value;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              border: Border.all(
                color: _blue.withValues(alpha: 0.65 * (2.0 - scale)),
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _blue.withValues(alpha: 0.20 * (2.0 - scale)),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PINKeyButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _PINKeyButton({
    required this.label,
    this.icon,
    required this.onTap,
  });

  @override
  State<_PINKeyButton> createState() => _PINKeyButtonState();
}

class _PINKeyButtonState extends State<_PINKeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _pressed ? _cream.withValues(alpha: 0.08) : _surface.withValues(alpha: 0.60),
              border: Border.all(
                color: _pressed ? _blue.withValues(alpha: 0.35) : _cream.withValues(alpha: 0.06),
                width: 0.6,
              ),
              boxShadow: _pressed
                  ? [
                      BoxShadow(
                        color: _blue.withValues(alpha: 0.12),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: widget.icon != null
                  ? Icon(
                      widget.icon,
                      size: 24,
                      color: _cream.withValues(alpha: 0.85),
                    )
                  : Text(
                      widget.label,
                      style: GoogleFonts.plusJakartaSans(
                        color: _cream.withValues(alpha: 0.92),
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
