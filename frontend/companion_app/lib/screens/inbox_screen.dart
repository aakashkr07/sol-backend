import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/notification_hooks_service.dart';
import '../services/session_bootstrap_service.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────

const Color _bg = Color(0xFF050810);
const Color _surface = Color(0xFF0C1018);
const Color _surfaceUp = Color(0xFF101820);
const Color _amber = Color(0xFFF0952A);
const Color _amberSft = Color(0xFFF5B86A);
const Color _cream = Color(0xFFE4D5BB);
const Color _sand = Color(0xFF9A8C78);
const Color _ink = Color(0xFF030508);

// ─────────────────────────────────────────────────────────────────────────────
// InboxScreen
// ─────────────────────────────────────────────────────────────────────────────

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  // ── State (untouched) ─────────────────────────────────────────────────────
  MyCompanionsResponse? _roster;
  bool _isLoading = true;
  bool _isOpeningThread = false;
  String? _error;

  // ── Lifecycle (untouched) ─────────────────────────────────────────────────
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
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  // ── Data (untouched) ──────────────────────────────────────────────────────
  Future<void> _load({bool silent = false}) async {
    if (!silent)
      setState(() {
        _isLoading = true;
        _error = null;
      });
    try {
      await NotificationHooksService.initialize();
      final roster = await ApiService.getMyCompanions();
      if (!mounted) return;
      setState(() {
        _roster = roster;
        _isLoading = false;
        _error = null;
      });
    } on ChatException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'couldn\'t load. pull to try again.';
      });
    }
  }

  // ── Navigation (untouched) ────────────────────────────────────────────────
  Future<void> _openEntry(InboxEntrySummary entry) async {
    if (_isOpeningThread) return;
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
      if (!mounted || session == null) return;
      SessionBootstrapService.stash(session);
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      );
      if (mounted) await _load(silent: true);
    } on ChatException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isOpeningThread = false);
    }
  }

  Future<void> _openProfile() async {
    final selectedPairId = _roster?.primaryCompanion?.pairId;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(initialPairId: selectedPairId),
      ),
    );
    if (mounted) await _load(silent: true);
  }

  Future<void> _signOut() async => AuthService.signOut();

  // ── Helpers ───────────────────────────────────────────────────────────────
  String? _firstName() {
    final name = _roster?.userName ?? AuthService.currentUserName;
    if (name == null || name.trim().isEmpty) return null;
    return name.trim().split(' ').first;
  }

  // Time-based greeting — more intimate than a static label
  String _greeting() {
    final name = _firstName();
    final h = DateTime.now().hour;
    String base;
    if (h >= 5 && h < 12)
      base = 'good morning';
    else if (h >= 12 && h < 17)
      base = 'good afternoon';
    else if (h >= 17 && h < 22)
      base = 'good evening';
    else
      base = 'still up?';
    return name != null ? '$base, $name.' : 'your threads.';
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _isLoading ? _buildLoader() : _buildBody(),
      ),
    );
  }

  Widget _buildLoader() {
    return Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 1.2,
          valueColor:
              AlwaysStoppedAnimation<Color>(_amberSft.withOpacity(0.60)),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final all = _roster?.inboxEntries ?? const <InboxEntrySummary>[];

    // Same partitioning logic — untouched
    final active = all.where((e) => e.waitingOnUser && !e.isArrival).toList();
    final arrivals = all.where((e) => e.isArrival).toList();
    final quiet = all.where((e) => !e.isArrival && !e.waitingOnUser).toList();

    // Flat priority-ordered list — active first, then arrivals, then quiet
    final ordered = [...active, ...arrivals, ...quiet];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Pinned header — does not scroll ───────────────────────────────
        _buildHeader(),

        // ── Error bar ─────────────────────────────────────────────────────
        if (_error != null) _buildErrorBar(),

        // ── Scrollable area ───────────────────────────────────────────────
        Expanded(
          child: RefreshIndicator(
            color: _amber,
            backgroundColor: _surface,
            displacement: 20,
            onRefresh: _load,
            child: all.isEmpty
                ? _buildEmpty()
                : ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 48),
                    children: [
                      // Stories-style presence strip — only rendered when
                      // there are active (waitingOnUser) threads
                      if (active.isNotEmpty) ...[
                        _buildPresenceStrip(active),
                        // Hairline between strip and thread list
                        Container(
                          height: 0.4,
                          color: _cream.withOpacity(0.05),
                        ),
                      ],

                      // Flat thread list
                      for (var i = 0; i < ordered.length; i++)
                        _InboxTile(
                          entry: ordered[i],
                          opening: _isOpeningThread,
                          isLast: i == ordered.length - 1,
                          onTap: () => _openEntry(ordered[i]),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              _greeting(),
              style: GoogleFonts.cormorantGaramond(
                color: _cream,
                fontSize: 32,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.2,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _iconBtn(Icons.tune_rounded, _openProfile),
          const SizedBox(width: 4),
          _iconBtn(Icons.logout_rounded, _signOut),
        ],
      ),
    );
  }

  // ── Error bar ─────────────────────────────────────────────────────────────
  Widget _buildErrorBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      child: Text(
        _error ?? '',
        style: GoogleFonts.jost(
          color: const Color(0xFFBB7070).withOpacity(0.70),
          fontSize: 11.5,
          fontWeight: FontWeight.w300,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ── Presence strip — Stories-like row of active companions ────────────────
  // Height budget: 6 top + 52 avatar + 7 gap + 14 name + 13 bottom = 92
  Widget _buildPresenceStrip(List<InboxEntrySummary> active) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 13),
        itemCount: active.take(8).length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (context, i) {
          final entry = active[i];
          return GestureDetector(
            onTap: _isOpeningThread ? null : () => _openEntry(entry),
            child: SizedBox(
              width: 56,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar — amber ring signals "active"
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _surface,
                      border: Border.all(
                        color: _amber.withOpacity(0.68),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _amber.withOpacity(0.16),
                          blurRadius: 10,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        entry.companionName.isNotEmpty
                            ? entry.companionName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.cormorantGaramond(
                          color: _cream.withOpacity(0.88),
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.companionName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jost(
                      color: _sand.withOpacity(0.60),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.32),
        Center(
          child: Text(
            'nothing yet.',
            style: GoogleFonts.cormorantGaramond(
              color: _sand.withOpacity(0.28),
              fontSize: 26,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  // ── Icon button ───────────────────────────────────────────────────────────
  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _surface.withOpacity(0.80),
          border: Border.all(
            color: _cream.withOpacity(0.05),
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 15,
          color: _sand.withOpacity(0.55),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InboxTile — a single thread row
//
// Design: iMessage-like flat row. No card border. Left amber accent bar for
// unread. Hairline separator aligned with text content (not avatar edge).
// The warmth is in the Cormorant name, amber timing, and amber glow on avatar.
// ─────────────────────────────────────────────────────────────────────────────

class _InboxTile extends StatelessWidget {
  final InboxEntrySummary entry;
  final bool opening;
  final bool isLast;
  final VoidCallback onTap;

  const _InboxTile({
    required this.entry,
    required this.opening,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = entry.hasUnread;
    final arrival = entry.isArrival;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: opening ? null : onTap,
        splashColor: _amber.withOpacity(0.03),
        highlightColor: _cream.withOpacity(0.015),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Row: accent bar + content ─────────────────────────────────
            Container(
              // Very subtle lifted background for unread threads
              color: unread ? _surfaceUp.withOpacity(0.50) : Colors.transparent,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left accent bar — appears for unread, invisible when read
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 2.5,
                      color: unread
                          ? _amber.withOpacity(0.65)
                          : Colors.transparent,
                    ),

                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Avatar
                            _buildAvatar(unread, arrival),
                            const SizedBox(width: 13),

                            // Text content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Name + timestamp on same baseline
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.companionName,
                                          style: GoogleFonts.cormorantGaramond(
                                            color: _cream.withOpacity(
                                              unread ? 1.0 : 0.62,
                                            ),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w400,
                                            letterSpacing: 0.15,
                                            height: 1.1,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _timeLabel(),
                                        style: GoogleFonts.jost(
                                          color: unread
                                              ? _amber.withOpacity(0.60)
                                              : _sand.withOpacity(0.34),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Social presence / status — subtle mood line
                                  if (entry.socialPresence.isNotEmpty ||
                                      entry.statusText.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      entry.socialPresence.isNotEmpty
                                          ? entry.socialPresence
                                          : entry.statusText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.jost(
                                        color: (unread || arrival)
                                            ? _amberSft.withOpacity(0.58)
                                            : _sand.withOpacity(0.34),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w300,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 5),

                                  // Preview — one line, trails off
                                  Text(
                                    entry.previewText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.jost(
                                      color: _cream.withOpacity(
                                        unread ? 0.62 : 0.32,
                                      ),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w300,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Unread count — small amber pill on right
                            if (entry.unreadCount > 0) ...[
                              const SizedBox(width: 10),
                              _buildBadge(entry.unreadCount),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Hairline separator — aligns with text, not avatar edge ─────
            // Left margin: 2.5 (bar) + 18 (pad) + 50 (avatar) + 13 (gap) = 83.5
            if (!isLast)
              Container(
                height: 0.4,
                margin: const EdgeInsets.only(left: 84),
                color: _cream.withOpacity(0.045),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(bool unread, bool arrival) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _surface,
        border: Border.all(
          color: _amber.withOpacity(
            arrival
                ? 0.55
                : unread
                    ? 0.28
                    : 0.09,
          ),
          width: (arrival || unread) ? 1.2 : 0.5,
        ),
        boxShadow: (unread || arrival)
            ? [
                BoxShadow(
                  color: _amber.withOpacity(0.10),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          entry.companionName.isNotEmpty
              ? entry.companionName[0].toUpperCase()
              : '?',
          style: GoogleFonts.cormorantGaramond(
            color: _cream.withOpacity(0.78),
            fontSize: 22,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(int count) {
    final label = count > 99 ? '99+' : '$count';
    final wide = count > 9;
    return Container(
      width: wide ? null : 20,
      height: 20,
      padding:
          wide ? const EdgeInsets.symmetric(horizontal: 6) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: _amber,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: GoogleFonts.jost(
          color: _ink,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _timeLabel() {
    final stamp = entry.previewDateTime;
    if (stamp == null) return entry.isArrival ? 'new' : '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(stamp.year, stamp.month, stamp.day);
    if (that == today) {
      final h = stamp.hour % 12 == 0 ? 12 : stamp.hour % 12;
      final m = stamp.minute.toString().padLeft(2, '0');
      return '$h:$m ${stamp.hour >= 12 ? 'pm' : 'am'}';
    }
    if (today.difference(that).inDays < 7) {
      const d = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
      return d[stamp.weekday - 1];
    }
    return '${stamp.month}/${stamp.day}';
  }
}
