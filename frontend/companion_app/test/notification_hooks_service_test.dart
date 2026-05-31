import 'package:companion_app/services/notification_hooks_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationHooksService Tests', () {
    test('broadcasts notifications via ValueNotifier', () {
      Map<String, dynamic>? receivedData;

      // Register listener
      NotificationHooksService.onNotificationReceived.addListener(() {
        receivedData = NotificationHooksService.onNotificationReceived.value;
      });

      final mockPayload = {
        'pair_id': 'user123::nova',
        'companion_id': 'nova',
        'event_id': 'evt_987',
        'reason': 'passive_thought',
      };

      // Mock receiving notification
      NotificationHooksService.mockIncomingNotification(mockPayload);

      // Verify the listener was triggered and received correct data
      expect(receivedData, isNotNull);
      expect(receivedData!['pair_id'], 'user123::nova');
      expect(receivedData!['companion_id'], 'nova');
      expect(receivedData!['event_id'], 'evt_987');
      expect(receivedData!['reason'], 'passive_thought');
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
