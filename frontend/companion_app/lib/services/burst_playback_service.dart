import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class BurstPlaybackService {
  static const String _storageKeyPrefix = 'bursts_queue_';

  // 1. Immediately write the incoming bursts to local storage
  static Future<void> saveBursts(String pairId, List<ChatBurst> bursts) async {
    if (pairId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> serialized = bursts.map((b) => {
      'text': b.text,
      'pre_burst_delay_ms': b.preBurstDelayMs,
      'typing_duration_ms': b.typingDurationMs,
      'pause_intensity': b.pauseIntensity,
      'is_follow_up': b.isFollowUp,
      'is_played': false,
    }).toList();

    await prefs.setString(_storageKeyPrefix + pairId, jsonEncode(serialized));
  }

  // 2. Fetch all stored bursts for a pair_id
  static Future<List<Map<String, dynamic>>> getStoredBursts(String pairId) async {
    if (pairId.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKeyPrefix + pairId);
    if (raw == null) return const [];
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  // 3. Get only the UNPLAYED bursts for a pair_id
  static Future<List<ChatBurst>> getUnplayedBursts(String pairId) async {
    final stored = await getStoredBursts(pairId);
    final unplayed = stored
        .where((b) => b['is_played'] == false || b['is_played'] == 0)
        .map((b) => ChatBurst(
              text: b['text'] as String? ?? '',
              preBurstDelayMs: b['pre_burst_delay_ms'] as int? ?? 320,
              typingDurationMs: b['typing_duration_ms'] as int? ?? 620,
              pauseIntensity: b['pause_intensity'] as String? ?? 'brief',
              isFollowUp: b['is_follow_up'] as bool? ?? false,
            ))
        .toList();
    return unplayed;
  }

  // 4. Get all stored bursts as standard ChatBurst objects
  static Future<List<ChatBurst>> getStoredBurstsAsChatBursts(String pairId) async {
    final stored = await getStoredBursts(pairId);
    return stored
        .map((b) => ChatBurst(
              text: b['text'] as String? ?? '',
              preBurstDelayMs: b['pre_burst_delay_ms'] as int? ?? 320,
              typingDurationMs: b['typing_duration_ms'] as int? ?? 620,
              pauseIntensity: b['pause_intensity'] as String? ?? 'brief',
              isFollowUp: b['is_follow_up'] as bool? ?? false,
            ))
        .toList();
  }

  // 5. Mark a specific burst as played in local storage by index
  static Future<void> markBurstPlayed(String pairId, int index) async {
    if (pairId.isEmpty) return;
    final stored = await getStoredBursts(pairId);
    if (index >= 0 && index < stored.length) {
      stored[index]['is_played'] = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKeyPrefix + pairId, jsonEncode(stored));
    }
  }

  // 6. Check if there are any unplayed bursts left
  static Future<bool> hasUnplayedBursts(String pairId) async {
    final unplayed = await getUnplayedBursts(pairId);
    return unplayed.isNotEmpty;
  }

  // 7. Clear all bursts for a pair_id
  static Future<void> clearQueue(String pairId) async {
    if (pairId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKeyPrefix + pairId);
  }
}
