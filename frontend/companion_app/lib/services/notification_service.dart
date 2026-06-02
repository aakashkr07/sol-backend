import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'auth_service.dart';

const String solNotificationQueueKey = 'sol_notification_queue';
const String solNotificationSoundEnabledKey = 'sol_notification_sound_enabled';
const String solNotificationHapticsEnabledKey = 'sol_notification_haptics_enabled';
const String solNotificationBannersEnabledKey = 'sol_notification_banners_enabled';

@pragma('vm:entry-point')
Future<void> solFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  await NotificationService.handleRemoteMessage(message, isForeground: false);
}

class SolNotification {
  final String id;
  final String sender;
  final String messagePreview;
  final DateTime timestamp;
  final String chatId;
  final bool isRead;
  final Map<String, dynamic> payload;

  const SolNotification({
    required this.id,
    required this.sender,
    required this.messagePreview,
    required this.timestamp,
    required this.chatId,
    this.isRead = false,
    this.payload = const {},
  });

  factory SolNotification.fromRemoteMessage(RemoteMessage message) {
    return SolNotification.fromPayload(
      message.data,
      senderFallback: message.notification?.title,
      previewFallback: message.notification?.body,
      sentTimeFallback: message.sentTime,
    );
  }

  factory SolNotification.fromPayload(
    Map<String, dynamic> data, {
    String? senderFallback,
    String? previewFallback,
    DateTime? sentTimeFallback,
  }) {
    final normalized = data.map((key, value) => MapEntry(key, value?.toString() ?? ''));
    final id = _firstNonEmpty([
      normalized['notification_id'],
      normalized['id'],
    ]);
    final sender = _firstNonEmpty([
      normalized['sender_name'],
      normalized['sender'],
      normalized['title'],
      senderFallback,
      'Sol',
    ]);
    final preview = _firstNonEmpty([
      normalized['message_preview'],
      normalized['messagePreview'],
      normalized['body'],
      previewFallback,
      '',
    ]);
    final timestamp = DateTime.tryParse(_firstNonEmpty([
          normalized['timestamp'],
          normalized['sent_at'],
          normalized['created_at'],
        ])) ??
        sentTimeFallback ??
        DateTime.now();
    final chatId = _firstNonEmpty([
      normalized['companion_id'],
      normalized['chatId'],
      normalized['chat_id'],
      normalized['pair_id'],
      '',
    ]);

    return SolNotification(
      id: id,
      sender: sender,
      messagePreview: preview,
      timestamp: timestamp.toLocal(),
      chatId: chatId,
      payload: Map<String, dynamic>.from(data),
    );
  }

  factory SolNotification.fromJson(Map<String, dynamic> json) {
    return SolNotification(
      id: json['id'] as String? ?? '',
      sender: json['sender'] as String? ?? 'Sol',
      messagePreview: json['messagePreview'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      chatId: json['chatId'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? false,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender,
      'messagePreview': messagePreview,
      'timestamp': timestamp.toIso8601String(),
      'chatId': chatId,
      'isRead': isRead,
      'payload': payload,
    };
  }

  SolNotification copyWith({bool? isRead}) {
    return SolNotification(
      id: id,
      sender: sender,
      messagePreview: messagePreview,
      timestamp: timestamp,
      chatId: chatId,
      isRead: isRead ?? this.isRead,
      payload: payload,
    );
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }
}

class NotificationService {
  NotificationService._();

  static const MethodChannel _badgeChannel = MethodChannel('sol/app_badge');

  static final ValueNotifier<SolNotification?> onNotificationReceived =
      ValueNotifier<SolNotification?>(null);

  static Future<void> handleRemoteMessage(
    RemoteMessage message, {
    bool isForeground = true,
  }) async {
    final notification = SolNotification.fromRemoteMessage(message);
    await handleNotification(notification, isForeground: isForeground);
  }

  static Future<void> handlePayload(
    Map<String, dynamic> data, {
    bool isForeground = true,
    String? senderFallback,
    String? previewFallback,
  }) async {
    final notification = SolNotification.fromPayload(
      data,
      senderFallback: senderFallback,
      previewFallback: previewFallback,
    );
    await handleNotification(notification, isForeground: isForeground);
  }

  static Future<void> handleNotification(
    SolNotification notification, {
    bool isForeground = true,
  }) async {
    if (notification.id.isEmpty) {
      return;
    }

    await _storeNotification(notification);
    unawaited(sendDeliveryReceipt(notification.id));

    if (isForeground) {
      await _playArrivalFeedback();
    }

    onNotificationReceived.value = notification;
  }

  static Future<List<SolNotification>> queuedNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(solNotificationQueueKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SolNotification.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<int> unreadCount() async {
    final queue = await queuedNotifications();
    return queue.where((notification) => !notification.isRead).length;
  }

  static Future<void> markRead(String notificationId) async {
    final queue = await queuedNotifications();
    await _saveQueue([
      for (final notification in queue)
        notification.id == notificationId ? notification.copyWith(isRead: true) : notification,
    ]);
  }

  static Future<void> markChatRead(String chatId) async {
    final queue = await queuedNotifications();
    await _saveQueue([
      for (final notification in queue)
        notification.chatId == chatId ? notification.copyWith(isRead: true) : notification,
    ]);
  }

  static Future<void> markAllRead() async {
    final queue = await queuedNotifications();
    await _saveQueue([
      for (final notification in queue) notification.copyWith(isRead: true),
    ]);
  }

  static Future<bool> showBannersWhileActiveInOtherRooms() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(solNotificationBannersEnabledKey) ?? true;
  }

  static Future<void> playOutboundReplyFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(solNotificationHapticsEnabledKey) ?? true)) {
      return;
    }
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 48));
    await HapticFeedback.selectionClick();
  }

  static Future<void> sendDeliveryReceipt(String notificationId) async {
    String? token;
    try {
      token = await AuthService.getIdToken();
    } catch (_) {
      return;
    }
    if (token == null || token.trim().isEmpty) {
      return;
    }

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/me/notifications/${Uri.encodeComponent(notificationId)}/receipt',
    );
    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Sol notification receipt failed: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('Sol notification receipt error: $error');
    }
  }

  static Future<void> _storeNotification(SolNotification incoming) async {
    final queue = await queuedNotifications();
    final deduped = queue.where((notification) => notification.id != incoming.id).toList();
    deduped.insert(0, incoming);
    await _saveQueue(deduped.take(20).toList());
  }

  static Future<void> _saveQueue(List<SolNotification> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      solNotificationQueueKey,
      jsonEncode(queue.map((notification) => notification.toJson()).toList()),
    );
    await _updateAppBadgeCount(queue.where((notification) => !notification.isRead).length);
  }

  static Future<void> _updateAppBadgeCount(int count) async {
    try {
      if (count <= 0) {
        await _badgeChannel.invokeMethod<void>('clearBadge');
      } else {
        await _badgeChannel.invokeMethod<void>('setBadgeCount', {'count': count});
      }
    } on MissingPluginException {
      // Native badge hooks are optional; the local unread queue remains canonical.
    } catch (error) {
      debugPrint('Sol badge update failed: $error');
    }
  }

  static Future<void> _playArrivalFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = prefs.getBool(solNotificationSoundEnabledKey) ?? true;
    final hapticsEnabled = prefs.getBool(solNotificationHapticsEnabledKey) ?? true;

    if (soundEnabled) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
    if (hapticsEnabled) {
      await Future<void>.delayed(const Duration(milliseconds: 36));
      await HapticFeedback.lightImpact();
    }
  }
}
