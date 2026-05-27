import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  OnboardingService._();

  static const String _prefix = 'sol_onboarding_complete';

  static String _keyForUser(String userId) => '$_prefix:$userId';

  static Future<bool> isComplete(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyForUser(userId)) ?? false;
  }

  static Future<void> markComplete(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyForUser(userId), true);
  }

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForUser(userId));
  }
}
