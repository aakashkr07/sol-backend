import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_bootstrap_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

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

  bool _isTyping = false;
  bool _isSending = false;
  bool _isInitializing = true;
  bool _isSwitchingCompanion = false;
  String? _errorMessage;
  String? _conversationId;
  String? _companionId;
  String _companionName = 'Companion';
  int _memoryCount = 0;
  List<CompanionSummary> _companions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
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

  Future<void> _initialize() async {
    try {
      final session =
          SessionBootstrapService.consume() ?? await ApiService.startSession();
      if (session != null && mounted) {
        setState(() {
          _conversationId = session.conversationId;
          _companionId = session.companionId;
          _companionName = session.companionName;
          _memoryCount = session.memoryCount;
        });
        if (_messages.isEmpty) {
          _addCompanionMessage(session.openingMessage);
        }
      }
      await _loadCompanions();
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
  }

  Future<void> _loadCompanions() async {
    final response = await ApiService.getMyCompanions();
    if (response == null || !mounted) {
      return;
    }

    final byId = <String, CompanionSummary>{};
    for (final pair in response.pairs) {
      byId[pair.id] = pair;
    }
    for (final companion in response.availableCompanions) {
      byId[companion.id] = byId[companion.id] ?? companion;
    }

    setState(() {
      _companions = byId.values.toList()
        ..sort((a, b) {
          if (a.isPrimary == b.isPrimary) {
            return a.name.compareTo(b.name);
          }
          return a.isPrimary ? -1 : 1;
        });
    });
  }

  String? _getFirstName() {
    final name = AuthService.currentUserName;
    if (name == null || name.trim().isEmpty) {
      return null;
    }
    return name.trim().split(' ').first;
  }

  void _addCompanionMessage(String text) {
    if (!mounted) {
      return;
    }
    setState(() => _messages.add(Message.fromCompanion(text)));
    _scrollToBottom();
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

  Future<void> _openCompanionPicker() async {
    if (_isSwitchingCompanion || _companions.isEmpty) {
      return;
    }

    final selected = await showModalBottomSheet<CompanionSummary>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose who you want to talk to',
                  style: TextStyle(
                    color: Color(0xFFEEE8DF),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Each companion keeps a separate relationship and memory thread.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                for (final companion in _companions)
                  ListTile(
                    onTap: () => Navigator.pop(context, companion),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      companion.name,
                      style: const TextStyle(
                        color: Color(0xFFEEE8DF),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      companion.summary.isEmpty
                          ? 'A different emotional rhythm.'
                          : companion.summary,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.48),
                        fontSize: 12.5,
                      ),
                    ),
                    trailing: companion.isPrimary
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _amber.withValues(alpha: 0.22),
                              ),
                            ),
                            child: const Text(
                              'current',
                              style: TextStyle(
                                color: _amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : Text(
                            companion.totalSessions > 0
                                ? '${companion.totalSessions} chats'
                                : 'new',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected.id == _companionId) {
      return;
    }

    await _switchCompanion(selected.id);
  }

  Future<void> _switchCompanion(String companionId) async {
    setState(() {
      _isSwitchingCompanion = true;
      _errorMessage = null;
    });

    try {
      final session = await ApiService.startSession(characterId: companionId);
      if (session == null || !mounted) {
        throw const ChatException('Could not switch companions.', -1);
      }

      setState(() {
        _messages.clear();
        _conversationId = session.conversationId;
        _companionId = session.companionId;
        _companionName = session.companionName;
        _memoryCount = session.memoryCount;
        _messages.add(Message.fromCompanion(session.openingMessage));
      });
      await _loadCompanions();
      _scrollToBottom();
    } on ChatException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) {
        setState(() => _isSwitchingCompanion = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    final userMessage = Message.fromUser(text);
    _inputController.clear();
    _inputFocusNode.requestFocus();
    HapticFeedback.lightImpact();

    setState(() {
      _messages.add(userMessage);
      _isTyping = true;
      _isSending = true;
      _errorMessage = null;
    });

    _scrollToBottom();

    try {
      final response = await ApiService.sendMessage(
        message: text,
        conversationId: _conversationId,
        characterId: _companionId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _conversationId = response?.conversationId ?? _conversationId;
        _companionId = response?.companionId ?? _companionId;
        _companionName = response?.companionName ?? _companionName;
        _memoryCount = response?.memoryCount ?? _memoryCount;
        _isTyping = false;
        _isSending = false;
        _replaceMessageStatus(userMessage.id, MessageStatus.read);
        if (response != null) {
          _messages.add(Message.fromCompanion(response.reply));
        }
      });
      await _loadCompanions();
      HapticFeedback.selectionClick();
      _scrollToBottom();
    } on ChatException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isTyping = false;
        _isSending = false;
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
        _isTyping = false;
        _isSending = false;
        _replaceMessageStatus(userMessage.id, MessageStatus.failed);
        _errorMessage = 'connection lost. check your network.';
      });
    }
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
    return _messages[index].role != _messages[index - 1].role;
  }

  bool _isLastInGroup(int index) {
    if (index == _messages.length - 1) {
      return true;
    }
    return _messages[index].role != _messages[index + 1].role;
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
                      : _isSwitchingCompanion
                          ? 'switching...'
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
              onTap: _isSwitchingCompanion ? null : _openCompanionPicker,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.45),
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
        itemCount: _messages.length + (_isTyping ? 1 : 0),
        itemBuilder: (context, index) {
          if (_isTyping && index == _messages.length) {
            return const TypingIndicator();
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
    final canSend = hasText && !_isSending;

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
                onChanged: (_) => setState(() {}),
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
