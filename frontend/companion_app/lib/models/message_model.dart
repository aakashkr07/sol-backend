enum MessageRole { user, assistant }

enum MessageStatus { sending, sent, delivered, read, failed }

class Message {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isNew;
  final MessageStatus status;
  final bool startsNewGroup;
  final int? parentMessageId;

  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isNew = false,
    this.status = MessageStatus.read,
    this.startsNewGroup = false,
    this.parentMessageId,
  });

  bool get isUser => role == MessageRole.user;
  String get text => content;

  String get timeLabel {
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final suffix = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  factory Message.fromCompanion(String content, {bool startsNewGroup = false, int? parentMessageId}) {
    return Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: content,
      timestamp: DateTime.now(),
      isNew: true,
      status: MessageStatus.read,
      startsNewGroup: startsNewGroup,
      parentMessageId: parentMessageId,
    );
  }

  factory Message.fromNova(String content) => Message.fromCompanion(content);

  factory Message.fromHistory({
    required String role,
    required String content,
    required String? createdAt,
    int? parentMessageId,
  }) {
    final parsedTimestamp = DateTime.tryParse(createdAt ?? '');
    return Message(
      id: '${role}_${createdAt ?? DateTime.now().microsecondsSinceEpoch}_${content.hashCode}',
      role: role == 'user' ? MessageRole.user : MessageRole.assistant,
      content: content,
      timestamp: parsedTimestamp?.toLocal() ?? DateTime.now(),
      isNew: false,
      status: MessageStatus.read,
      startsNewGroup: false,
      parentMessageId: parentMessageId,
    );
  }

  factory Message.fromUser(String content, {int? parentMessageId}) {
    return Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
      isNew: true,
      status: MessageStatus.sending,
      startsNewGroup: false,
      parentMessageId: parentMessageId,
    );
  }

  Message copyWith({
    String? content,
    DateTime? timestamp,
    bool? isNew,
    MessageStatus? status,
    bool? startsNewGroup,
    int? parentMessageId,
  }) {
    return Message(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isNew: isNew ?? this.isNew,
      status: status ?? this.status,
      startsNewGroup: startsNewGroup ?? this.startsNewGroup,
      parentMessageId: parentMessageId ?? this.parentMessageId,
    );
  }
}
