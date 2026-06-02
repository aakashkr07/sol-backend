import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class ApiConfig {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'sol-backend-production.up.railway.app',
  );

  static String get baseUrl {
    final raw = _baseUrl.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    return 'https://$raw';
  }

  static String get chatUrl => '$baseUrl/api/chat';
  static String get sessionStartUrl => '$baseUrl/api/session/start';
  static String get myCompanionsUrl => '$baseUrl/api/companions/me';
  static String get myProfileUrl => '$baseUrl/api/me/profile';
  static String pairMemoriesUrl(String pairId) => '$baseUrl/api/me/pairs/$pairId/memories';
  static String pairPreferencesUrl(String pairId) => '$baseUrl/api/me/pairs/$pairId/preferences';
  static String pairResetUrl(String pairId) => '$baseUrl/api/me/pairs/$pairId/reset';
  static String pairMemoryDeleteUrl(String pairId, String memoryId) =>
      '$baseUrl/api/me/pairs/$pairId/memories/$memoryId';
  static String pairMemoryUrl(String pairId, String memoryId) =>
      '$baseUrl/api/me/pairs/$pairId/memories/$memoryId';
  static String pairFactUrl(String pairId, int factId) =>
      '$baseUrl/api/me/pairs/$pairId/facts/$factId';
  static String get preferencesUrl => '$baseUrl/api/me/preferences';
  static String get deviceTokenUrl => '$baseUrl/api/me/device-token';
  static String get proactivePendingUrl => '$baseUrl/api/me/proactive/pending';
  static String get onboardingCompleteUrl => '$baseUrl/api/onboarding/complete';
  static String get onboardingStatusUrl => '$baseUrl/api/onboarding/status';
  static String get healthUrl => '$baseUrl/health';

  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration chatTimeout = Duration(seconds: 75);
}

class ChatResponse {
  final String reply;
  final List<ChatBurst> bursts;
  final String conversationId;
  final int memoryCount;
  final String pairId;
  final String companionId;
  final String companionName;

  const ChatResponse({
    required this.reply,
    required this.bursts,
    required this.conversationId,
    required this.memoryCount,
    required this.pairId,
    required this.companionId,
    required this.companionName,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final replyText = json['reply'] as String? ?? '';
    final bursts = _parseBursts(json['bursts']);
    return ChatResponse(
      reply: replyText.isNotEmpty ? replyText : _combinedBurstText(bursts),
      bursts: bursts.isNotEmpty
          ? bursts
          : (replyText.trim().isEmpty ? const [] : [ChatBurst.single(replyText)]),
      conversationId: json['conversation_id'] as String,
      memoryCount: json['memory_count'] as int? ?? 0,
      pairId: json['pair_id'] as String? ?? '',
      companionId: json['companion_id'] as String? ?? '',
      companionName: json['companion_name'] as String? ?? 'Companion',
    );
  }
}

class SessionStartResponse {
  final String conversationId;
  final String? userName;
  final int sessionNumber;
  final int memoryCount;
  final bool isFirstSession;
  final String pairId;
  final String companionId;
  final String companionName;
  final String companionSummary;
  final String openingMessage;
  final List<ChatBurst> openingBursts;
  final bool resumedExisting;
  final List<SessionHistoryMessage> historyMessages;

  const SessionStartResponse({
    required this.conversationId,
    this.userName,
    required this.sessionNumber,
    required this.memoryCount,
    required this.isFirstSession,
    required this.pairId,
    required this.companionId,
    required this.companionName,
    required this.companionSummary,
    required this.openingMessage,
    required this.openingBursts,
    required this.resumedExisting,
    required this.historyMessages,
  });

