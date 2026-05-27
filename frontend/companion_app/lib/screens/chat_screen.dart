import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message_model.dart';
import '../services/notification_hooks_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_bootstrap_service.dart';
import 'profile_screen.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  final SessionStartResponse? initialSession;

  const ChatScreen({
    super.key,
    this.initialSession,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const Color _navy = Color(0xFF0A0E1A);
  static const Color _navySurface = Color(0xFF111827);
  static const Color _amber = Color(0xFFF5A623);
  static const Color _stone = Color(0xFFE8DCC8);

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

  bool get _isTyping => _typingSpec != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    _cancelAssistantPlayback(clearTyping: false);
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPendingProactiveEvents(silent: true);
    }
  }

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
          _messages
            ..clear()
            ..addAll(
              session.historyMessages
                  .map(
                    (message) => Message.fromHistory(
                      role: message.role,
                      content: message.content,
                      createdAt: message.createdAt,
                    ),
                  )
                  .toList(),
            );
        } else if (session.openingBursts.isNotEmpty || session.openingMessage.trim().isNotEmpty) {
          openingBursts = session.openingBursts.isNotEmpty
              ? session.openingBursts
              : [ChatBurst.single(session.openingMessage)];
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'couldn\'t start a fresh session. you can still try messaging.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
    if (mounted && _messages.isEmpty && openingBursts.isNotEmpty) {
      await _playCompanionBursts(openingBursts);
    }
    await _loadPendingProactiveEvents(silent: true);
  }

  void _applySession(SessionStartResponse session) {
    if (!mounted) {
      return;
    }
    setState(() {
      _conversationId = session.conversationId;
      _pairId = session.pairId;
      _companionId = session.companionId;
      _companionName = session.companionName;
      _memoryCount = session.memoryCount;
    });
  }

  String? _getFirstName() {
    final name = AuthService.currentUserName;
    if (name == null || name.trim().isEmpty) {
      return null;
    }
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
    final plannedBursts = bursts.isNotEmpty ? bursts : [ChatBurst.single('...')];

    if (mounted) {
      setState(() {
        _typingSpec = null;
        _isAssistantDelivering = true;
      });
    }

    for (var i = 0; i < plannedBursts.length; i++) {
      if (!mounted || playbackId != _assistantPlaybackGeneration) {
        return;
      }

      final burst = plannedBursts[i];
      final thinkDelayMs =
          i == 0 ? _effectiveFirstBurstDelay(burst, networkElapsedMs) : burst.preBurstDelayMs;
      if (thinkDelayMs > 0) {
        if (mounted) {
          setState(() => _typingSpec = null);
        }
        await Future.delayed(Duration(milliseconds: thinkDelayMs));
      }
      if (!mounted || playbackId != _assistantPlaybackGeneration) {
        return;
      }

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
      if (!mounted || playbackId != _assistantPlaybackGeneration) {
        return;
      }

      setState(() {
        _typingSpec = null;
        _messages.add(
          Message.fromCompanion(
            burst.text,
            startsNewGroup: burst.isFollowUp,
          ),
        );
      });
      _scrollToBottom();
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
    if (compensated <= 80) {
      return 80;
    }
    return compensated;
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141B2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign out?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w400,
          ),
        ),
        content: Text(
          'Your memories with $_companionName stay saved.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: _amber)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Sign out',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AuthService.signOut();
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending || _isAssistantDelivering) {
      return;
    }

    final clientSentAt = DateTime.now();
    final draftDurationMs = _draftStartedAt == null
        ? null
        : clientSentAt.difference(_draftStartedAt!).inMilliseconds.clamp(0, 600000).toInt();
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
      _messages.add(userMessage);
      _isSending = true;
      _isAssistantDelivering = true;
      _typingSpec = TypingIndicatorSpec.network();
      _errorMessage = null;
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

      if (!mounted) {
        return;
      }

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
      });
      if (response != null) {
        await _playCompanionBursts(
          response.bursts.isNotEmpty
              ? response.bursts
              : [ChatBurst.single(response.reply)],
          networkElapsedMs: networkElapsedMs,
        );
      } else {
        _cancelAssistantPlayback();
      }
      HapticFeedback.selectionClick();
      _scrollToBottom();
    } on ChatException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSending = false;
        _typingSpec = null;
        _isAssistantDelivering = false;
        _replaceMessageStatus(userMessage.id, MessageStatus.failed);
        if (e.statusCode == 503) {
          _errorMessage = "${_companionName.toLowerCase()}'s quiet right now. try again.";
        } else if (e.statusCode == 422) {
          _errorMessage = 'request validation failed (${e.statusCode}): ${e.message}';
        } else if (e.statusCode > 0) {
          _errorMessage = 'server error (${e.statusCode}): ${e.message}';
        } else {
          _errorMessage = 'something went wrong. try again.';
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

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
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (!message.isUser) {
        return message.timestamp;
      }
    }
    return null;
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(initialPairId: _pairId),
      ),
    );
    if (mounted) {
      await _loadPendingProactiveEvents(silent: true);
    }
  }

  Future<void> _loadPendingProactiveEvents({required bool silent}) async {
    try {
      final events = await ApiService.getPendingProactiveEvents();
      if (!mounted || events.isEmpty) {
        return;
      }

      final currentPairEvents = events
          .where((event) => _pairId != null && event.pairId == _pairId)
          .toList();
      for (final event in currentPairEvents) {
        if (event.conversationId.isNotEmpty) {
          _conversationId = event.conversationId;
        }
        if (event.bursts.isNotEmpty) {
          await _playCompanionBursts(event.bursts);
        }
      }

      final otherEvents = events.where((event) => event.pairId != _pairId).toList();
      if (otherEvents.isNotEmpty && !silent) {
        _showNotice(
          '${otherEvents.first.companionName} left something in your inbox.',
        );
      } else if (otherEvents.isNotEmpty && silent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showNotice(
              '${otherEvents.first.companionName} left something in your inbox.',
            );
          }
        });
      }
    } catch (_) {}
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF141B2D),
        content: Text(message),
      ),
    );
  }

  void _replaceMessageStatus(String id, MessageStatus status) {
    final index = _messages.indexWhere((message) => message.id == id);
    if (index == -1) {
      return;
    }
    _messages[index] = _messages[index].copyWith(status: status, isNew: false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  bool _isFirstInGroup(int index) {
    if (index == 0) {
      return true;
    }
    return _messages[index].role != _messages[index - 1].role ||
        _messages[index].startsNewGroup;
  }

  bool _isLastInGroup(int index) {
    if (index == _messages.length - 1) {
      return true;
    }
    return _messages[index].role != _messages[index + 1].role ||
        _messages[index + 1].startsNewGroup;
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _navy,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF101827), Color(0xFF0A0E1A)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildMessageArea()),
                if (_errorMessage != null) _buildErrorBanner(),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(bottom: viewInsets.bottom == 0 ? 0 : 8),
                  child: _buildInputBar(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final firstName = _getFirstName();
    final canPop = Navigator.of(context).canPop();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.94),
        border: Border(
          bottom:
              BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1),
        ),
      ),
      child: Row(
        children: [
          if (canPop) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.56),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          _buildCompanionAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _companionName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEEE8DF),
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  _isTyping
                      ? 'typing...'
                      : firstName != null
                          ? 'online with $firstName'
                          : 'online now',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          if (_memoryCount > 0) _buildMemoryIndicator(),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openProfile,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 17,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _signOut,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
                child: Icon(
                  Icons.logout_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanionAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            _amber.withValues(alpha: 0.72),
            const Color(0xFF3D2A00).withValues(alpha: 0.45),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _amber.withValues(alpha: 0.22),
            blurRadius: 14,
          ),
        ],
      ),
      child: Center(
        child: Image.asset(
          'assets/images/sol_logo.png',
          width: 22,
          height: 22,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text(
            _companionName.isNotEmpty ? _companionName[0].toUpperCase() : 'C',
            style: TextStyle(
              color: _stone,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemoryIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: _amber.withValues(alpha: 0.1),
        border: Border.all(color: _amber.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _amber,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$_memoryCount',
            style: const TextStyle(
              fontSize: 11,
              color: _amber,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageArea() {
    if (_isInitializing) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          valueColor:
              AlwaysStoppedAnimation<Color>(_amber.withValues(alpha: 0.55)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.015),
            Colors.transparent,
          ],
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
        itemCount: _messages.length + (_typingSpec != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (_typingSpec != null && index == _messages.length) {
            return TypingIndicator(
              key: ValueKey(
                '${_typingSpec!.pauseIntensity}-${_typingSpec!.typingDurationMs}-${_typingSpec!.isFollowUp}-${_typingSpec!.isNetworkPending}-${_assistantPlaybackGeneration}',
              ),
              spec: _typingSpec!,
            );
          }

          final message = _messages[index];
          return MessageBubble(
            key: ValueKey(message.id),
            message: message,
            isNew: message.isNew,
            isFirst: _isFirstInGroup(index),
            isLast: _isLastInGroup(index),
            showAvatar: !message.isUser && _isLastInGroup(index),
          );
        },
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF521A1A).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _errorMessage = null),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, color: Colors.redAccent, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final hasText = _inputController.text.trim().isNotEmpty;
    final canSend = hasText && !_isSending && !_isAssistantDelivering;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: _navySurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: hasText
                      ? _amber.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 15.5,
                  height: 1.35,
                ),
                decoration: InputDecoration(
                  hintText: 'Message',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.22),
                    fontSize: 15.5,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (value) {
                  if (value.trim().isNotEmpty && _draftStartedAt == null) {
                    _draftStartedAt = DateTime.now();
                  }
                  if (value.trim().isEmpty) {
                    _draftStartedAt = null;
                  }
                  setState(() {});
                },
                onTap: _scrollToBottom,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: canSend ? 1 : 0.35,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: canSend ? _sendMessage : null,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: canSend ? _amber : _navySurface,
                    boxShadow: canSend
                        ? [
                            BoxShadow(
                              color: _amber.withValues(alpha: 0.35),
                              blurRadius: 14,
                            ),
                          ]
                        : const [],
                  ),
                  child: Icon(
                    _isSending ? Icons.schedule_send_rounded : Icons.send_rounded,
                    color: Colors.white,
                    size: 18,
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
