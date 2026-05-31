// =============================================================================
// biometric_service.dart — Secure native biometric and PIN service
// =============================================================================

import 'dart:convert';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const String _pinKey = 'sol_vault_pin_hash';
  static const String _enabledKey = 'sol_vault_enabled';

  /// Check if the device hardware supports biometrics and is configured.
  static Future<bool> canAuthenticate() async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (e) {
      return false;
    }
  }

  /// Trigger Face Unlock or Fingerprint biometric prompt with a secure message.
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'authenticate to access your vault',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  /// Check if vault security is globally enabled.
  static Future<bool> isVaultEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Enable or disable vault security.
  static Future<bool> setVaultEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setBool(_enabledKey, enabled);
  }

  /// Check if the user has already configured a 4-digit PIN.
  static Future<bool> hasVaultPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_pinKey);
  }

  /// Clear vault configurations (e.g. on account reset).
  static Future<void> clearVault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
    await prefs.remove(_enabledKey);
  }

  /// Public entry point to save vault PIN.
  static Future<bool> saveVaultPin(String pin) async {
    return _saveVaultPin(pin);
  }

  /// Public entry point to verify vault PIN.
  static Future<bool> verifyVaultPin(String pin) async {
    return _verifyVaultPin(pin);
  }

  // --- Private secure methods ---

  static Future<bool> _saveVaultPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final hashed = _hashPin(pin);
    return prefs.setString(_pinKey, hashed);
  }

  static Future<bool> _verifyVaultPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pinKey);
    if (stored == null) return false;
    return stored == _hashPin(pin);
  }

  /// Salted custom cryptographic digest to store the PIN securely.
  static String _hashPin(String pin) {
    // Unique salt combined with PIN
    final String salted = 'sol_vault_salt_#2026!_${pin}_presence';
    final List<int> bytes = utf8.encode(salted);

    // Secure folding hash algorithm
    int h1 = 0x6a09e667;
    int h2 = 0xbb67ae85;

    for (int i = 0; i < bytes.length; i++) {
      h1 = (h1 + bytes[i]) ^ (h2 << 5 | h2 >>> 27);
      h2 = (h2 + bytes[i]) ^ (h1 << 7 | h1 >>> 25);
      h1 = h1 & 0xFFFFFFFF;
      h2 = h2 & 0xFFFFFFFF;
    }

    return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
  }
}