  factory SessionStartResponse.fromJson(Map<String, dynamic> json) {
    final openingBursts = _parseBursts(json['opening_bursts']);
    final openingText = json['opening_message'] as String? ?? '';
    final resumedExisting = _asBool(json['resumed_existing'], false);
    return SessionStartResponse(
      conversationId: json['conversation_id'] as String,
      userName: json['user_name'] as String?,
      sessionNumber: json['session_number'] as int? ?? 1,
      memoryCount: json['memory_count'] as int? ?? 0,
      isFirstSession: json['is_first_session'] as bool? ?? true,
      pairId: json['pair_id'] as String? ?? '',
      companionId: json['companion_id'] as String? ?? '',
      companionName: json['companion_name'] as String? ?? 'Companion',
      companionSummary: json['companion_summary'] as String? ?? '',
      openingMessage: resumedExisting
          ? ''
          : openingText.ifEmpty(_combinedBurstText(openingBursts).ifEmpty('hey')),
      openingBursts: resumedExisting
          ? const []
          : (openingBursts.isNotEmpty
              ? openingBursts
              : [ChatBurst.single(openingText.ifEmpty('hey'))]),
      resumedExisting: resumedExisting,
      historyMessages: (json['history_messages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SessionHistoryMessage.fromJson)
          .toList(),
    );
  }
}

class SessionHistoryMessage {
  final int? id;
  final String role;
  final String content;
  final String createdAt;
  final int? parentMessageId;

  const SessionHistoryMessage({
    this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.parentMessageId,
  });

  factory SessionHistoryMessage.fromJson(Map<String, dynamic> json) {
    return SessionHistoryMessage(
      id: json['id'] as int?,
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      parentMessageId: json['parent_message_id'] as int?,
    );
  }
}

class ChatBurst {
  final String text;
  final int preBurstDelayMs;
  final int typingDurationMs;
  final String pauseIntensity;
  final bool isFollowUp;

  const ChatBurst({
    required this.text,
    required this.preBurstDelayMs,
    required this.typingDurationMs,
    required this.pauseIntensity,
    required this.isFollowUp,
  });

  factory ChatBurst.fromJson(Map<String, dynamic> json) {
    return ChatBurst(
      text: json['text'] as String? ?? '',
      preBurstDelayMs: json['pre_burst_delay_ms'] as int? ?? 320,
      typingDurationMs: json['typing_duration_ms'] as int? ?? 620,
      pauseIntensity: json['pause_intensity'] as String? ?? 'brief',
      isFollowUp: json['is_follow_up'] as bool? ?? false,
    );
  }

  factory ChatBurst.single(String text) {
    return ChatBurst(
      text: text,
      preBurstDelayMs: 260,
      typingDurationMs: 620,
      pauseIntensity: 'brief',
      isFollowUp: false,
    );
  }
}

class CompanionSummary {
  final String id;
  final String pairId;
  final String name;
  final String summary;
  final bool isPrimary;
  final int totalSessions;
  final String currentStage;
  final int totalMessages;

  const CompanionSummary({
    required this.id,
    required this.pairId,
    required this.name,
    required this.summary,
    required this.isPrimary,
    required this.totalSessions,
    required this.currentStage,
    required this.totalMessages,
  });

  factory CompanionSummary.fromJson(Map<String, dynamic> json) {
    return CompanionSummary(
      id: json['companion_id'] as String? ?? json['id'] as String? ?? '',
      pairId: json['pair_id'] as String? ?? '',
      name: json['companion_name'] as String? ?? json['name'] as String? ?? 'Companion',
      summary: json['companion_summary'] as String? ?? json['summary'] as String? ?? '',
      isPrimary: _asBool(json['is_primary'], false),
      totalSessions: json['total_sessions'] as int? ?? 0,
      currentStage: json['current_stage'] as String? ?? 'new',
      totalMessages: json['total_messages'] as int? ?? 0,
    );
  }
}

class RelationshipStateSnapshot {
  final double closeness;
  final double trust;
  final double openness;
  final double comfort;
  final double rhythm;
  final double topicFamiliarity;
  final String stage;

  const RelationshipStateSnapshot({
    required this.closeness,
    required this.trust,
    required this.openness,
    required this.comfort,
    required this.rhythm,
    required this.topicFamiliarity,
    required this.stage,
  });

  factory RelationshipStateSnapshot.fromJson(Map<String, dynamic> json) {
    return RelationshipStateSnapshot(
      closeness: (json['closeness'] as num?)?.toDouble() ?? 0,
      trust: (json['trust'] as num?)?.toDouble() ?? 0,
      openness: (json['openness'] as num?)?.toDouble() ?? 0,
      comfort: (json['comfort'] as num?)?.toDouble() ?? 0,
      rhythm: (json['rhythm'] as num?)?.toDouble() ?? 0,
      topicFamiliarity: (json['topic_familiarity'] as num?)?.toDouble() ?? 0,
      stage: json['stage'] as String? ?? 'new',
    );
  }
}

class UserPreferences {
  final bool allowMemoryStorage;
  final bool showMemoryOverview;
  final bool allowProactiveMessages;
  final bool allowPushNotifications;
  final int quietHoursStart;
  final int quietHoursEnd;
  final bool allowSensitiveProactive;

  const UserPreferences({
    required this.allowMemoryStorage,
    required this.showMemoryOverview,
    required this.allowProactiveMessages,
    required this.allowPushNotifications,
    required this.quietHoursStart,
    required this.quietHoursEnd,
    required this.allowSensitiveProactive,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      allowMemoryStorage: _asBool(json['allow_memory_storage'], true),
      showMemoryOverview: _asBool(json['show_memory_overview'], true),
      allowProactiveMessages: _asBool(json['allow_proactive_messages'], true),
      allowPushNotifications: _asBool(json['allow_push_notifications'], true),
      quietHoursStart: json['quiet_hours_start'] as int? ?? 23,
      quietHoursEnd: json['quiet_hours_end'] as int? ?? 8,
      allowSensitiveProactive: _asBool(json['allow_sensitive_proactive'], true),
    );
  }
}

class PairPreferences {
  final bool proactiveEnabled;
  final String proactiveCadence;
  final bool proactiveEmotionalCallbacksEnabled;

  const PairPreferences({
    required this.proactiveEnabled,
    required this.proactiveCadence,
    required this.proactiveEmotionalCallbacksEnabled,
  });

  factory PairPreferences.fromPairJson(Map<String, dynamic> json) {
    return PairPreferences(
      proactiveEnabled: _asBool(json['proactive_enabled'], true),
      proactiveCadence: json['proactive_cadence'] as String? ?? 'balanced',
      proactiveEmotionalCallbacksEnabled: _asBool(
        json['proactive_emotional_callbacks_enabled'],
        true,
      ),
    );
  }
}

class MemoryEntry {
  final String id;
  final String title;
  final String content;
  final String emotionTag;
  final double emotionalWeight;
  final double strength;
  final bool archived;
  final String createdAt;

  const MemoryEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.emotionTag,
    required this.emotionalWeight,
    required this.strength,
    required this.archived,
    required this.createdAt,
  });

  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    return MemoryEntry(
      id: json['chroma_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled moment',
      content: json['content'] as String? ?? '',
      emotionTag: json['emotion_tag'] as String? ?? '',
      emotionalWeight: (json['emotional_weight'] as num?)?.toDouble() ?? 0,
      strength: (json['strength'] as num?)?.toDouble() ?? 0,
      archived: json['archived'] == 1 || json['archived'] == true,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class UserProfileResponse {
  final Map<String, dynamic> user;
  final UserPreferences preferences;
  final CompanionSummary? selectedPair;
  final PairPreferences? pairPreferences;
  final RelationshipStateSnapshot? relationshipState;
  final Map<String, String> whatSolKnows;
  final List<Map<String, dynamic>> factRows;
  final List<Map<String, dynamic>> factConflicts;
  final List<MemoryEntry> memories;
  final int memoryCount;
  final String? currentNarrative;
  final List<CompanionSummary> pairs;

  const UserProfileResponse({
    required this.user,
    required this.preferences,
    required this.selectedPair,
    required this.pairPreferences,
    required this.relationshipState,
    required this.whatSolKnows,
    required this.factRows,
    required this.factConflicts,
    required this.memories,
    required this.memoryCount,
    required this.currentNarrative,
    required this.pairs,
  });

  factory UserProfileResponse.fromJson(Map<String, dynamic> json) {
    final selectedPairJson = json['selected_pair'] as Map<String, dynamic>?;
    final selectedPair =
        selectedPairJson == null ? null : CompanionSummary.fromJson(selectedPairJson);
    final relationshipJson = json['relationship_state'] as Map<String, dynamic>?;
    return UserProfileResponse(
      user: json['user'] as Map<String, dynamic>? ?? const {},
      preferences: UserPreferences.fromJson(
        json['preferences'] as Map<String, dynamic>? ?? const {},
      ),
      selectedPair: selectedPair,
      pairPreferences:
          selectedPairJson == null ? null : PairPreferences.fromPairJson(selectedPairJson),
      relationshipState: relationshipJson == null
          ? null
          : RelationshipStateSnapshot.fromJson(relationshipJson),
      whatSolKnows: (json['what_sol_knows'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, value.toString())),
      factRows: (json['fact_rows'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      factConflicts: (json['fact_conflicts'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      memories: (json['memories'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MemoryEntry.fromJson)
          .toList(),
      memoryCount: json['memory_count'] as int? ?? 0,
      currentNarrative:
          (json['current_narrative'] as Map<String, dynamic>?)?['summary'] as String?,
      pairs: (json['pairs'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CompanionSummary.fromJson)
          .toList(),
    );
  }
}

class PendingProactiveEvent {
  final String id;
  final String pairId;
  final String conversationId;
  final String companionName;
  final String reason;
  final List<ChatBurst> bursts;

  const PendingProactiveEvent({
    required this.id,
    required this.pairId,
    required this.conversationId,
    required this.companionName,
    required this.reason,
    required this.bursts,
  });

  factory PendingProactiveEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? const {};
    return PendingProactiveEvent(
      id: json['id'] as String? ?? '',
      pairId: json['pair_id'] as String? ?? '',
      conversationId:
          json['conversation_id'] as String? ?? payload['conversation_id'] as String? ?? '',
      companionName: payload['companion_name'] as String? ?? 'Companion',
      reason: json['reason'] as String? ?? payload['reason'] as String? ?? 'presence',
      bursts: _parseBursts(payload['bursts']),
    );
  }
}

class MyCompanionsResponse {
  final String? userName;
  final CompanionSummary? primaryCompanion;
  final List<CompanionSummary> pairs;
  final List<CompanionSummary> availableCompanions;
  final List<InboxEntrySummary> inboxEntries;

  const MyCompanionsResponse({
    required this.userName,
    required this.primaryCompanion,
    required this.pairs,
    required this.availableCompanions,
    required this.inboxEntries,
  });

  factory MyCompanionsResponse.fromJson(Map<String, dynamic> json) {
    final primaryJson = json['primary_pair'] as Map<String, dynamic>?;
    final pairList = (json['pairs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanionSummary.fromJson)
        .toList();
    final available = (json['available_companions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CompanionSummary.fromJson)
        .toList();

    return MyCompanionsResponse(
      userName: json['user_name'] as String?,
      primaryCompanion: primaryJson == null ? null : CompanionSummary.fromJson(primaryJson),
      pairs: pairList,
      availableCompanions: available,
      inboxEntries: (json['inbox_entries'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(InboxEntrySummary.fromJson)
          .toList(),
    );
  }
}

class InboxEntrySummary {
  final String entryKind;
  final String pairId;
  final String companionId;
  final String companionName;
  final String companionSummary;
  final String previewText;
  final String previewAt;
  final String statusText;
  final String? currentConversationId;
  final bool isPrimary;
  final bool isDiscovered;
  final int unreadCount;
  final String latestRole;
  final bool waitingOnUser;
  final String socialPresence;
  final String arrivalHint;
  final String relationshipStage;
  final int totalSessions;

  const InboxEntrySummary({
    required this.entryKind,
    required this.pairId,
    required this.companionId,
    required this.companionName,
    required this.companionSummary,
    required this.previewText,
    required this.previewAt,
    required this.statusText,
    required this.currentConversationId,
    required this.isPrimary,
    required this.isDiscovered,
    required this.unreadCount,
    required this.latestRole,
    required this.waitingOnUser,
    required this.socialPresence,
    required this.arrivalHint,
    required this.relationshipStage,
    required this.totalSessions,
  });

  bool get isArrival => entryKind == 'arrival';
  bool get hasUnread => unreadCount > 0;

  DateTime? get previewDateTime => DateTime.tryParse(previewAt)?.toLocal();

  factory InboxEntrySummary.fromJson(Map<String, dynamic> json) {
    return InboxEntrySummary(
      entryKind: json['entry_kind'] as String? ?? 'thread',
      pairId: json['pair_id'] as String? ?? '',
      companionId: json['companion_id'] as String? ?? '',
      companionName: json['companion_name'] as String? ?? 'Companion',
      companionSummary: json['companion_summary'] as String? ?? '',
      previewText: json['preview_text'] as String? ?? '',
      previewAt: json['preview_at'] as String? ?? '',
      statusText: json['status_text'] as String? ?? '',
      currentConversationId: json['current_conversation_id'] as String?,
      isPrimary: _asBool(json['is_primary'], false),
      isDiscovered: _asBool(json['is_discovered'], true),
      unreadCount: json['unread_count'] as int? ?? 0,
      latestRole: json['latest_role'] as String? ?? 'assistant',
      waitingOnUser: _asBool(json['waiting_on_user'], false),
      socialPresence: json['social_presence'] as String? ?? '',
      arrivalHint: json['arrival_hint'] as String? ?? '',
      relationshipStage: json['relationship_stage'] as String? ?? 'new',
      totalSessions: json['total_sessions'] as int? ?? 0,
    );
  }
}

class ApiService {
  ApiService._();

  static final http.Client _client = http.Client();
  static void Function()? onboardingSuccessCallback;

  static String get _userId {
    final uid = AuthService.currentUserId;
    if (uid == null) throw StateError('No authenticated user');
    return uid;
  }

  static Future<ChatResponse?> sendMessage({
    required String message,
    String? conversationId,
    String? characterId,
    String? clientSentAt,
    int? draftDurationMs,
    int? replyLatencyMs,
    int? parentMessageId,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(ApiConfig.chatUrl),
            headers: await _defaultHeaders(),
            body: jsonEncode({
              'user_id': _userId,
              'message': message,
              'conversation_id': conversationId,
              'character_id': characterId,
              'client_sent_at': clientSentAt,
              'draft_duration_ms': draftDurationMs,
              'reply_latency_ms': replyLatencyMs,
              'parent_message_id': parentMessageId,
            }),
          )
          .timeout(ApiConfig.chatTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return ChatResponse.fromJson(json);
      }

      throw ChatException(_parseError(response), response.statusCode);
    } on SocketException {
      throw const ChatException('No connection to server. Is the backend running?', 0);
    } on TimeoutException {
      throw const ChatException('Your companion took too long to respond. Try again.', 408);
    } on ChatException {
      rethrow;
    } catch (e) {
      throw ChatException('Unexpected error: $e', -1);
    }
  }

  static Future<SessionStartResponse?> startSession({
    String? characterId,
    bool resumeExisting = true,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(ApiConfig.sessionStartUrl),
            headers: await _defaultHeaders(),
            body: jsonEncode({
              'user_id': _userId,
              'character_id': characterId,
              'resume_existing': resumeExisting,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return SessionStartResponse.fromJson(json);
      }
      throw ChatException(_parseError(response), response.statusCode);
    } on SocketException {
      throw const ChatException('No connection to server. Is the backend running?', 0);
    } on TimeoutException {
      throw const ChatException('The first thread took too long to open. Try again.', 408);
    } on ChatException {
      rethrow;
    } catch (e) {
      throw ChatException('Unexpected error: $e', -1);
    }
  }

  static Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse(ApiConfig.healthUrl))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<MyCompanionsResponse?> getMyCompanions() async {
    try {
      final response = await _client
          .get(
            Uri.parse(ApiConfig.myCompanionsUrl),
            headers: await _defaultHeaders(),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return MyCompanionsResponse.fromJson(json);
      }

      throw ChatException(_parseError(response), response.statusCode);
    } on SocketException {
      throw const ChatException('No connection to server. Is the backend running?', 0);
    } on TimeoutException {
      throw const ChatException('The companion roster took too long to load.', 408);
    } on ChatException {
      rethrow;
    } catch (e) {
      throw ChatException('Unexpected error: $e', -1);
    }
  }

  static Future<UserProfileResponse?> getMyProfile({String? pairId}) async {
    try {
      final uri = Uri.parse(ApiConfig.myProfileUrl).replace(
        queryParameters: pairId == null ? null : {'pair_id': pairId},
      );
      final response = await _client
          .get(uri, headers: await _defaultHeaders())
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return UserProfileResponse.fromJson(json);
      }
      throw ChatException(_parseError(response), response.statusCode);
    } on SocketException {
      throw const ChatException('No connection to server. Is the backend running?', 0);
    } on TimeoutException {
      throw const ChatException('Your Sol profile took too long to load.', 408);
    } on ChatException {
      rethrow;
    } catch (e) {
      throw ChatException('Unexpected error: $e', -1);
    }
  }

  static Future<List<MemoryEntry>> getPairMemories(String pairId) async {
    final response = await _client
        .get(
          Uri.parse(ApiConfig.pairMemoriesUrl(pairId)),
          headers: await _defaultHeaders(),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['memories'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MemoryEntry.fromJson)
        .toList();
  }

  static Future<UserPreferences> updatePreferences(Map<String, dynamic> updates) async {
    final response = await _client
        .patch(
          Uri.parse(ApiConfig.preferencesUrl),
          headers: await _defaultHeaders(),
          body: jsonEncode(updates),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return UserPreferences.fromJson(
      json['preferences'] as Map<String, dynamic>? ?? const {},
    );
  }

  static Future<PairPreferences> updatePairPreferences(
    String pairId,
    Map<String, dynamic> updates,
  ) async {
    final response = await _client
        .patch(
          Uri.parse(ApiConfig.pairPreferencesUrl(pairId)),
          headers: await _defaultHeaders(),
          body: jsonEncode(updates),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return PairPreferences.fromPairJson(
      json['pair'] as Map<String, dynamic>? ?? const {},
    );
  }

  static Future<void> deleteMemory(String pairId, String memoryId) async {
    final response = await _client
        .delete(
          Uri.parse(ApiConfig.pairMemoryDeleteUrl(pairId, memoryId)),
          headers: await _defaultHeaders(),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
  }

  static Future<Map<String, dynamic>> updateFact(
    String pairId,
    int factId,
    String value,
  ) async {
    final response = await _client
        .patch(
          Uri.parse(ApiConfig.pairFactUrl(pairId, factId)),
          headers: await _defaultHeaders(),
          body: jsonEncode({'value': value}),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['fact'] as Map<String, dynamic>? ?? const {};
  }

  static Future<MemoryEntry> updateMemory(
    String pairId,
    String memoryId, {
    String? title,
    String? content,
  }) async {
    final response = await _client
        .patch(
          Uri.parse(ApiConfig.pairMemoryUrl(pairId, memoryId)),
          headers: await _defaultHeaders(),
          body: jsonEncode({
            if (title != null) 'title': title,
            if (content != null) 'content': content,
          }),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return MemoryEntry.fromJson(
      json['memory'] as Map<String, dynamic>? ?? const {},
    );
  }

  static Future<void> resetPairMemory(String pairId) async {
    final response = await _client
        .post(
          Uri.parse(ApiConfig.pairResetUrl(pairId)),
          headers: await _defaultHeaders(),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
  }

  static Future<void> deleteAccount() async {
    final response = await _client
        .delete(
          Uri.parse('${ApiConfig.baseUrl}/api/me/account'),
          headers: await _defaultHeaders(),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
  }

  static Future<void> registerDeviceToken({
    required String platform,
    required String pushToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse(ApiConfig.deviceTokenUrl),
          headers: await _defaultHeaders(),
          body: jsonEncode({
            'platform': platform,
            'push_token': pushToken,
          }),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
  }

  static Future<List<PendingProactiveEvent>> getPendingProactiveEvents({
    String? pairId,
  }) async {
    final uri = Uri.parse(ApiConfig.proactivePendingUrl).replace(
      queryParameters: pairId == null ? null : {'pair_id': pairId},
    );
    final response = await _client
        .get(uri, headers: await _defaultHeaders())
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw ChatException(_parseError(response), response.statusCode);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['events'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PendingProactiveEvent.fromJson)
        .toList();
  }

  static Future<OnboardingCompleteResponse?> completeOnboarding({
    required String preferredName,
    required String connectionStyle,
    required String presenceFrequency,
    required String depthPreference,
    required String behavioralGuardrail,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(ApiConfig.onboardingCompleteUrl),
            headers: await _defaultHeaders(),
            body: jsonEncode({
              'preferred_name': preferredName,
              'connection_style': connectionStyle,
              'presence_frequency': presenceFrequency,
              'depth_preference': depthPreference,
              'behavioral_guardrail': behavioralGuardrail,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        onboardingSuccessCallback?.call();
        return OnboardingCompleteResponse.fromJson(json);
      }
      throw ChatException(_parseError(response), response.statusCode);
    } on SocketException {
      throw const ChatException('No connection to server. Is the backend running?', 0);
    } on TimeoutException {
      throw const ChatException('Onboarding took too long to complete. Try again.', 408);
    } on ChatException {
      rethrow;
    } catch (e) {
      throw ChatException('Unexpected error: $e', -1);
    }
  }

  static Future<bool> checkOnboardingStatus() async {
    try {
      final response = await _client
          .get(
            Uri.parse(ApiConfig.onboardingStatusUrl),
            headers: await _defaultHeaders(),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['onboarding_completed'] as bool? ?? false;
      }
      throw ChatException(_parseError(response), response.statusCode);
    } on SocketException {
      throw const ChatException('No connection to server. Is the backend running?', 0);
    } on TimeoutException {
      throw const ChatException('Onboarding status check timed out.', 408);
    } on ChatException {
      rethrow;
    } catch (e) {
      throw ChatException('Unexpected status check error: $e', -1);
    }
  }

  static Future<Map<String, String>> _defaultHeaders() async {
    final token = await AuthService.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String _parseError(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = json['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail;
      }
      if (detail != null) {
        return detail.toString();
      }
      return 'Server error ${response.statusCode}';
    } catch (_) {
      return 'Server error ${response.statusCode}';
    }
  }
}

List<ChatBurst> _parseBursts(dynamic payload) {
  if (payload is! List) {
    return const [];
  }
  return payload
      .whereType<Map<String, dynamic>>()
      .map(ChatBurst.fromJson)
      .where((burst) => burst.text.trim().isNotEmpty)
      .toList();
}

String _combinedBurstText(List<ChatBurst> bursts) {
  return bursts.map((burst) => burst.text.trim()).where((text) => text.isNotEmpty).join('\n');
}

bool _asBool(dynamic value, bool fallback) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  return fallback;
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

class ChatException implements Exception {
  final String message;
  final int statusCode;

  const ChatException(this.message, this.statusCode);

  @override
  String toString() => 'ChatException($statusCode): $message';
}

class OnboardingCompleteResponse {
  final String companionId;
  final String companionName;
  final String companionSummary;
  final List<String> humanizingDetails;
  final String conversationalVibe;
  final String openingLine;
  final String pairId;

  const OnboardingCompleteResponse({
    required this.companionId,
    required this.companionName,
    required this.companionSummary,
    required this.humanizingDetails,
    required this.conversationalVibe,
    required this.openingLine,
    required this.pairId,
  });

  factory OnboardingCompleteResponse.fromJson(Map<String, dynamic> json) {
    return OnboardingCompleteResponse(
      companionId: json['companion_id'] as String? ?? '',
      companionName: json['companion_name'] as String? ?? '',
      companionSummary: json['companion_summary'] as String? ?? '',
      humanizingDetails: (json['humanizing_details'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      conversationalVibe: json['conversational_vibe'] as String? ?? '',
      openingLine: json['opening_line'] as String? ?? '',
      pairId: json['pair_id'] as String? ?? '',
    );
  }
}
