import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/notification_hooks_service.dart';
import '../services/session_bootstrap_service.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  static const Color _bg = Color(0xFF08101A);
  static const Color _surface = Color(0xFF101927);
  static const Color _surfaceSoft = Color(0xFF162233);
  static const Color _amber = Color(0xFFF5A623);
  static const Color _cream = Color(0xFFEEE8DF);
  static const Color _muted = Color(0xFF9FA7B5);

  MyCompanionsResponse? _roster;
  bool _isLoading = true;
  bool _isOpeningThread = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      await NotificationHooksService.initialize();
      final roster = await ApiService.getMyCompanions();
      if (!mounted) {
        return;
      }
      setState(() {
        _roster = roster;
        _isLoading = false;
        _error = null;
      });
    } on ChatException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = 'Your inbox did not load. Try again.';
      });
    }
  }

  Future<void> _openEntry(InboxEntrySummary entry) async {
    if (_isOpeningThread) {
      return;
    }

    setState(() {
      _isOpeningThread = true;
      _error = null;
    });

    try {
      final pending = SessionBootstrapService.peek();
      final session =
          pending != null && pending.companionId == entry.companionId
              ? SessionBootstrapService.consume()
              : await ApiService.startSession(
                  characterId: entry.companionId,
                  resumeExisting: true,
                );

      if (!mounted || session == null) {
        return;
      }

      SessionBootstrapService.stash(session);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ChatScreen(),
        ),
      );

      if (mounted) {
        await _load(silent: true);
      }
    } on ChatException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _isOpeningThread = false);
      }
    }
  }

  Future<void> _openProfile() async {
    final selectedPairId = _roster?.primaryCompanion?.pairId;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(initialPairId: selectedPairId),
      ),
    );
    if (mounted) {
      await _load(silent: true);
    }
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: _bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111A2A), _bg],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: _amber,
            onRefresh: _load,
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 1.6))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 18),
                      _buildPresenceBanner(),
                      const SizedBox(height: 16),
                      _buildActiveStack(),
                      const SizedBox(height: 16),
                      if (_error != null) _buildError(),
                      ..._buildInboxEntries(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final firstName = _firstName();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                firstName == null ? 'Messages' : '$firstName\'s messages',
                style: GoogleFonts.cormorantGaramond(
                  color: _cream,
                  fontSize: 34,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'threads that kept moving while you were away',
                style: GoogleFonts.jost(
                  color: _muted.withValues(alpha: 0.72),
                  fontSize: 12.5,
                  letterSpacing: 0.25,
                ),
              ),
            ],
          ),
        ),
        _iconButton(Icons.tune_rounded, _openProfile),
        const SizedBox(width: 8),
        _iconButton(Icons.logout_rounded, _signOut),
      ],
    );
  }

  Widget _buildPresenceBanner() {
    final entries = _roster?.inboxEntries ?? const <InboxEntrySummary>[];
    final unread = entries.where((entry) => entry.hasUnread).length;
    final arrivals = entries.where((entry) => entry.isArrival).length;
    final activeNow = entries.where((entry) => entry.waitingOnUser).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _surfaceSoft.withValues(alpha: 0.95),
            _surface.withValues(alpha: 0.95),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _amber.withValues(alpha: 0.12),
            ),
            child: Icon(
              arrivals > 0
                  ? Icons.mark_chat_unread_rounded
                  : Icons.forum_rounded,
              color: _amber,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              arrivals > 0
                  ? '$arrivals new thread${arrivals == 1 ? '' : 's'} surfaced naturally'
                  : activeNow > 0
                      ? '$activeNow thread${activeNow == 1 ? '' : 's'} feel socially active right now'
                      : unread > 0
                          ? '$unread active conversation${unread == 1 ? '' : 's'} waiting on you'
                          : 'everything feels quiet right now',
              style: GoogleFonts.jost(
                color: _cream.withValues(alpha: 0.88),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF521A1A).withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.22)),
      ),
      child: Text(
        _error ?? '',
        style: GoogleFonts.jost(
          color: const Color(0xFFFFA3A3),
          fontSize: 12.5,
        ),
      ),
    );
  }

  List<Widget> _buildInboxEntries() {
    final entries = _roster?.inboxEntries ?? const <InboxEntrySummary>[];
    if (entries.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Center(
            child: Text(
              'No threads have come into focus yet.',
              style: GoogleFonts.jost(
                color: _muted.withValues(alpha: 0.78),
                fontSize: 13,
              ),
            ),
          ),
        ),
      ];
    }

    final active = entries
        .where((entry) => entry.waitingOnUser && !entry.isArrival)
        .toList();
    final arrivals = entries.where((entry) => entry.isArrival).toList();
    final quieter = entries
        .where((entry) => !entry.isArrival && !entry.waitingOnUser)
        .toList();

    final widgets = <Widget>[];
    if (active.isNotEmpty) {
      widgets
          .add(_buildSectionLabel('Waiting On You', '${active.length} active'));
      widgets.addAll(_tilesFor(active));
    }
    if (arrivals.isNotEmpty) {
      widgets.add(_buildSectionLabel('New Around You', 'ambient arrivals'));
      widgets.addAll(_tilesFor(arrivals));
    }
    if (quieter.isNotEmpty) {
      widgets.add(_buildSectionLabel('Quiet Threads', 'still inhabited'));
      widgets.addAll(_tilesFor(quieter));
    }
    return widgets;
  }

  List<Widget> _tilesFor(List<InboxEntrySummary> entries) {
    return entries
        .map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _InboxTile(
              entry: entry,
              opening: _isOpeningThread,
              onTap: () => _openEntry(entry),
            ),
          ),
        )
        .toList();
  }

  Widget _buildActiveStack() {
    final entries = (_roster?.inboxEntries ?? const <InboxEntrySummary>[])
        .where((entry) => entry.waitingOnUser)
        .take(6)
        .toList();
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return GestureDetector(
            onTap: _isOpeningThread ? null : () => _openEntry(entry),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _PresenceAvatar(entry: entry),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _amber,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          entry.unreadCount > 0
                              ? '${entry.unreadCount}'
                              : 'now',
                          style: GoogleFonts.jost(
                            color: const Color(0xFF0B0E16),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    entry.companionName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jost(
                      color: _cream,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    entry.socialPresence,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jost(
                      color: _muted.withValues(alpha: 0.72),
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionLabel(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.jost(
              color: _cream.withValues(alpha: 0.92),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            subtitle,
            style: GoogleFonts.jost(
              color: _muted.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          child: Icon(
            icon,
            size: 18,
            color: Colors.white.withValues(alpha: 0.58),
          ),
        ),
      ),
    );
  }

  String? _firstName() {
    final name = _roster?.userName ?? AuthService.currentUserName;
    if (name == null || name.trim().isEmpty) {
      return null;
    }
    return name.trim().split(' ').first;
  }
}

class _InboxTile extends StatelessWidget {
  final InboxEntrySummary entry;
  final bool opening;
  final VoidCallback onTap;

  const _InboxTile({
    required this.entry,
    required this.opening,
    required this.onTap,
  });

  static const Color _surface = Color(0xFF101927);
  static const Color _amber = Color(0xFFF5A623);
  static const Color _cream = Color(0xFFEEE8DF);
  static const Color _muted = Color(0xFF98A4B6);

  @override
  Widget build(BuildContext context) {
    final unread = entry.hasUnread;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: opening ? null : onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: unread
                ? _surface.withValues(alpha: 0.98)
                : _surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: unread
                  ? _amber.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatar(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.companionName,
                              style: GoogleFonts.jost(
                                color: _cream,
                                fontSize: 15,
                                fontWeight:
                                    unread ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            _timeLabel(entry),
                            style: GoogleFonts.jost(
                              color: unread
                                  ? _amber.withValues(alpha: 0.86)
                                  : _muted.withValues(alpha: 0.7),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.socialPresence.isNotEmpty
                            ? entry.socialPresence
                            : entry.statusText,
                        style: GoogleFonts.jost(
                          color: unread
                              ? _amber.withValues(alpha: 0.9)
                              : _muted.withValues(alpha: 0.74),
                          fontSize: 11.5,
                          fontWeight:
                              unread ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.previewText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jost(
                          color: _cream.withValues(alpha: unread ? 0.9 : 0.7),
                          fontSize: 13.3,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.unreadCount > 0) ...[
                  const SizedBox(width: 10),
                  Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: _amber,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${entry.unreadCount}',
                      style: GoogleFonts.jost(
                        color: const Color(0xFF0B0E16),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            _amber.withValues(alpha: entry.isArrival ? 0.82 : 0.7),
            const Color(0xFF3D2A00).withValues(alpha: 0.44),
          ],
        ),
      ),
      child: Center(
        child: Text(
          entry.companionName.isNotEmpty
              ? entry.companionName[0].toUpperCase()
              : '?',
          style: GoogleFonts.cormorantGaramond(
            color: _cream,
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _timeLabel(InboxEntrySummary entry) {
    final stamp = entry.previewDateTime;
    if (stamp == null) {
      return entry.isArrival ? 'new' : '';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(stamp.year, stamp.month, stamp.day);
    if (thatDay == today) {
      final hour = stamp.hour % 12 == 0 ? 12 : stamp.hour % 12;
      final minute = stamp.minute.toString().padLeft(2, '0');
      final suffix = stamp.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $suffix';
    }
    if (today.difference(thatDay).inDays < 7) {
      const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return labels[stamp.weekday - 1];
    }
    return '${stamp.month}/${stamp.day}';
  }
}

class _PresenceAvatar extends StatelessWidget {
  final InboxEntrySummary entry;

  const _PresenceAvatar({
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xFFF5A623)
                .withValues(alpha: entry.isArrival ? 0.82 : 0.72),
            const Color(0xFF3D2A00).withValues(alpha: 0.42),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF5A623).withValues(alpha: 0.18),
            blurRadius: 16,
          ),
        ],
      ),
      child: Center(
        child: Text(
          entry.companionName.isNotEmpty
              ? entry.companionName[0].toUpperCase()
              : '?',
          style: GoogleFonts.cormorantGaramond(
            color: const Color(0xFFEEE8DF),
            fontSize: 26,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
