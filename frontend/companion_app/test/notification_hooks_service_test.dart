import 'package:companion_app/services/notification_hooks_service.dart';
import 'package:companion_app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.onNotificationReceived.value = null;
  });

  group('NotificationHooksService Tests', () {
    test('broadcasts parsed notifications via ValueNotifier', () async {
      SolNotification? receivedNotification;

      NotificationHooksService.onNotificationReceived.addListener(() {
        receivedNotification = NotificationHooksService.onNotificationReceived.value;
      });

      final mockPayload = {
        'notification_id': 'notif-987',
        'sender_name': 'Nova',
        'message_preview': 'still here?',
        'pair_id': 'user123::nova',
        'companion_id': 'nova',
        'event_id': 'evt_987',
        'reason': 'passive_thought',
      };

      await NotificationHooksService.mockIncomingNotification(mockPayload);

      expect(receivedNotification, isNotNull);
      expect(receivedNotification!.id, 'notif-987');
      expect(receivedNotification!.sender, 'Nova');
      expect(receivedNotification!.messagePreview, 'still here?');
      expect(receivedNotification!.chatId, 'nova');
      expect(receivedNotification!.payload['reason'], 'passive_thought');
    });

    test('exposes setForegroundNotificationOptions safely', () async {
      // Should not throw or crash even if Firebase is not fully configured in tests
      expect(
        () => NotificationHooksService.setForegroundNotificationOptions(active: true),
        returnsNormally,
      );
    });
  });
}
