enum MessageRole { user, assistant }

enum MessageStatus { sending, sent, delivered, read, failed }

class Message {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isNew;
  final MessageStatus status;

  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isNew = false,
    this.status = MessageStatus.read,
  });

  bool get isUser => role == MessageRole.user;
  String get text => content;

  String get timeLabel {
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final suffix = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  factory Message.fromNova(String content) {
    return Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: content,
      timestamp: DateTime.now(),
      isNew: true,
      status: MessageStatus.read,
    );
  }

  factory Message.fromUser(String content) {
    return Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
      isNew: true,
      status: MessageStatus.sending,
    );
  }

  Message copyWith({
    String? content,
    DateTime? timestamp,
    bool? isNew,
    MessageStatus? status,
  }) {
    return Message(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isNew: isNew ?? this.isNew,
      status: status ?? this.status,
    );
  }
}
