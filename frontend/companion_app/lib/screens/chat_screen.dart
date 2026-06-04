// =============================================================================
// lib/screens/chat_screen.dart
// Sol · Chat Screen  [VISUAL POLISH — frontend only]
//
// Changes (UI/layout only — zero backend/logic/service changes):
//
//   Typography
//   · All TextStyle declarations migrated to GoogleFonts.inter / .interTight
//     to match login_screen.dart. Companion name uses InterTight w600.
//     Status line, body copy, hints, error copy all use Inter.
//
//   Top bar
//   · Consistent left/right padding (20px each side).
//   · Companion name + status wrapped in Flexible to prevent overflow on long
//     names or when the memory badge is visible.
//   · Avatar border replaced with a softly glowing amber ring (boxShadow +
//     border) matching the login screen's amber warmth treatment.
//   · Memory badge: tighter geometry, amber glow shadow, Inter Tight font.
//   · Icon buttons unified: same 34×34 pill, consistent icon sizes.
//     Sign-out is visually de-emphasised relative to profile (tune).
//
//   Message area
//   · Removed the double BoxDecoration gradient wrapper around ListView.
//     The Scaffold gradient already provides the background depth.
//   · Horizontal ListView padding added (16px each side) so MessageBubble
//     widgets have breathing room against screen edges.
//   · Loading indicator colour uses withValues for
//     clean analyzer diagnostics.
//
//   Error banner
//   · Replaced jarring Colors.redAccent with a muted dustRose palette
//     consistent with the login screen's _dustRose error colour.
//   · Rounded corners increased to 16, border softened.
//
//   Input bar
//   · Removed AnimatedPadding keyboard hack — SafeArea + Scaffold handle
//     insets correctly; the extra 8px caused a visible jump.
//   · Text field background: single border colour token, amber tint on focus.
//   · Send button inactive state uses a subtler surface, not flat _navySurface.
//   · Text field hint and body use Inter for font consistency.
//   · Added ClipRRect around the text field container to hard-clip any
//     overflow from the inner TextField decoration.
//
//   Overflow fixes
//   · TopBar Row: Flexible + overflow: TextOverflow.ellipsis on name.
//   · Input Row: constrained heights prevent unbounded layout.
//   · Error banner Row: Expanded on text, fixed icon sizes.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/message_model.dart';
import '../services/notification_hooks_service.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_bootstrap_service.dart';
import '../services/burst_playback_service.dart';
import 'relationship_studio_screen.dart';
import '../widgets/atmosphere_background.dart';

