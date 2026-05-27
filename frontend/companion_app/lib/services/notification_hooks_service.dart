import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

class NotificationHooksService {
  NotificationHooksService._();

  static bool _initialized = false;

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
    } catch (_) {
      // Notification hooks are optional; missing platform config should not break chat.
    }
  }
}
