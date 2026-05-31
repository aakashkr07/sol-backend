import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';

class NotificationHooksService {
  NotificationHooksService._();

  static bool _initialized = false;

  /// Global notifier that broadcasts FCM message data to active screens in real-time.
  static final ValueNotifier<Map<String, dynamic>?> onNotificationReceived =
      ValueNotifier<Map<String, dynamic>?>(null);

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
      );

      final token = await messaging.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await ApiService.registerDeviceToken(
          platform: defaultTargetPlatform.name.toLowerCase(),
          pushToken: token,
        );
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        if (token.trim().isEmpty) {
          return;
        }
        try {
          await ApiService.registerDeviceToken(
            platform: defaultTargetPlatform.name.toLowerCase(),
            pushToken: token,
          );
        } catch (_) {}
      });

      // Hook foreground message capture
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _handleMessage(message.data);
      });

      // Hook background message click / application open
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleMessage(message.data);
      });
    } catch (_) {
      // Notification hooks are optional; missing platform config should not break chat.
    }
  }

  static Future<void> setForegroundNotificationOptions({required bool active}) async {
    try {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: !active,
        badge: !active,
        sound: !active,
      );
    } catch (_) {}
  }

  /// Processes FCM data payloads, playing premium chimes and triggering micro-vibrations
  static void _handleMessage(Map<String, dynamic> data) {
    if (data.isEmpty) return;

    try {
      // Premium atmospheric Sol notification click sound & haptics
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();
    } catch (_) {}

    // Broadcast message to the inbox screen for real-time updates
    onNotificationReceived.value = data;
  }

  /// Exposes a mock trigger to easily test hooks, badging, and sounds in unit tests
  @visibleForTesting
  static void mockIncomingNotification(Map<String, dynamic> data) {
    _handleMessage(data);
  }
}
