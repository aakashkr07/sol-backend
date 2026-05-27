import 'package:companion_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses profile response with pair id and preferences', () {
    final profile = UserProfileResponse.fromJson({
      'user': {'id': 'u1', 'name': 'Aakash'},
      'preferences': {
        'allow_memory_storage': 1,
        'allow_proactive_messages': true,
        'allow_push_notifications': 0,
        'quiet_hours_start': 22,
        'quiet_hours_end': 8,
      },
      'selected_pair': {
        'pair_id': 'u1::nova',
        'companion_id': 'nova',
        'companion_name': 'Nova',
        'companion_summary': 'warm',
        'is_primary': true,
        'proactive_enabled': 1,
        'proactive_cadence': 'balanced',
        'proactive_emotional_callbacks_enabled': 0,
      },
      'relationship_state': {
        'closeness': 0.61,
        'trust': 0.58,
        'openness': 0.44,
        'comfort': 0.67,
        'rhythm': 0.52,
        'topic_familiarity': 0.49,
        'stage': 'close',
      },
      'what_sol_knows': {'favorite_color': 'black'},
      'fact_rows': [],
      'fact_conflicts': [],
      'memories': [],
      'memory_count': 3,
      'pairs': [],
      'inbox_entries': const [],
    });

    expect(profile.selectedPair?.id, 'nova');
    expect(profile.selectedPair?.pairId, 'u1::nova');
    expect(profile.preferences.allowMemoryStorage, isTrue);
    expect(profile.preferences.allowPushNotifications, isFalse);
    expect(profile.pairPreferences?.proactiveEmotionalCallbacksEnabled, isFalse);
    expect(profile.relationshipState?.stage, 'close');
  });

  test('parses pending proactive event bursts', () {
    final event = PendingProactiveEvent.fromJson({
      'id': 'evt-1',
      'pair_id': 'u1::nova',
      'conversation_id': 'conv-1',
      'reason': 'inactivity_check_in',
      'payload': {
        'companion_name': 'Nova',
        'bursts': [
          {
            'text': 'you still up',
            'pre_burst_delay_ms': 200,
            'typing_duration_ms': 500,
            'pause_intensity': 'brief',
            'is_follow_up': false,
          }
        ],
      },
    });

    expect(event.companionName, 'Nova');
    expect(event.bursts, hasLength(1));
    expect(event.bursts.first.text, 'you still up');
  });

  test('parses inbox entries and resumed session history', () {
    final roster = MyCompanionsResponse.fromJson({
      'user_name': 'Aakash',
      'pairs': const [],
      'available_companions': const [],
      'inbox_entries': [
        {
          'entry_kind': 'arrival',
          'pair_id': '',
          'companion_id': 'atlas',
          'companion_name': 'Atlas',
          'preview_text': 'nova brought you up once',
          'preview_at': 'arrival-123',
          'status_text': 'nova mentioned you',
          'unread_count': 1,
        }
      ],
    });

    final session = SessionStartResponse.fromJson({
      'conversation_id': 'conv-1',
      'session_number': 3,
      'memory_count': 4,
      'is_first_session': false,
      'pair_id': 'u1::nova',
      'companion_id': 'nova',
      'companion_name': 'Nova',
      'companion_summary': 'warm',
      'opening_message': '',
      'opening_bursts': const [],
      'resumed_existing': true,
      'history_messages': [
        {
          'role': 'assistant',
          'content': 'you disappeared yesterday',
          'created_at': '2026-05-27T10:00:00',
        }
      ],
    });

    expect(roster.inboxEntries.single.isArrival, isTrue);
    expect(session.resumedExisting, isTrue);
    expect(session.openingBursts, isEmpty);
    expect(session.historyMessages.single.content, 'you disappeared yesterday');
  });
}
