import 'package:companion_app/models/message_model.dart';
import 'package:companion_app/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Message.fromUser creates a sending user message', () {
    final message = Message.fromUser('hello there');

    expect(message.isUser, isTrue);
    expect(message.text, 'hello there');
    expect(message.status, MessageStatus.sending);
  });

  testWidgets('MessageBubble renders user content and send state',
      (WidgetTester tester) async {
    final message = Message.fromUser('hello there').copyWith(
      status: MessageStatus.read,
      isNew: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF0A0E1A),
          body: SizedBox.shrink(),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0E1A),
          body: MessageBubble(
            message: message,
            isNew: false,
          ),
        ),
      ),
    );

    expect(find.text('hello there'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));
  });
}
