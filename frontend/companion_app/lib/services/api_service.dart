// =============================================================================
// services/api_service.dart — Backend Communication (Firebase UID version)
// =============================================================================
//
// CHANGE FROM PREVIOUS VERSION:
//   Before: we generated a random UUID and stored it in SharedPreferences.
//   Now: we use the Firebase UID directly — AuthService.currentUserId
//
//   This means:
//   - Every Google account gets a DIFFERENT user_id automatically
//   - Same account on different devices = same user_id = same memories
//   - Logging out and back in = same memories (uid is permanent)
//   - Two different Google accounts = completely separate memory spaces
//
// NO OTHER CHANGES — the API endpoints and request format are identical.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

// ---------------------------------------------------------------------------
// Configuration — UPDATE THIS IP before running on physical device
// ---------------------------------------------------------------------------

class ApiConfig {
  // !! CHANGE THIS to your computer's local IP when on a real device !!
  // Find it with: ipconfig (Windows) or ifconfig (Mac)
  static const String _baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'sol-backend-production.up.railway.app');

  static String get baseUrl {
    final raw = _baseUrl.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    // Default to HTTPS when only a host is provided.
    return 'https://$raw';
  }
  static String get chatUrl => '$baseUrl/api/chat';
  static String get sessionStartUrl => '$baseUrl/api/session/start';
  static String get healthUrl => '$baseUrl/health';

  static const Duration requestTimeout = Duration(seconds: 30);
}

// ---------------------------------------------------------------------------
// Response Models (unchanged)
// ---------------------------------------------------------------------------

class ChatResponse {
  final String reply;
  final String conversationId;
  final int memoryCount;

  const ChatResponse({
    required this.reply,
    required this.conversationId,
    required this.memoryCount,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      reply: json['reply'] as String,
      conversationId: json['conversation_id'] as String,
      memoryCount: json['memory_count'] as int? ?? 0,
    );
  }
}

class SessionStartResponse {
  final String conversationId;
  final String? userName;
  final int sessionNumber;
  final int memoryCount;
  final bool isFirstSession;

  const SessionStartResponse({
    required this.conversationId,
    this.userName,
    required this.sessionNumber,
    required this.memoryCount,
    required this.isFirstSession,
  });

  factory SessionStartResponse.fromJson(Map<String, dynamic> json) {
    return SessionStartResponse(
      conversationId: json['conversation_id'] as String,
      userName: json['user_name'] as String?,
      sessionNumber: json['session_number'] as int? ?? 1,
      memoryCount: json['memory_count'] as int? ?? 0,
      isFirstSession: json['is_first_session'] as bool? ?? true,
    );
  }
}

// ---------------------------------------------------------------------------
// API Service — now uses Firebase UID
// ---------------------------------------------------------------------------

class ApiService {
  ApiService._();

  static final http.Client _client = http.Client();

  /// Gets the current user's Firebase UID to use as backend user_id.
  /// Throws if not logged in (should never happen — auth gate prevents this).
  static String get _userId {
    final uid = AuthService.currentUserId;
    if (uid == null) throw StateError('No authenticated user');
    return uid;
  }

  // ── Chat ──────────────────────────────────────────────────────────────

  static Future<ChatResponse?> sendMessage({
    required String message,
    String? conversationId,
    String characterId = 'nova',
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(ApiConfig.chatUrl),
            headers: _defaultHeaders(),
            body: jsonEncode({
              'user_id': _userId, // Firebase UID — unique per Google account
              'message': message,
              'conversation_id': conversationId,
              'character_id': characterId,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return ChatResponse.fromJson(json);
      } else {
        final error = _parseError(response);
        throw ChatException(error, response.statusCode);
      }
    } on SocketException {
      throw ChatException(
          'No connection to server. Is the backend running?', 0);
    } on TimeoutException {
      throw ChatException('Nova took too long to respond. Try again.', 408);
    } on ChatException {
      rethrow;
    } catch (e) {
      throw ChatException('Unexpected error: $e', -1);
    }
  }

  // ── Session ───────────────────────────────────────────────────────────

  static Future<SessionStartResponse?> startSession({
    String characterId = 'nova',
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(ApiConfig.sessionStartUrl),
            headers: _defaultHeaders(),
            body: jsonEncode({
              'user_id': _userId, // Firebase UID
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

  // ── Health check ──────────────────────────────────────────────────────

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

  // ── Helpers ────────────────────────────────────────────────────────────

  static Map<String, String> _defaultHeaders() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

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

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

class ChatException implements Exception {
  final String message;
  final int statusCode;
  const ChatException(this.message, this.statusCode);

  @override
  String toString() => 'ChatException($statusCode): $message';
}
