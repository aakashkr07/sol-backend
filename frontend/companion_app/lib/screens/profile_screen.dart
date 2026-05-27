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

  Future<void> _deleteMemory(MemoryEntry memory) async {
    final pairId = _profile?.selectedPair?.pairId;
    if (pairId == null) {
      return;
    }
    final confirmed = await _confirm(
      title: 'Delete this memory?',
      body: 'Sol will stop using this specific remembered moment.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) {
      return;
    }
    try {
      await ApiService.deleteMemory(pairId, memory.id);
      await _load();
    } on ChatException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<void> _resetRelationship() async {
    final pair = _profile?.selectedPair;
    if (pair == null) {
      return;
    }
    final confirmed = await _confirm(
      title: 'Reset this relationship?',
      body:
          'This clears Sol\'s long-term memory, emotional timeline, and relationship state for ${pair.name}.',
      confirmLabel: 'Reset',
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
          'This removes your relationships, memories, and stored settings across the app.',
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
        title: const Text('Sol & Privacy'),
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
                      _buildRelationshipCard(),
                      const SizedBox(height: 14),
                      _buildPrivacyCard(),
                      const SizedBox(height: 14),
                      _buildKnowledgeCard(),
                      const SizedBox(height: 14),
                      _buildMemoryCard(),
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
      subtitle: 'The current relationship thread and your account footprint.',
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
                ? 'No active companion selected.'
                : 'Talking with ${pair.name} right now.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
          ),
          const SizedBox(height: 14),
          if ((_profile?.pairs.length ?? 0) > 1)
            DropdownButtonFormField<String>(
              value: _selectedPairId,
              dropdownColor: _surface,
              decoration: _inputDecoration('View another relationship'),
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

  Widget _buildRelationshipCard() {
    final state = _profile?.relationshipState;
    final pairPrefs = _profile?.pairPreferences;
    if (state == null || pairPrefs == null) {
      return const SizedBox.shrink();
    }

    return _sectionCard(
      title: 'Relationship State',
      subtitle:
          'This is the live emotional model that shapes how your companion responds.',
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _scoreChip('Closeness', state.closeness),
              _scoreChip('Trust', state.trust),
              _scoreChip('Openness', state.openness),
              _scoreChip('Comfort', state.comfort),
              _scoreChip('Rhythm', state.rhythm),
              _scoreChip('Familiarity', state.topicFamiliarity),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow('Stage', state.stage),
          _toggleRow(
            title: 'Let this companion message first',
            value: pairPrefs.proactiveEnabled,
            onChanged: (value) => _updatePairPreferences({
              'proactive_enabled': value,
            }),
          ),
          _toggleRow(
            title: 'Allow emotional callbacks',
            subtitle: 'Reach out after heavier moments, not just long silence.',
            value: pairPrefs.proactiveEmotionalCallbacksEnabled,
            onChanged: (value) => _updatePairPreferences({
              'proactive_emotional_callbacks_enabled': value,
            }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: pairPrefs.proactiveCadence,
            dropdownColor: _surface,
            decoration: _inputDecoration('Proactive cadence'),
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
      subtitle: 'Control what Sol stores and how it can reach back out.',
      child: Column(
        children: [
          _toggleRow(
            title: 'Allow long-term memory storage',
            subtitle: 'Facts, emotional patterns, and episodic recall.',
            value: prefs.allowMemoryStorage,
            onChanged: (value) => _updatePreferences({
              'allow_memory_storage': value,
            }),
          ),
          _toggleRow(
            title: 'Show memory overview in this screen',
            value: prefs.showMemoryOverview,
            onChanged: (value) => _updatePreferences({
              'show_memory_overview': value,
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

  Widget _buildKnowledgeCard() {
    final facts = _profile?.factRows ?? const [];
    final conflicts = _profile?.factConflicts ?? const [];
    final narrative = _profile?.currentNarrative;

    return _sectionCard(
      title: 'What Sol Knows',
      subtitle:
          'The durable facts and narrative threads currently shaping responses.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (narrative != null && narrative.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                narrative,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.76),
                  height: 1.45,
                ),
              ),
            ),
          if (narrative != null && narrative.trim().isNotEmpty)
            const SizedBox(height: 14),
          if (facts.isEmpty)
            Text(
              'No durable facts stored yet.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.54)),
            )
          else
            ...facts.take(10).map(
                  (fact) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      (fact['fact_key'] as String? ?? '').replaceAll('_', ' '),
                      style: const TextStyle(color: _stone),
                    ),
                    subtitle: Text(
                      fact['fact_value'] as String? ?? '',
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Recent shifts',
              style: TextStyle(
                color: _amber.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...conflicts.take(4).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${(item['fact_key'] as String? ?? '').replaceAll('_', ' ')} changed from ${item['previous_value']} to ${item['current_value']}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58)),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildMemoryCard() {
    final showMemories = _profile?.preferences.showMemoryOverview ?? true;
    final memories = _profile?.memories ?? const [];

    return _sectionCard(
      title: 'Visible Memories',
      subtitle:
          'The episodic moments Sol can currently retrieve for this relationship.',
      child: !showMemories
          ? Text(
              'Memory visibility is hidden by your current privacy preference.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.54)),
            )
          : memories.isEmpty
              ? Text(
                  'No stored episodic memories yet.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.54)),
                )
              : Column(
                  children: memories.take(12).map((memory) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  memory.title,
                                  style: const TextStyle(
                                    color: _stone,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _deleteMemory(memory),
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.white.withValues(alpha: 0.42),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            memory.content,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              _tag(memory.emotionTag.ifEmpty('memory')),
                              _tag(
                                  'weight ${memory.emotionalWeight.toStringAsFixed(2)}'),
                              _tag(
                                  'strength ${memory.strength.toStringAsFixed(2)}'),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  Widget _buildDestructiveCard() {
    return _sectionCard(
      title: 'Reset & Delete',
      subtitle: 'These actions change or remove stored relationship history.',
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _resetRelationship,
              child: const Text('Reset current relationship memory'),
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

  Widget _scoreChip(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _amber.withValues(alpha: 0.14)),
      ),
      child: Text(
        '$label ${(value * 100).round()}%',
        style: const TextStyle(
          color: _amber,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.52)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: _stone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.54),
          fontSize: 11.5,
        ),
      ),
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
