// =============================================================================
// screens/chat_screen.dart — Sol Chat Interface (Firebase Auth version)
// =============================================================================
//
// CHANGES FROM PREVIOUS VERSION:
//   1. No more SharedPreferences userId — uses AuthService.currentUserId (Firebase UID)
//   2. No more Uuid() generation — Firebase handles identity
//   3. Top bar shows user's Google display name
//   4. Sign out option in top bar
//   5. Sol color palette (navy + amber) replaces purple
//   6. ApiService calls no longer need userId param (it reads from AuthService)
//
// EVERYTHING ELSE IS IDENTICAL — memory, typing indicator, message bubbles,
// scroll behavior, error handling. All unchanged.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import 'login_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  // ── Sol palette ────────────────────────────────────────────────────────
  static const Color _navy = Color(0xFF0A0E1A);
  static const Color _navySurface = Color(0xFF111827);
  static const Color _amber = Color(0xFFF5A623);
  static const Color _stone = Color(0xFFE8DCC8);
  static const Color _textMuted = Color(0xFF6B7280);

  // ── State ──────────────────────────────────────────────────────────────
  final List<Message> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isTyping = false;
  bool _isSending = false;
  bool _isInitializing = true;
  String? _errorMessage;

  String? _conversationId;
  int _memoryCount = 0;

  static const String _characterId = 'nova';

  // ── Lifecycle ──────────────────────────────────────────────────────────

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

  // ── Initialization ─────────────────────────────────────────────────────

  Future<void> _initialize() async {
    // Firebase UID is ready immediately — no async needed
    // Just start the session with the backend
    try {
      final session = await ApiService.startSession(characterId: _characterId);
      if (session != null && mounted) {
        setState(() {
          _conversationId = session.conversationId;
          _memoryCount = session.memoryCount;
        });

        // Greet based on session history
        final firstName = _getFirstName();
        if (session.isFirstSession) {
          _addNovaMessage("hey. glad you're here.");
        } else if (session.memoryCount > 0 && firstName != null) {
          _addNovaMessage(
              "hey ${firstName.toLowerCase()}. was thinking about you.");
        } else {
          _addNovaMessage("hey. you're back.");
        }
      }
    } catch (_) {
      // Session start failure is non-fatal
    }

    if (mounted) setState(() => _isInitializing = false);
  }

  String? _getFirstName() {
    final name = AuthService.currentUserName;
    if (name == null) return null;
    return name.split(' ').first;
  }

  void _addNovaMessage(String text) {
    if (!mounted) return;
    setState(() => _messages.add(Message.fromNova(text)));
  }

  // ── Sign out ───────────────────────────────────────────────────────────

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141B2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign out?',
          style: TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w400),
        ),
        content: Text(
          'Your memories with Nova stay saved.',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: _amber)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign out',
                style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AuthService.signOut();
      // Auth gate in main.dart automatically redirects to LoginScreen
      // when Firebase emits null from authStateChanges()
    }
  }

  // ── Message sending ────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    _inputController.clear();
    HapticFeedback.lightImpact();

    setState(() {
      _messages.add(Message.fromUser(text));
      _isTyping = true;
      _isSending = true;
      _errorMessage = null;
    });

    _scrollToBottom();
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) _scrollToBottom();

    try {
      final response = await ApiService.sendMessage(
        message: text,
        conversationId: _conversationId,
        characterId: _characterId,
      );

      if (!mounted) return;

      if (response != null) {
        setState(() {
          _conversationId = response.conversationId;
          _memoryCount = response.memoryCount;
          _isTyping = false;
          _isSending = false;
          _messages.add(Message.fromNova(response.reply));
        });
        HapticFeedback.selectionClick();
        _scrollToBottom();
      }
    } on ChatException catch (e) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _isSending = false;
        _errorMessage = e.statusCode == 503
            ? "nova's quiet right now. try again."
            : "something went wrong. try again.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _isSending = false;
        _errorMessage = "connection lost. check your network.";
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildMessageList()),
            if (_errorMessage != null) _buildErrorBanner(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final firstName = _getFirstName();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _navy,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Nova avatar — amber glow version
          _buildNovaAvatar(),
          const SizedBox(width: 12),

          // Name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nova',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFEEE8DF),
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  _isTyping
                      ? 'typing...'
                      : firstName != null
                          ? 'here with you, $firstName'
                          : 'here with you',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.35),
                  ),
                ),
              ],
            ),
          ),

          // Memory indicator
          if (_memoryCount > 0) _buildMemoryIndicator(),

          const SizedBox(width: 8),

          // Sign out button
          GestureDetector(
            onTap: _signOut,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
              child: Icon(
                Icons.logout_rounded,
                size: 15,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNovaAvatar() {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            _amber.withOpacity(0.7),
            const Color(0xFF3D2A00).withOpacity(0.4),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _amber.withOpacity(0.25),
            blurRadius: 12,
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
            'N',
            style: TextStyle(
              color: _stone,
              fontSize: 16,
              fontWeight: FontWeight.w400,
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
        borderRadius: BorderRadius.circular(12),
        color: _amber.withOpacity(0.1),
        border: Border.all(color: _amber.withOpacity(0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _amber),
          ),
          const SizedBox(width: 4),
          Text(
            '$_memoryCount',
            style: TextStyle(
              fontSize: 11,
              color: _amber,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────

  Widget _buildMessageList() {
    if (_isInitializing) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation<Color>(_amber.withOpacity(0.5)),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isTyping && index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.only(top: 4),
            child: TypingIndicator(),
          );
        }
        final message = _messages[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: MessageBubble(
            key: ValueKey(message.id),
            message: message,
            isNew: message.isNew,
          ),
        );
      },
    );
  }

  // ── Error banner ───────────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.red.withOpacity(0.1),
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
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: const Icon(Icons.close, color: Colors.redAccent, size: 16),
          ),
        ],
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: _navy,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
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
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontSize: 15.5,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: 'say something...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.18),
                    fontSize: 15.5,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _inputController.text.trim().isEmpty ? 0.25 : 1.0,
            child: GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _inputController.text.trim().isEmpty
                      ? _navySurface
                      : _amber,
                  boxShadow: _inputController.text.trim().isEmpty
                      ? []
                      : [
                          BoxShadow(
                            color: _amber.withOpacity(0.4),
                            blurRadius: 12,
                          ),
                        ],
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
