// =============================================================================
// vault_screen.dart — Sol Vault Lock and PIN Verification Screen
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/biometric_service.dart';
import '../widgets/atmosphere_background.dart';

// Sol Palette
const Color _bgDeep = Color(0xFF080A0E);
const Color _surface = Color(0xFF10131A);
const Color _blue = Color(0xFF7DA2FF);
const Color _violet = Color(0xFFA78BFA);
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);
const Color _ink = Color(0xFF060810);


enum VaultMode {
  verify,      // App startup verification
  setup,       // First-time PIN setup
  changePin,   // Changing existing PIN
}

class VaultScreen extends StatefulWidget {
  final VaultMode mode;
  final VoidCallback? onSuccess;

  const VaultScreen({
    super.key,
    required this.mode,
    this.onSuccess,
  });

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen>
    with SingleTickerProviderStateMixin {
  // Screen state
  String _inputBuffer = '';
  String _titleText = 'authenticate to access your vault';
  String? _subtextText;
  bool _isBiometricsAvailable = false;
  bool _hasCheckedBiometrics = false;

  // Setup/Change specific flow states
  String _firstInputPin = '';
  bool _hasVerifiedCurrentPin = false;
  int _setupStep = 1; // 1 = choose, 2 = confirm


  // Animation for shaking on error
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;
  bool _isShaking = false;

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
          _inputBuffer = '';
        });
        _shakeCtrl.reset();
      }
    });

    // ── Mode resolution and biometric trigger ───────────────────────────────
    _initializeFlow();
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializeFlow() async {
    final bioAvail = await BiometricService.canAuthenticate();
    if (!mounted) return;
    setState(() {
      _isBiometricsAvailable = bioAvail;
    });

    if (widget.mode == VaultMode.setup) {
      setState(() {
        _titleText = 'choose a 4-digit vault PIN';
        _subtextText = 'this acts as a fallback for lock protection.';
      });
    } else if (widget.mode == VaultMode.changePin) {
      setState(() {
        _titleText = 'enter your current PIN';
        _subtextText = 'verify your identity to proceed.';
      });
    } else {
      // Default: verify. Trigger biometrics automatically once
      setState(() {
        _titleText = 'authenticate to access your vault';
        _subtextText = bioAvail ? 'Face ID / Fingerprint or PIN fallback' : 'enter your 4-digit PIN';
      });

      if (bioAvail && !_hasCheckedBiometrics) {
        _hasCheckedBiometrics = true;
        // Small delay to let the screen transition finish smoothly before native overlay shows
        Future.delayed(const Duration(milliseconds: 350), () {
          _triggerBiometrics();
        });
      }
    }
  }

  Future<void> _triggerBiometrics() async {
    if (!_isBiometricsAvailable) return;
    final authenticated = await BiometricService.authenticate();
    if (!mounted) return;
    if (authenticated) {
      _handleSuccess();
    } else {
      setState(() {
        _subtextText = 'biometrics failed. enter PIN to access.';
      });
    }
  }

  void _handleSuccess() {
    if (widget.onSuccess != null) {
      widget.onSuccess!();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  void _triggerError(String errorText) {
    HapticFeedback.heavyImpact();
    setState(() {
      _isShaking = true;
      _subtextText = errorText;
    });
    _shakeCtrl.forward();
  }

  void _onKeyPress(String val) {
    if (_isShaking) return;
    if (_inputBuffer.length >= 4) return;

    HapticFeedback.lightImpact();
    setState(() {
      _inputBuffer += val;
    });

    if (_inputBuffer.length == 4) {
      // Wait slightly so the last dot fills in visually before verifying
      Future.delayed(const Duration(milliseconds: 180), () {
        _verifyInput();
      });
    }
  }

  void _onBackspace() {
    if (_isShaking || _inputBuffer.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _inputBuffer = _inputBuffer.substring(0, _inputBuffer.length - 1);
    });
  }

  Future<void> _verifyInput() async {
    final pin = _inputBuffer;

    if (widget.mode == VaultMode.setup) {
      if (_setupStep == 1) {
        // Choose step completed
        _firstInputPin = pin;
        setState(() {
          _setupStep = 2;
          _titleText = 'confirm your vault PIN';
          _subtextText = 're-enter your chosen 4-digit code.';
          _inputBuffer = '';
        });
      } else {
        // Confirm step completed
        if (pin == _firstInputPin) {
          await BiometricService.saveVaultPin(pin);
          await BiometricService.setVaultEnabled(true);
          _handleSuccess();
        } else {
          // Reset setup
          _setupStep = 1;
          _firstInputPin = '';
          _triggerError('PINs do not match. choose again.');
          setState(() {
            _titleText = 'choose a 4-digit vault PIN';
          });
        }
      }
    } else if (widget.mode == VaultMode.changePin) {
      if (!_hasVerifiedCurrentPin) {
        final verified = await BiometricService.verifyVaultPin(pin);
        if (verified) {
          setState(() {
            _hasVerifiedCurrentPin = true;
            _titleText = 'choose a new 4-digit PIN';
            _subtextText = 'enter your new security code.';
            _inputBuffer = '';
          });
        } else {
          _triggerError('incorrect current PIN. try again.');
        }
      } else {
        // Now in setting new PIN
        if (_setupStep == 1) {
          _firstInputPin = pin;
          setState(() {
            _setupStep = 2;
            _titleText = 'confirm your new PIN';
            _subtextText = 're-enter your new security code.';
            _inputBuffer = '';
          });
        } else {
          if (pin == _firstInputPin) {
            await BiometricService.saveVaultPin(pin);
            _handleSuccess();
          } else {
            _setupStep = 1;
            _firstInputPin = '';
            _triggerError('PINs do not match. choose again.');
            setState(() {
              _titleText = 'choose a new 4-digit PIN';
            });
          }
        }
      }
    } else {
      // Default: verify mode
      final verified = await BiometricService.verifyVaultPin(pin);
      if (verified) {
        _handleSuccess();
      } else {
        _triggerError('incorrect security code. try again.');
      }
    }
  }

  // ── Render Helpers ─────────────────────────────────────────────────────────

  Widget _buildKey(String label, {VoidCallback? customTap, IconData? icon}) {
    return _PINKeyButton(
      label: label,
      icon: icon,
      onTap: customTap ?? () => _onKeyPress(label),
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
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.mode != VaultMode.verify)
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(false),
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
                      )
                    else
                      const SizedBox(width: 38), // placeholder spacing
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
                          'SOL VAULT',
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

              // Title and feedback prompt
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    Text(
                      _titleText,
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
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _subtextText ?? '',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.jost(
                          color: _isShaking
                              ? const Color(0xFFF2B8A0)
                              : _sand.withValues(alpha: 0.55),
                          fontSize: 13,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 38),

              // ── 4 Indicator Dots ───────────────────────────────────────────
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
                    final isFilled = _inputBuffer.length > index;
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

              // ── PIN Pad Grid ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Table(
                  children: [
                    TableRow(
                      children: [
                        _buildKey('1'),
                        _buildKey('2'),
                        _buildKey('3'),
                      ],
                    ),
                    TableRow(
                      children: [
                        TableCell(child: const SizedBox(height: 16)),
                        TableCell(child: const SizedBox(height: 16)),
                        TableCell(child: const SizedBox(height: 16)),
                      ],
                    ),
                    TableRow(
                      children: [
                        _buildKey('4'),
                        _buildKey('5'),
                        _buildKey('6'),
                      ],
                    ),
                    TableRow(
                      children: [
                        TableCell(child: const SizedBox(height: 16)),
                        TableCell(child: const SizedBox(height: 16)),
                        TableCell(child: const SizedBox(height: 16)),
                      ],
                    ),
                    TableRow(
                      children: [
                        _buildKey('7'),
                        _buildKey('8'),
                        _buildKey('9'),
                      ],
                    ),
                    TableRow(
                      children: [
                        TableCell(child: const SizedBox(height: 16)),
                        TableCell(child: const SizedBox(height: 16)),
                        TableCell(child: const SizedBox(height: 16)),
                      ],
                    ),
                    TableRow(
                      children: [
                        // Left utility key: triggers biometrics if available, else blank/cancel
                        TableCell(
                          child: _isBiometricsAvailable
                              ? _buildKey(
                                  '',
                                  icon: Icons.fingerprint_rounded,
                                  customTap: _triggerBiometrics,
                                )
                              : const SizedBox.shrink(),
                        ),
                        _buildKey('0'),
                        // Right utility key: backspace
                        TableCell(
                          child: _buildKey(
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
        ),
      ),
    );
  }
}

// ── Inside-file micro-component for PIN Keys with nice press interactions ──

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
            width: 64,
            height: 64,
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
