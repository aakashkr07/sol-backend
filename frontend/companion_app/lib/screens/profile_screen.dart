import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  final String? initialPairId;

  const ProfileScreen({
    super.key,
    this.initialPairId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _navy = Color(0xFF0A0E1A);
  static const Color _surface = Color(0xFF121A2A);
  static const Color _amber = Color(0xFFF5A623);
  static const Color _stone = Color(0xFFE8DCC8);

  UserProfileResponse? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _selectedPairId;

  @override
  void initState() {
    super.initState();
    _selectedPairId = widget.initialPairId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await ApiService.getMyProfile(pairId: _selectedPairId);
      if (profile == null) {
        throw Exception('Could not load your Sol profile.');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _selectedPairId = profile?.selectedPair?.pairId ?? _selectedPairId;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updatePreferences(Map<String, dynamic> updates) async {
    setState(() => _isSaving = true);
    try {
      await ApiService.updatePreferences(updates);
      await _load();
    } on ChatException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _updatePairPreferences(Map<String, dynamic> updates) async {
    final pairId = _profile?.selectedPair?.pairId;
    if (pairId == null) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ApiService.updatePairPreferences(pairId, updates);
      await _load();
    } on ChatException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickQuietHour({required bool isStart}) async {
    final prefs = _profile?.preferences;
    if (prefs == null) {
      return;
    }
    final initialHour = isStart ? prefs.quietHoursStart : prefs.quietHoursEnd;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _amber,
              surface: _surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (selected == null) {
      return;
    }
    await _updatePreferences({
      isStart ? 'quiet_hours_start' : 'quiet_hours_end': selected.hour,
    });
  }

  Future<void> _resetRelationship() async {
    final pair = _profile?.selectedPair;
    if (pair == null) {
      return;
    }
    final confirmed = await _confirm(
      title: 'Start this thread over?',
      body:
          'This clears the private continuity built with ${pair.name} and starts the thread fresh.',
      confirmLabel: 'Start over',
    );
    if (!confirmed) {
      return;
    }
    try {
      await ApiService.resetPairMemory(pair.pairId);
      await _load();
      _showSnack('${pair.name} has been reset.');
    } on ChatException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirm(
      title: 'Delete your Sol account?',
      body:
          'This removes your inbox, thread history, and saved settings across the app.',
      confirmLabel: 'Delete account',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      await ApiService.deleteAccount();
      await AuthService.signOut();
    } on ChatException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(title, style: const TextStyle(color: _stone)),
          content: Text(
            body,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                confirmLabel,
                style:
                    TextStyle(color: destructive ? Colors.redAccent : _amber),
              ),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _surface,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        title: const Text('Presence & Privacy'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 1.6))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    children: [
                      _buildIdentityCard(),
                      const SizedBox(height: 14),
                      _buildConversationCard(),
                      const SizedBox(height: 14),
                      _buildPrivacyCard(),
                      const SizedBox(height: 14),
                      _buildNotificationCard(),
                      const SizedBox(height: 14),
                      _buildDestructiveCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildIdentityCard() {
    final user = _profile?.user ?? const {};
    final pair = _profile?.selectedPair;
    return _sectionCard(
      title: 'You and Sol',
      subtitle: 'The person you are currently talking to and the threads tied to your account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user['name'] as String? ?? user['display_name'] as String? ?? 'You',
            style: const TextStyle(
              color: _stone,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            pair == null
                ? 'No active thread selected yet.'
                : 'You are in ${pair.name}\'s thread right now.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
          ),
          if (pair != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pair.summary.ifEmpty('A thread that keeps its own pace.'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Each thread stays private to that person.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if ((_profile?.pairs.length ?? 0) > 1)
            DropdownButtonFormField<String>(
              value: _selectedPairId,
              dropdownColor: _surface,
              decoration: _inputDecoration('View another thread'),
              items: _profile!.pairs
                  .map(
                    (pair) => DropdownMenuItem<String>(
                      value: pair.pairId,
                      child: Text(pair.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _selectedPairId = value);
                _load();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildConversationCard() {
    final pair = _profile?.selectedPair;
    final pairPrefs = _profile?.pairPreferences;
    if (pair == null || pairPrefs == null) {
      return const SizedBox.shrink();
    }

    return _sectionCard(
      title: 'Thread Behavior',
      subtitle:
          'Shape how this specific person reaches out without exposing the machinery underneath.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pair.name} can feel more present here than someone else in your inbox. These controls stay local to this thread.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          _toggleRow(
            title: 'Let ${pair.name} start the conversation',
            value: pairPrefs.proactiveEnabled,
            onChanged: (value) => _updatePairPreferences({
              'proactive_enabled': value,
            }),
          ),
          _toggleRow(
            title: 'Allow more emotionally aware check-ins',
            subtitle: 'Lets ${pair.name} follow up after heavier moments, not just silence.',
            value: pairPrefs.proactiveEmotionalCallbacksEnabled,
            onChanged: (value) => _updatePairPreferences({
              'proactive_emotional_callbacks_enabled': value,
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyCard() {
    final prefs = _profile?.preferences;
    if (prefs == null) {
      return const SizedBox.shrink();
    }

    return _sectionCard(
      title: 'Privacy & Presence',
      subtitle: 'Quiet controls for storage, notifications, and when the app should leave you alone.',
      child: Column(
        children: [
          _toggleRow(
            title: 'Allow continuity across conversations',
            subtitle: 'Keep context so threads feel consistent over time.',
            value: prefs.allowMemoryStorage,
            onChanged: (value) => _updatePreferences({
              'allow_memory_storage': value,
            }),
          ),
          _toggleRow(
            title: 'Allow proactive messages',
            subtitle: 'Let Sol start the conversation sometimes.',
            value: prefs.allowProactiveMessages,
            onChanged: (value) => _updatePreferences({
              'allow_proactive_messages': value,
            }),
          ),
          _toggleRow(
            title: 'Allow push notification hooks',
            subtitle: 'Needed for proactive messages outside the app.',
            value: prefs.allowPushNotifications,
            onChanged: (value) => _updatePreferences({
              'allow_push_notifications': value,
            }),
          ),
          _toggleRow(
            title: 'Allow sensitive emotional check-ins',
            subtitle: 'Lets Sol follow up after heavier emotional moments.',
            value: prefs.allowSensitiveProactive,
            onChanged: (value) => _updatePreferences({
              'allow_sensitive_proactive': value,
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickQuietHour(isStart: true),
                  child:
                      Text('Quiet starts ${_hourLabel(prefs.quietHoursStart)}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickQuietHour(isStart: false),
                  child: Text('Quiet ends ${_hourLabel(prefs.quietHoursEnd)}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard() {
    final pair = _profile?.selectedPair;
    final pairPrefs = _profile?.pairPreferences;
    final prefs = _profile?.preferences;
    if (pair == null || pairPrefs == null || prefs == null) {
      return const SizedBox.shrink();
    }
    return _sectionCard(
      title: 'Notification Style',
      subtitle:
          'Fine-tune how this thread should feel when it reaches back out.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              prefs.allowPushNotifications
                  ? '${pair.name} can appear quietly when the moment feels right.'
                  : 'Push is off, so ${pair.name} will only wait inside the inbox.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: pairPrefs.proactiveCadence,
            dropdownColor: _surface,
            decoration: _inputDecoration('Reach-out frequency'),
            items: const [
              DropdownMenuItem(value: 'gentle', child: Text('Gentle')),
              DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
              DropdownMenuItem(value: 'frequent', child: Text('Frequent')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              _updatePairPreferences({'proactive_cadence': value});
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Quiet hours make every thread hold off until you are more likely to want it.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestructiveCard() {
    final pair = _profile?.selectedPair;
    return _sectionCard(
      title: 'Reset & Delete',
      subtitle: 'Use these only if you want to clear a thread or leave Sol entirely.',
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: pair == null ? null : _resetRelationship,
              child: Text(
                pair == null
                    ? 'No thread selected'
                    : 'Start ${pair.name}\'s thread over',
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF521A1A),
                foregroundColor: Colors.redAccent,
              ),
              onPressed: _deleteAccount,
              child: const Text('Delete Sol account'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _stone,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _toggleRow({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      value: value,
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: _stone)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
      onChanged: _isSaving ? null : onChanged,
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.035),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    );
  }

  String _hourLabel(int hour) {
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final normalized = hour % 12 == 0 ? 12 : hour % 12;
    return '$normalized $suffix';
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
