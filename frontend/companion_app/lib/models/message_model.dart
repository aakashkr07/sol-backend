// =============================================================================
// models/message_model.dart — Message Data Model
// =============================================================================
//
// PURPOSE:
//   The data class that represents a single chat message in Flutter.
//   Used by: chat_screen.dart (state), message_bubble.dart (display).
//
// WHY A SEPARATE MODEL:
//   Clean separation between data and UI. If you add fields later
//   (e.g., reactions, read receipts, emotion tags), you add them here
//   without touching the widgets.
// =============================================================================

enum MessageRole { user, assistant }

class Message {
  /// Unique ID for this message (used as widget key for efficient list updates)
  final String id;

  /// Who sent it — user or Nova (assistant)
  final MessageRole role;

  /// The actual text content
  final String content;

  /// When this message was created (shown on tap)
  final DateTime timestamp;

  /// Whether this message should animate in (true for new, false for history)
  final bool isNew;

  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isNew = false,
  });

  /// Create from API response (Nova's reply)
  factory Message.fromNova(String content) {
    return Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: content,
      timestamp: DateTime.now(),
      isNew: true,
    );
  }

  /// Create from user input
  factory Message.fromUser(String content) {
    return Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
      isNew: true,
    );
  }

  Message copyWith({bool? isNew}) {
    return Message(
      id: id,
      role: role,
      content: content,
      timestamp: timestamp,
      isNew: isNew ?? this.isNew,
    );
  }
}
