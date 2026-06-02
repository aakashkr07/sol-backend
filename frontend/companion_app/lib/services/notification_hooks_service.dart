import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'notification_service.dart';

class NotificationHooksService {
  NotificationHooksService._();

  static bool _initialized = false;

  /// Global notifier that broadcasts parsed Sol notifications to active screens in real-time.
  static final ValueNotifier<SolNotification?> onNotificationReceived =
      NotificationService.onNotificationReceived;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(solFirebaseMessagingBackgroundHandler);

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
        _handleMessage(message, isForeground: true);
      });

      // Hook background message click / application open
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleMessage(message, isForeground: true);
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

  static void _handleMessage(RemoteMessage message, {required bool isForeground}) {
    if (message.data.isEmpty && message.notification == null) {
      return;
    }
    NotificationService.handleRemoteMessage(message, isForeground: isForeground);
  }

  /// Exposes a mock trigger to easily test hooks, badging, and sounds in unit tests
  @visibleForTesting
  static Future<void> mockIncomingNotification(Map<String, dynamic> data) {
    return NotificationService.handlePayload(data);
  }
}
