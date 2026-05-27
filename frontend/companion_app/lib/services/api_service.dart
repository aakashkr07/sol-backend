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
  static String get healthUrl => '$baseUrl/health';

  static const Duration requestTimeout = Duration(seconds: 30);
}

class ChatResponse {
  final String reply;
  final String conversationId;
  final int memoryCount;
  final String pairId;
  final String companionId;
  final String companionName;

  const ChatResponse({
    required this.reply,
    required this.conversationId,
    required this.memoryCount,
    required this.pairId,
    required this.companionId,
    required this.companionName,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      reply: json['reply'] as String,
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
  });

  factory SessionStartResponse.fromJson(Map<String, dynamic> json) {
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
      openingMessage: json['opening_message'] as String? ?? 'hey',
    );
  }
}

class CompanionSummary {
  final String id;
  final String name;
  final String summary;
  final bool isPrimary;
  final int totalSessions;

  const CompanionSummary({
    required this.id,
    required this.name,
    required this.summary,
    required this.isPrimary,
    required this.totalSessions,
  });

  factory CompanionSummary.fromJson(Map<String, dynamic> json) {
    return CompanionSummary(
      id: json['companion_id'] as String? ?? json['id'] as String? ?? '',
      name: json['companion_name'] as String? ?? json['name'] as String? ?? 'Companion',
      summary: json['companion_summary'] as String? ?? json['summary'] as String? ?? '',
      isPrimary: json['is_primary'] as bool? ?? false,
      totalSessions: json['total_sessions'] as int? ?? 0,
    );
  }
}

class MyCompanionsResponse {
  final String? userName;
  final CompanionSummary? primaryCompanion;
  final List<CompanionSummary> pairs;
  final List<CompanionSummary> availableCompanions;

  const MyCompanionsResponse({
    required this.userName,
    required this.primaryCompanion,
    required this.pairs,
    required this.availableCompanions,
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
    );
  }
}

class ApiService {
  ApiService._();

  static final http.Client _client = http.Client();

  static String get _userId {
    final uid = AuthService.currentUserId;
    if (uid == null) throw StateError('No authenticated user');
    return uid;
  }

  static Future<ChatResponse?> sendMessage({
    required String message,
    String? conversationId,
    String? characterId,
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
            }),
          )
          .timeout(ApiConfig.requestTimeout);

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
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(ApiConfig.sessionStartUrl),
            headers: await _defaultHeaders(),
            body: jsonEncode({
              'user_id': _userId,
              'character_id': characterId,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return SessionStartResponse.fromJson(json);
      }
      return null;
    } catch (_) {
      return null;
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
    } on ChatException {
      rethrow;
    } catch (_) {
      return null;
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

class ChatException implements Exception {
  final String message;
  final int statusCode;

  const ChatException(this.message, this.statusCode);

  @override
  String toString() => 'ChatException($statusCode): $message';
}
