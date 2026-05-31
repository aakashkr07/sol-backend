import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class OnboardingService {
  OnboardingService._();

  static const String _prefix = 'sol_onboarding_complete';
  static void Function()? onboardingSuccessCallback;

  static String _keyForUser(String userId) => '$_prefix:$userId';

  static Future<bool> isComplete(String userId) async {
    try {
      // 1. Live server verification
      final serverComplete = await ApiService.checkOnboardingStatus();
      
      // 2. Sync to local cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyForUser(userId), serverComplete);
      
      return serverComplete;
    } catch (e) {
      // 3. Graceful fallback on network failure or offline state
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyForUser(userId)) ?? false;
    }
  }

  static Future<void> markComplete(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyForUser(userId), true);
    onboardingSuccessCallback?.call();
  }

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForUser(userId));
  }
}
