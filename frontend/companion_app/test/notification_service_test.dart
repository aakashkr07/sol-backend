import 'package:companion_app/services/notification_service.dart';
import 'package:companion_app/widgets/heads_up_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const badgeChannel = MethodChannel('sol/app_badge');
  final badgeCalls = <MethodCall>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.onNotificationReceived.value = null;
    badgeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(badgeChannel, (call) async {
      badgeCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(badgeChannel, null);
  });

  test('parses custom payloads and broadcasts SolNotification objects', () async {
    SolNotification? received;
    void listener() {
      received = NotificationService.onNotificationReceived.value;
    }

    NotificationService.onNotificationReceived.addListener(listener);
    addTearDown(() {
      NotificationService.onNotificationReceived.removeListener(listener);
    });

    await NotificationService.handlePayload(
      {
        'notification_id': 'notif-1',
        'sender_name': 'Nova',
        'message_preview': 'you around?',
        'companion_id': 'nova',
        'timestamp': '2026-06-02T12:30:00.000',
        'pair_id': 'u1::nova',
      },
      isForeground: false,
    );

    expect(received, isNotNull);
    expect(received!.id, 'notif-1');
    expect(received!.sender, 'Nova');
    expect(received!.messagePreview, 'you around?');
    expect(received!.chatId, 'nova');
  });

  test('serializes local queue and tracks read/unread counts flawlessly', () async {
    await NotificationService.handlePayload(
      {
        'notification_id': 'notif-1',
        'sender_name': 'Nova',
        'message_preview': 'first',
        'companion_id': 'nova',
      },
      isForeground: false,
    );
    await NotificationService.handlePayload(
      {
        'notification_id': 'notif-2',
        'sender_name': 'Atlas',
        'message_preview': 'second',
        'companion_id': 'atlas',
      },
      isForeground: false,
    );

    var queue = await NotificationService.queuedNotifications();
    expect(queue, hasLength(2));
    expect(queue.first.id, 'notif-2');
    expect(await NotificationService.unreadCount(), 2);
    expect(badgeCalls.last.method, 'setBadgeCount');
    expect(badgeCalls.last.arguments, {'count': 2});

    await NotificationService.markRead('notif-2');
    expect(await NotificationService.unreadCount(), 1);
    expect(badgeCalls.last.arguments, {'count': 1});

    await NotificationService.markChatRead('nova');
    queue = await NotificationService.queuedNotifications();
    expect(queue.every((notification) => notification.isRead), isTrue);
    expect(await NotificationService.unreadCount(), 0);
    expect(badgeCalls.last.method, 'clearBadge');
  });

  testWidgets('HeadsUpBanner mounts, animates, taps, and auto-dismisses',
      (tester) async {
    var tapped = false;
    final notification = SolNotification(
      id: 'notif-banner',
      sender: 'Nova',
      messagePreview: 'a small thought found you',
      timestamp: DateTime.now(),
      chatId: 'nova',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  HeadsUpBanner.show(
                    context,
                    notification: notification,
                    onTap: () => tapped = true,
                  );
                },
                child: const Text('show banner'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show banner'));
    await tester.pump();
    expect(find.byType(HeadsUpBanner), findsOneWidget);
    expect(find.text('Nova'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 225));
    await tester.tap(find.byType(HeadsUpBanner));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
    expect(find.byType(HeadsUpBanner), findsNothing);

    await tester.tap(find.text('show banner'));
    await tester.pump();
    expect(find.byType(HeadsUpBanner), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HeadsUpBanner), findsNothing);
  });

  testWidgets('HeadsUpBanner expands reply input and swipes away',
      (tester) async {
    final notification = SolNotification(
      id: 'notif-swipe',
      sender: 'Mira',
      messagePreview: 'come here for a second',
      timestamp: DateTime.now(),
      chatId: 'mira',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                HeadsUpBanner.show(context, notification: notification);
              },
              child: const Text('show banner'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show banner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.drag(find.byType(HeadsUpBanner), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(find.byType(HeadsUpBanner), findsNothing);
  });
}