import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  static String? activeChatCompanionId;

  final SessionStartResponse? initialSession;

  const ChatScreen({
    super.key,
    this.initialSession,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  // ── Palette — mirrors inbox_screen.dart Sol design system ───────────────────
  static const Color _bg = Color(0xFF080A0E); // bgDeep
  static const Color _surface = Color(0xFF10131A); // surface
  static const Color _blue =
      Color(0xFF7DA2FF); // presence blue — emotional core
  static const Color _blueSoft = Color(0xFF8BA8FF); // softer presence
  static const Color _violet = Color(0xFFA78BFA); // depth / vulnerability
  static const Color _cream = Color(0xFFE8DDD0); // typography
  static const Color _sand = Color(0xFF9A8C78); // secondary text
  static const Color _dustRose = Color(0xFFBB7070); // error tint only
  static const Color _borderFaint = Color(0x0DFFFFFF); // white 5%

  // ── State (backend-owned — do not touch) ────────────────────────────────────
  final List<Message> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isSending = false;
  bool _isInitializing = true;
  bool _isAssistantDelivering = false;
  String? _errorMessage;
  String? _conversationId;
  String? _pairId;
  String? _companionId;
  String _companionName = 'Companion';
  int _memoryCount = 0;
  TypingIndicatorSpec? _typingSpec;
  int _assistantPlaybackGeneration = 0;
  DateTime? _draftStartedAt;
  List<ChatItem> _cachedDisplayItems = [];

  void _cacheDisplayItems() {
    _cachedDisplayItems = _buildDisplayItems();
  }

  void _updateCachedDisplayItems() {
    if (!mounted) return;
    setState(_cacheDisplayItems);
  }

  bool get _isTyping => _typingSpec != null;

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationHooksService.onNotificationReceived
        .addListener(_onNotificationReceived);
    NotificationHooksService.setForegroundNotificationOptions(active: true);
    _initialize();
  }

  @override
  void dispose() {
    if (ChatScreen.activeChatCompanionId == _companionId) {
      ChatScreen.activeChatCompanionId = null;
    }
    NotificationHooksService.onNotificationReceived
        .removeListener(_onNotificationReceived);
    NotificationHooksService.setForegroundNotificationOptions(active: false);
    _cancelAssistantPlayback(clearTyping: false);
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Left empty since reverse layout naturally anchors to the bottom of the viewport when keyboard resizes
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPendingProactiveEvents(silent: true);
    }
  }

  void _onNotificationReceived() {
    final notification = NotificationHooksService.onNotificationReceived.value;
    if (notification == null || notification.chatId != _companionId) {
      return;
    }
    _loadPendingProactiveEvents(silent: true);
  }

  // ── Backend calls — untouched ─────────────────────────────────────────────
  Future<void> _initialize() async {
    List<ChatBurst> openingBursts = const [];
    try {
      await NotificationHooksService.initialize();
      final session = widget.initialSession ??
          SessionBootstrapService.consume() ??
          await ApiService.startSession(resumeExisting: true);
      if (session != null && mounted) {
        _applySession(session);
        if (session.historyMessages.isNotEmpty) {
          final hist = session.historyMessages
              .map(
                (message) => Message.fromHistory(
                  role: message.role,
                  content: message.content,
                  createdAt: message.createdAt,
                  parentMessageId: message.parentMessageId,
                ),
              )
              .toList();
          _messages
            ..clear()
            ..addAll(hist.reversed);
          _cacheDisplayItems();
        } else if (session.openingBursts.isNotEmpty ||
            session.openingMessage.trim().isNotEmpty) {
          openingBursts = session.openingBursts.isNotEmpty
              ? session.openingBursts
              : [ChatBurst.single(session.openingMessage)];

          if (_pairId != null) {
            await BurstPlaybackService.saveBursts(_pairId!, openingBursts);
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'couldn\'t start a fresh session. you can still try messaging.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }

    List<ChatBurst> burstsToPlay = const [];
    if (mounted && _pairId != null) {
      final hasUnplayed =
          await BurstPlaybackService.hasUnplayedBursts(_pairId!);
      if (hasUnplayed) {
        burstsToPlay =
            await BurstPlaybackService.getStoredBurstsAsChatBursts(_pairId!);
      } else if (_messages.isEmpty && openingBursts.isNotEmpty) {
        burstsToPlay = openingBursts;
      }
    }

    if (mounted && burstsToPlay.isNotEmpty) {
      await _playCompanionBursts(burstsToPlay);
    }

    _updateCachedDisplayItems();

    await _loadPendingProactiveEvents(silent: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottom();
      }
    });
  }

  void _applySession(SessionStartResponse session) {
    if (!mounted) return;
    setState(() {
      _conversationId = session.conversationId;
      _pairId = session.pairId;
      _companionId = session.companionId;
      _companionName = session.companionName;
      _memoryCount = session.memoryCount;
    });
    ChatScreen.activeChatCompanionId = session.companionId;
    unawaited(NotificationService.markChatRead(session.companionId));
  }

  String? _getFirstName() {
    final name = AuthService.currentUserName;
    if (name == null || name.trim().isEmpty) return null;
    return name.trim().split(' ').first;
  }

  void _cancelAssistantPlayback({bool clearTyping = true}) {
    _assistantPlaybackGeneration += 1;
    if (!clearTyping) {
      _typingSpec = null;
      _isAssistantDelivering = false;
      return;
    }
    if (!mounted) {
      _typingSpec = null;
      _isAssistantDelivering = false;
      return;
    }
    setState(() {
      _typingSpec = null;
      _isAssistantDelivering = false;
    });
  }

  Future<void> _playCompanionBursts(
    List<ChatBurst> bursts, {
    int networkElapsedMs = 0,
  }) async {
    final playbackId = ++_assistantPlaybackGeneration;
    final plannedBursts =
        bursts.isNotEmpty ? bursts : [ChatBurst.single('...')];

    if (mounted) {
      setState(() {
        _typingSpec = null;
        _isAssistantDelivering = true;
      });
    }

    final stored = _pairId != null
        ? await BurstPlaybackService.getStoredBursts(_pairId!)
        : const <Map<String, dynamic>>[];

    for (var i = 0; i < plannedBursts.length; i++) {
      if (!mounted || playbackId != _assistantPlaybackGeneration) return;

      if (stored.isNotEmpty &&
          i < stored.length &&
          stored[i]['is_played'] == true) {
        continue;
      }

      final burst = plannedBursts[i];
      final thinkDelayMs = i == 0
          ? _effectiveFirstBurstDelay(burst, networkElapsedMs)
          : burst.preBurstDelayMs;

      if (thinkDelayMs > 0) {
        if (mounted) setState(() => _typingSpec = null);
        await Future.delayed(Duration(milliseconds: thinkDelayMs));
      }
      if (!mounted || playbackId != _assistantPlaybackGeneration) return;

      if (mounted) {
        setState(() {
          _typingSpec = TypingIndicatorSpec(
            typingDurationMs: burst.typingDurationMs,
            pauseIntensity: burst.pauseIntensity,
            isFollowUp: burst.isFollowUp,
            isNetworkPending: false,
          );
          _isAssistantDelivering = true;
        });
      }
      await Future.delayed(Duration(milliseconds: burst.typingDurationMs));
      if (!mounted || playbackId != _assistantPlaybackGeneration) return;

      setState(() {
        _typingSpec = null;
        _messages.insert(
          0,
          Message.fromCompanion(burst.text, startsNewGroup: burst.isFollowUp),
        );
        _cacheDisplayItems();
      });
      _scrollToBottom();

      if (_pairId != null) {
        await BurstPlaybackService.markBurstPlayed(_pairId!, i);
      }
    }

    if (mounted && playbackId == _assistantPlaybackGeneration) {
      setState(() {
        _typingSpec = null;
        _isAssistantDelivering = false;
      });
    }
  }

  int _effectiveFirstBurstDelay(ChatBurst burst, int networkElapsedMs) {
    final compensated = burst.preBurstDelayMs - networkElapsedMs;
    return compensated <= 80 ? 80 : compensated;
  }

  String _relationshipButtonLabel() {
    final parts = _companionName.trim().split(RegExp(r'\s+'));
    final first = parts.isEmpty || parts.first.isEmpty ? 'sol' : parts.first;
    return 'you & ${first.toLowerCase()}';
  }

  void _openRelationshipStudio() {
    final pairId = _pairId;
    if (pairId == null || pairId.isEmpty) {
      _showNotice('relationship record is still loading.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RelationshipStudioScreen(
          pairId: pairId,
          companionName: _companionName,
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending || _isAssistantDelivering) return;

    final clientSentAt = DateTime.now();
    final draftDurationMs = _draftStartedAt == null
        ? null
        : clientSentAt
            .difference(_draftStartedAt!)
            .inMilliseconds
            .clamp(0, 600000)
            .toInt();
    final replyLatencyMs = _latestAssistantTimestamp() == null
        ? null
        : clientSentAt
            .difference(_latestAssistantTimestamp()!)
            .inMilliseconds
            .clamp(0, 86400000)
            .toInt();

    final userMessage = Message.fromUser(text);
    _inputController.clear();
    _draftStartedAt = null;
    _inputFocusNode.requestFocus();
    HapticFeedback.lightImpact();

    setState(() {
      _messages.insert(0, userMessage);
      _isSending = true;
      _isAssistantDelivering = true;
      _typingSpec = TypingIndicatorSpec.network();
      _errorMessage = null;
      _cacheDisplayItems();
    });

    _scrollToBottom();
    final requestStartedAt = DateTime.now();

    try {
      final response = await ApiService.sendMessage(
        message: text,
        conversationId: _conversationId,
        characterId: _companionId,
        clientSentAt: clientSentAt.toIso8601String(),
        draftDurationMs: draftDurationMs,
        replyLatencyMs: replyLatencyMs,
      );

      if (!mounted) return;

      final networkElapsedMs =
          DateTime.now().difference(requestStartedAt).inMilliseconds;
      setState(() {
        _conversationId = response?.conversationId ?? _conversationId;
        _pairId = response?.pairId ?? _pairId;
        _companionId = response?.companionId ?? _companionId;
        _companionName = response?.companionName ?? _companionName;
        _memoryCount = response?.memoryCount ?? _memoryCount;
        _isSending = false;
        _replaceMessageStatus(userMessage.id, MessageStatus.read);
        _cacheDisplayItems();
      });

      if (response != null) {
        final responseBursts = response.bursts.isNotEmpty
            ? response.bursts
            : (response.reply.trim().isEmpty
                ? const <ChatBurst>[]
                : [ChatBurst.single(response.reply)]);

        if (responseBursts.isEmpty) {
          _cancelAssistantPlayback();
          HapticFeedback.selectionClick();
          _scrollToBottom();
          return;
        }

        if (_pairId != null) {
          await BurstPlaybackService.saveBursts(_pairId!, responseBursts);
        }
        await _playCompanionBursts(
          responseBursts,
          networkElapsedMs: networkElapsedMs,
        );
      } else {
        _cancelAssistantPlayback();
      }
      HapticFeedback.selectionClick();
      _scrollToBottom();
    } on ChatException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _typingSpec = null;
        _isAssistantDelivering = false;
        _replaceMessageStatus(userMessage.id, MessageStatus.failed);
        if (e.statusCode == 503) {
          _errorMessage =
              "${_companionName.toLowerCase()}'s quiet right now. try again.";
        } else if (e.statusCode == 422) {
          _errorMessage =
              'request validation failed (${e.statusCode}): ${e.message}';
        } else if (e.statusCode > 0) {
          _errorMessage = 'server error (${e.statusCode}): ${e.message}';
        } else {
          _errorMessage = 'something went wrong. try again.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _typingSpec = null;
        _isAssistantDelivering = false;
        _replaceMessageStatus(userMessage.id, MessageStatus.failed);
        _errorMessage = 'connection lost. check your network.';
      });
    }
  }

  DateTime? _latestAssistantTimestamp() {
    for (var i = 0; i < _messages.length; i++) {
      if (!_messages[i].isUser) return _messages[i].timestamp;
    }
    return null;
  }

  Future<void> _loadPendingProactiveEvents({required bool silent}) async {
    try {
      final events = await ApiService.getPendingProactiveEvents();
      if (!mounted || events.isEmpty) return;

      final currentPairEvents =
          events.where((e) => _pairId != null && e.pairId == _pairId).toList();
      for (final event in currentPairEvents) {
        if (event.conversationId.isNotEmpty) {
          _conversationId = event.conversationId;
        }
        if (event.bursts.isNotEmpty) {
          if (_pairId != null) {
            await BurstPlaybackService.saveBursts(_pairId!, event.bursts);
          }
          await _playCompanionBursts(event.bursts);
        }
      }

      final otherEvents = events.where((e) => e.pairId != _pairId).toList();
      if (otherEvents.isNotEmpty && !silent) {
        _showNotice(
            '${otherEvents.first.companionName} left something in your inbox.');
      } else if (otherEvents.isNotEmpty && silent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showNotice(
                '${otherEvents.first.companionName} left something in your inbox.');
          }
        });
      }
    } catch (_) {}
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF141B2D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            color: _cream.withValues(alpha: 0.85),
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  void _replaceMessageStatus(String id, MessageStatus status) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index == -1) return;
    _messages[index] = _messages[index].copyWith(status: status, isNew: false);
    _cacheDisplayItems();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  bool _isFirstInGroup(int index) {
    if (index == _messages.length - 1) return true;
    return _messages[index].role != _messages[index + 1].role ||
        _messages[index].startsNewGroup;
  }

  bool _isLastInGroup(int index) {
    if (index == 0) return true;
    return _messages[index].role != _messages[index - 1].role ||
        _messages[index - 1].startsNewGroup;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final compareDate = DateTime(date.year, date.month, date.day);
    if (compareDate == today) {
      return 'Today';
    } else if (compareDate == yesterday) {
      return 'Yesterday';
    } else {
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }

  List<ChatItem> _buildDisplayItems() {
    final List<ChatItem> items = [];
    if (_messages.isEmpty) return items;
    for (int i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      items.add(MessageItem(msg, _isFirstInGroup(i), _isLastInGroup(i)));
      final msgDate =
          DateTime(msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);
      if (i == _messages.length - 1) {
        items.add(DateHeaderItem(_formatDateHeader(msg.timestamp)));
      } else {
        final nextMsg = _messages[i + 1];
        final nextMsgDate = DateTime(nextMsg.timestamp.year,
            nextMsg.timestamp.month, nextMsg.timestamp.day);
        if (msgDate != nextMsgDate) {
          items.add(DateHeaderItem(_formatDateHeader(msg.timestamp)));
        }
      }
    }
    return items;
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bg,
        // Scaffold handles keyboard insets — no manual AnimatedPadding needed
        resizeToAvoidBottomInset: true,
        body: AtmosphereBackground(
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildMessageArea()),
                if (_errorMessage != null) _buildErrorBanner(),
                _buildInputBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    final firstName = _getFirstName();
    final canPop = Navigator.of(context).canPop();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
      decoration: BoxDecoration(
        // Slightly lighter than the gradient base to lift the bar
        color: _bg.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(color: _borderFaint, width: 0.8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Back button (only when nested) ──────────────────────────────
          if (canPop) ...[
            _IconButton(
              icon: Icons.arrow_back_rounded,
              size: 18,
              onTap: () => Navigator.of(context).maybePop(),
              opacity: 0.55,
            ),
            const SizedBox(width: 10),
          ],

          // ── Avatar ───────────────────────────────────────────────────────
          _buildCompanionAvatar(),
          const SizedBox(width: 12),

          // ── Name + status — Flexible prevents overflow ───────────────────
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _companionName,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFEEE8DF),
                    letterSpacing: -0.3,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isTyping
                      ? 'typing…'
                      : firstName != null
                          ? 'here with $firstName'
                          : 'here with you',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    color: _isTyping
                        ? _blue.withValues(alpha: 0.60)
                        : Colors.white.withValues(alpha: 0.32),
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          _relationshipPill(),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ── Companion avatar — initial letter, WhatsApp style ───────────────────────
  Widget _buildCompanionAvatar() {
    final initial =
        _companionName.isNotEmpty ? _companionName[0].toUpperCase() : 'S';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _surface,
        border: Border.all(
          color: _blue.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: _blue.withValues(alpha: 0.18),
            blurRadius: 14,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.plusJakartaSans(
            color: _cream.withValues(alpha: 0.85),
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  // Relationship shortcut
  Widget _relationshipPill() {
    return GestureDetector(
      onTap: _openRelationshipStudio,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 128, minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: _blue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _blue.withValues(alpha: 0.20), width: 0.7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _memoryCount > 0
                  ? Icons.auto_awesome_rounded
                  : Icons.favorite_border_rounded,
              color: _blue.withValues(alpha: 0.78),
              size: 14,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _relationshipButtonLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jost(
                  color: _cream.withValues(alpha: 0.88),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Message area ─────────────────────────────────────────────────────────────
  Widget _buildMessageArea() {
    if (_isInitializing) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.0,
          valueColor: AlwaysStoppedAnimation<Color>(
            _blue.withValues(alpha: 0.45),
          ),
        ),
      );
    }

    final displayItems = _cachedDisplayItems;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      clipBehavior:
          Clip.hardEdge, // prevents avatar/label clipping at item boundaries
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      itemCount: displayItems.length + (_typingSpec != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (_typingSpec != null && index == 0) {
          return TypingIndicator(
            key: ValueKey(
              '${_typingSpec!.pauseIntensity}-'
              '${_typingSpec!.typingDurationMs}-'
              '${_typingSpec!.isFollowUp}-'
              '${_typingSpec!.isNetworkPending}-'
              '$_assistantPlaybackGeneration',
            ),
            spec: _typingSpec!,
            companionName: _companionName,
          );
        }

        final item = displayItems[_typingSpec != null ? index - 1 : index];
        if (item is DateHeaderItem) {
          return Center(
            key: ValueKey('date_${item.dateText}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                    width: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.dateText.toLowerCase(),
                  style: GoogleFonts.jost(
                    color: _sand,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          );
        } else if (item is MessageItem) {
          final message = item.message;
          return MessageBubble(
            key: ValueKey(message.id),
            message: message,
            isNew: message.isNew,
            isFirst: item.isFirst,
            isLast: item.isLast,
            showAvatar: !message.isUser && item.isLast,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  // ── Error banner ─────────────────────────────────────────────────────────────
  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _dustRose.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _dustRose.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              color: _dustRose.withValues(alpha: 0.75),
              size: 15,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: GoogleFonts.plusJakartaSans(
                color: _dustRose.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: Icon(
              Icons.close_rounded,
              color: _dustRose.withValues(alpha: 0.50),
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ── Input bar ────────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    final hasText = _inputController.text.trim().isNotEmpty;
    final canSend = hasText && !_isSending && !_isAssistantDelivering;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: _bg.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: _borderFaint, width: 0.8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Text field ───────────────────────────────────────────────────
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 44,
                  maxHeight: 120,
                ),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: hasText
                        ? _blue.withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.06),
                    width: 0.8,
                  ),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: _blue,
                  cursorWidth: 1.4,
                  selectionControls: materialTextSelectionControls,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 15,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText: 'say something…',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.20),
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (value) {
                    if (value.trim().isNotEmpty && _draftStartedAt == null) {
                      _draftStartedAt = DateTime.now();
                    }
                    if (value.trim().isEmpty) _draftStartedAt = null;
                    setState(() {});
                  },
                  onTap: _scrollToBottom,
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // ── Send button ──────────────────────────────────────────────────
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: canSend ? 1.0 : 0.28,
            child: GestureDetector(
              onTap: canSend ? _sendMessage : null,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: canSend
                        ? [_blue, _blueSoft]
                        : [
                            Colors.white.withValues(alpha: 0.10),
                            Colors.white.withValues(alpha: 0.06),
                          ],
                  ),
                  boxShadow: canSend
                      ? [
                          BoxShadow(
                            color: _blue.withValues(alpha: 0.30),
                            blurRadius: 16,
                            spreadRadius: 0,
                          ),
                          BoxShadow(
                            color: _violet.withValues(alpha: 0.14),
                            blurRadius: 24,
                            spreadRadius: 0,
                          ),
                        ]
                      : const [],
                ),
                child: Center(
                  child: Icon(
                    _isSending
                        ? Icons.schedule_send_rounded
                        : Icons.arrow_upward_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _IconButton — shared pill icon button, keeps the top bar DRY
// ─────────────────────────────────────────────────────────────────────────────

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.size,
    required this.onTap,
    this.opacity = 0.45,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    const baseColor = Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.04),
          ),
          child: Icon(
            icon,
            size: size,
            color: baseColor.withValues(alpha: opacity),
          ),
        ),
      ),
    );
  }
}

abstract class ChatItem {}

class DateHeaderItem extends ChatItem {
  final String dateText;
  DateHeaderItem(this.dateText);
}

class MessageItem extends ChatItem {
  final Message message;
  final bool isFirst;
  final bool isLast;
  MessageItem(this.message, this.isFirst, this.isLast);
}
