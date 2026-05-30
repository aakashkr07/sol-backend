import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
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
// Palette — Sol Design System
// ─────────────────────────────────────────────────────────────────────────────

// Base backgrounds — breathable deep darks, never pure black
const Color _bgDeep = Color(0xFF080A0E);
const Color _surface = Color(0xFF10131A);
const Color _surfaceUp = Color(0xFF141720);

// Presence Blue — emotional core, used sparingly
const Color _blue = Color(0xFF7DA2FF);
const Color _blueSoft = Color(0xFF8BA8FF);

// Warm Violet — vulnerability and emotional depth
const Color _violet = Color(0xFFA78BFA);
const Color _violetSoft = Color(0xFFB69CFF);

// Human Warmth — amber/peach, used very subtly
const Color _amber = Color(0xFFF2B8A0);

// Typography
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);
const Color _dusty = Color(0xFF5A5568);
const Color _ink = Color(0xFF060810);

// ─────────────────────────────────────────────────────────────────────────────
// InboxScreen
// ─────────────────────────────────────────────────────────────────────────────

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── State (untouched) ─────────────────────────────────────────────────────
  MyCompanionsResponse? _roster;
  bool _isLoading = true;
  bool _isOpeningThread = false;
  String? _error;

  // ── Animation controllers ─────────────────────────────────────────────────
  late AnimationController _breatheCtrl;
  late AnimationController _fadeInCtrl;
  late Animation<double> _breatheAnim;
  late Animation<double> _fadeInAnim;

  late final Animation<double> _blueOpacity;
  late final Animation<double> _violetOpacity;
  late final Animation<double> _amberOpacity;

  // ── Lifecycle (untouched) ─────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _breatheAnim = CurvedAnimation(
      parent: _breatheCtrl,
      curve: Curves.easeInOut,
    );

    _blueOpacity = Tween<double>(begin: 0.028, end: 0.046).animate(_breatheAnim);
    _violetOpacity = Tween<double>(begin: 0.038, end: 0.022).animate(_breatheAnim);
    _amberOpacity = Tween<double>(begin: 0.014, end: 0.024).animate(_breatheAnim);

    _fadeInCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeInAnim = CurvedAnimation(
      parent: _fadeInCtrl,
      curve: Curves.easeOut,
    );

    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _breatheCtrl.dispose();
    _fadeInCtrl.dispose();
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
      _fadeInCtrl.forward(from: 0);
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
      backgroundColor: _bgDeep,
      body: Stack(
        children: [
          // ── Atmospheric breathing background ──────────────────────────
          _buildAtmosphere(),

          // ── Global glassmorphic blur overlay ──────────────────────────
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: const SizedBox.shrink(),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────
          SafeArea(
            child: _isLoading ? _buildLoader() : _buildBody(),
          ),
        ],
      ),
    );
  }

  // ── Atmospheric background — subtle breathing gradient orbs ───────────────
  Widget _buildAtmosphere() {
    return Stack(
      children: [
        // Base deep background fill
        Positioned.fill(
          child: Container(
            color: const Color(0xFF080A0E),
          ),
        ),
        // Orb 1 — presence blue (top-left)
        Positioned.fill(
          child: FadeTransition(
            opacity: _blueOpacity,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: FractionalOffset(0.15, 0.12),
                  radius: 0.65,
                  colors: [
                    Color(0xFF7DA2FF),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Orb 2 — warm violet (bottom-right)
        Positioned.fill(
          child: FadeTransition(
            opacity: _violetOpacity,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: FractionalOffset(0.88, 0.72),
                  radius: 0.75,
                  colors: [
                    Color(0xFFA78BFA),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Orb 3 — center-bottom, human warmth (bottom-center)
        Positioned.fill(
          child: FadeTransition(
            opacity: _amberOpacity,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: FractionalOffset(0.50, 0.95),
                  radius: 0.55,
                  colors: [
                    Color(0xFFF2B8A0),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Loader ────────────────────────────────────────────────────────────────
  Widget _buildLoader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.0,
              valueColor: AlwaysStoppedAnimation<Color>(
                _blue.withOpacity(0.62),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'gathering presence…',
            style: GoogleFonts.plusJakartaSans(
              color: _sand.withOpacity(0.38),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    final all = _roster?.inboxEntries ?? const <InboxEntrySummary>[];

    final active = all.where((e) => e.waitingOnUser && !e.isArrival).toList();
    final arrivals = all.where((e) => e.isArrival).toList();
    final quiet = all.where((e) => !e.isArrival && !e.waitingOnUser).toList();
    final ordered = [...active, ...arrivals, ...quiet];
    final threads = all.where((e) => !e.isArrival).toList();

    return FadeTransition(
      opacity: _fadeInAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_error != null) _buildErrorBar(),
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
                      padding: const EdgeInsets.only(bottom: 60),
                      children: [
                        if (threads.isNotEmpty) ...[
                          _buildPresenceStrip(threads),
                          _buildSectionDivider(),
                        ],
                        if (arrivals.isNotEmpty) ...[
                          _buildSectionLabel('new arrivals'),
                        ],
                        for (var i = 0; i < ordered.length; i++)
                          _InboxTile(
                            entry: ordered[i],
                            opening: _isOpeningThread,
                            isLast: i == ordered.length - 1,
                            index: i,
                            onTap: () => _openEntry(ordered[i]),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 18, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tiny Sol wordmark / eyebrow label
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _blue.withOpacity(0.70),
                        boxShadow: [
                          BoxShadow(
                            color: _blue.withOpacity(0.62),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'sol',
                      style: GoogleFonts.jost(
                        color: _sand.withOpacity(0.58),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Greeting
                Text(
                  _greeting(),
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withOpacity(0.92),
                    fontSize: 26,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.3,
                    height: 1.12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Icon buttons — glass morphism style
          _iconBtn(Icons.tune_rounded, _openProfile),
          const SizedBox(width: 8),
          _iconBtn(Icons.logout_rounded, _signOut),
        ],
      ),
    );
  }

  // ── Error bar ─────────────────────────────────────────────────────────────
  Widget _buildErrorBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE07070).withOpacity(0.60),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _error ?? '',
            style: GoogleFonts.jost(
              color: const Color(0xFFBB7070).withOpacity(0.65),
              fontSize: 11.5,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section divider ───────────────────────────────────────────────────────
  Widget _buildSectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 0.4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    _cream.withOpacity(0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: Text(
        label,
        style: GoogleFonts.jost(
          color: _violet.withOpacity(0.68),
          fontSize: 10.5,
          fontWeight: FontWeight.w400,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  // ── Presence strip — Stories-style horizontal scroll ─────────────────────
  Widget _buildPresenceStrip(List<InboxEntrySummary> threads) {
    final list = threads.take(8).toList();
    return RepaintBoundary(
      child: SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 20),
          itemBuilder: (context, i) {
            final entry = list[i];
            return GestureDetector(
              onTap: _isOpeningThread ? null : () => _openEntry(entry),
              child: SizedBox(
                width: 58,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Avatar with animated presence ring
                    _PresenceAvatar(entry: entry),
                    const SizedBox(height: 7),
                    Text(
                      entry.companionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jost(
                        color: _sand.withOpacity(0.78),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.30),
        Center(
          child: Column(
            children: [
              // Soft orb
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _blue.withOpacity(0.12),
                      Colors.transparent,
                    ],
                  ),
                  border: Border.all(
                    color: _blue.withOpacity(0.10),
                    width: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'nothing yet.',
                style: GoogleFonts.plusJakartaSans(
                  color: _sand.withOpacity(0.42),
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'your connections will appear here.',
                style: GoogleFonts.jost(
                  color: _dusty.withOpacity(0.68),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Icon button — glassmorphic ─────────────────────────────────────────────
  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _surface.withOpacity(0.70),
          border: Border.all(
            color: _cream.withOpacity(0.08),
            width: 0.6,
          ),
        ),
        child: Icon(
          icon,
          size: 15,
          color: _sand.withOpacity(0.72),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _getAvatarGradient — elegant, name-derived deep linear gradients
// ─────────────────────────────────────────────────────────────────────────────

LinearGradient _getAvatarGradient(String name, bool isArrival) {
  if (isArrival) {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF241544), // Deep Violet
        Color(0xFF0F0B1E), // Deep Dark Indigo
      ],
    );
  }
  final hash = name.codeUnits.fold<int>(0, (prev, element) => prev + element);
  final index = hash % 4;
  switch (index) {
    case 0:
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF132242), Color(0xFF0A1224)],
      );
    case 1:
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF221642), Color(0xFF0F0A24)],
      );
    case 2:
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF331E18), Color(0xFF1B0F0C)],
      );
    default:
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF152626), Color(0xFF0B1414)],
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PresenceDot — miniature glowing and breathing connection indicator
// ─────────────────────────────────────────────────────────────────────────────

class _PresenceDot extends StatefulWidget {
  final bool isTyping;
  const _PresenceDot({super.key, required this.isTyping});

  @override
  State<_PresenceDot> createState() => _PresenceDotState();
}

class _PresenceDotState extends State<_PresenceDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isTyping ? _violetSoft : _blueSoft;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final glow = _pulse.value;
          return Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _bgDeep,
            ),
            alignment: Alignment.center,
            child: Container(
              width: 8.5,
              height: 8.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.35 + glow * 0.45),
                    blurRadius: 3 + glow * 5,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BouncingDots — lightweight fluid typing circles
// ─────────────────────────────────────────────────────────────────────────────

class _BouncingDots extends StatefulWidget {
  const _BouncingDots({super.key});

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final t = (_controller.value - delay) % 1.0;
            final bounce = math.sin(t * math.pi).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              width: 3.5,
              height: 3.5,
              transform: Matrix4.translationValues(0, -bounce * 3.2, 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _blueSoft.withOpacity(0.42 + (1.0 - bounce) * 0.58),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PresenceAvatar — pulsing ring for active companions
// ─────────────────────────────────────────────────────────────────────────────

class _PresenceAvatar extends StatefulWidget {
  final InboxEntrySummary entry;
  const _PresenceAvatar({super.key, required this.entry});

  @override
  State<_PresenceAvatar> createState() => _PresenceAvatarState();
}

class _PresenceAvatarState extends State<_PresenceAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.entry.companionName;
    final unread = widget.entry.unreadCount > 0;
    final waiting = widget.entry.waitingOnUser;
    final isOnline = unread || waiting;

    final gradient = _getAvatarGradient(name, false);
    final ringColor = unread
        ? _blue.withOpacity(0.55)
        : waiting
            ? _blueSoft.withOpacity(0.35)
            : _cream.withOpacity(0.07);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = _pulse.value;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: isOnline
                    ? [
                        BoxShadow(
                          color: _blue.withOpacity(0.06 + glow * 0.14),
                          blurRadius: 10 + glow * 6,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: gradient,
                  border: Border.all(
                    color: ringColor,
                    width: isOnline ? 1.5 : 0.8,
                  ),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.plusJakartaSans(
                      color: _cream.withOpacity(isOnline ? 0.90 : 0.48),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            if (isOnline)
              const Positioned(
                right: 0,
                bottom: 0,
                child: _PresenceDot(isTyping: false),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InboxTile — a single thread row
// ─────────────────────────────────────────────────────────────────────────────

class _InboxTile extends StatefulWidget {
  final InboxEntrySummary entry;
  final bool opening;
  final bool isLast;
  final int index;
  final VoidCallback onTap;

  const _InboxTile({
    required this.entry,
    required this.opening,
    required this.isLast,
    required this.index,
    required this.onTap,
  });

  @override
  State<_InboxTile> createState() => _InboxTileState();
}

class _InboxTileState extends State<_InboxTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;
  bool _pressed = false;
  bool _isTyping = false;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500 + widget.index * 40),
    );
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));

    // Staggered entrance
    Future.delayed(Duration(milliseconds: widget.index * 55), () {
      if (mounted) _entryCtrl.forward();
    });

    _initTypingSimulation();
  }

  void _initTypingSimulation() {
    if (widget.entry.isArrival) return;
    final random = math.Random();
    _typingTimer = Timer.periodic(Duration(seconds: 14 + random.nextInt(10)), (timer) {
      if (!mounted || widget.opening) return;
      final isCompanionActive = widget.entry.waitingOnUser || (random.nextDouble() < 0.12);
      if (isCompanionActive && !_isTyping) {
        setState(() => _isTyping = true);
        Timer(Duration(seconds: 4 + random.nextInt(4)), () {
          if (mounted) {
            setState(() => _isTyping = false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _entryCtrl.dispose();
    super.dispose();
  }

  String _getFormattedPreviewText() {
    final preview = widget.entry.previewText;
    if (widget.entry.isArrival) return preview;
    if (widget.entry.latestRole == 'user') {
      return 'You: $preview';
    }
    return preview;
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.entry.hasUnread;
    final arrival = widget.entry.isArrival;

    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            if (!widget.opening) widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: arrival
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
                : EdgeInsets.zero,
            padding: arrival ? const EdgeInsets.only(right: 6) : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: _pressed
                  ? _cream.withOpacity(0.018)
                  : arrival
                      ? _surfaceUp.withOpacity(0.24)
                      : unread
                          ? _surfaceUp.withOpacity(0.38)
                          : Colors.transparent,
              border: arrival
                  ? Border.all(
                      color: _violet.withOpacity(0.08),
                      width: 0.8,
                    )
                  : null,
              borderRadius: arrival ? BorderRadius.circular(16) : null,
              boxShadow: arrival
                  ? [
                      BoxShadow(
                        color: _violet.withOpacity(0.025),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Left accent bar ──────────────────────────────
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: arrival ? 0.0 : 2.0,
                        decoration: BoxDecoration(
                          gradient: unread
                              ? LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    _blue.withOpacity(0.70),
                                    _blue.withOpacity(0.20),
                                  ],
                                )
                              : null,
                          color: unread ? null : Colors.transparent,
                        ),
                      ),

                      // ── Content ──────────────────────────────────────
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(arrival ? 16 : 20, 16, 18, 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildAvatar(unread, arrival),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Name + timestamp
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            widget.entry.companionName,
                                            style: GoogleFonts.plusJakartaSans(
                                              color: _cream.withOpacity(
                                                unread ? 0.96 : 0.78,
                                              ),
                                              fontSize: 15,
                                              fontWeight: unread
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              letterSpacing: -0.1,
                                              height: 1.15,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _timeLabel(),
                                          style: GoogleFonts.jost(
                                            color: unread
                                                ? (arrival
                                                    ? _violet.withOpacity(0.65)
                                                    : _blue.withOpacity(0.60))
                                                : _sand.withOpacity(0.30),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w400,
                                            letterSpacing: 0.1,
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Social presence / mood line
                                    if (widget
                                            .entry.socialPresence.isNotEmpty ||
                                        widget.entry.statusText.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        widget.entry.socialPresence.isNotEmpty
                                            ? widget.entry.socialPresence
                                            : widget.entry.statusText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.jost(
                                          color: (unread || arrival)
                                              ? (arrival
                                                  ? _violetSoft
                                                      .withOpacity(0.52)
                                                  : _amber.withOpacity(0.52))
                                              : _sand.withOpacity(0.46),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w400,
                                          letterSpacing: 0.15,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 5),

                                    // Preview text or Typing indicator
                                    if (_isTyping)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2.0),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              'typing',
                                              style: GoogleFonts.jost(
                                                color: _blueSoft.withOpacity(0.85),
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w500,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            const _BouncingDots(),
                                          ],
                                        ),
                                      )
                                    else
                                      Text(
                                        _getFormattedPreviewText(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.jost(
                                          color: _cream.withOpacity(
                                            unread ? 0.78 : 0.52,
                                          ),
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w400,
                                          height: 1.45,
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Unread badge
                              if (widget.entry.unreadCount > 0) ...[
                                const SizedBox(width: 10),
                                _buildBadge(widget.entry.unreadCount, arrival),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Hairline separator
                if (!widget.isLast && !arrival)
                  Container(
                    height: 0.4,
                    margin: const EdgeInsets.only(left: 86),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _cream.withOpacity(0.055),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(bool unread, bool arrival) {
    final gradient = _getAvatarGradient(widget.entry.companionName, arrival);
    final ringColor = arrival
        ? _violet.withOpacity(unread ? 0.65 : 0.22)
        : unread
            ? _blue.withOpacity(0.55)
            : _cream.withOpacity(0.07);

    final ringWidth = (arrival || unread) ? 1.3 : 0.6;
    final isOnline = !arrival && (widget.entry.waitingOnUser || _isTyping || widget.entry.unreadCount > 0);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradient,
            border: Border.all(color: ringColor, width: ringWidth),
            boxShadow: (unread || arrival)
                ? [
                    BoxShadow(
                      color: arrival
                          ? _violet.withOpacity(0.12)
                          : _blue.withOpacity(0.14),
                      blurRadius: 14,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              widget.entry.companionName.isNotEmpty
                  ? widget.entry.companionName[0].toUpperCase()
                  : '?',
              style: GoogleFonts.plusJakartaSans(
                color: _cream.withOpacity(unread ? 0.85 : 0.48),
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: -1,
            bottom: -1,
            child: _PresenceDot(isTyping: _isTyping),
          ),
      ],
    );
  }

  Widget _buildBadge(int count, bool arrival) {
    final label = count > 99 ? '99+' : '$count';
    final wide = count > 9;

    return Container(
      width: wide ? null : 20,
      height: 20,
      padding:
          wide ? const EdgeInsets.symmetric(horizontal: 6) : EdgeInsets.zero,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: arrival ? [_violet, _violetSoft] : [_blue, _blueSoft],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: (arrival ? _violet : _blue).withOpacity(0.30),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: GoogleFonts.jost(
          color: _ink.withOpacity(0.85),
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _timeLabel() {
    final stamp = widget.entry.previewDateTime;
    if (stamp == null) return widget.entry.isArrival ? 'new' : '';
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


