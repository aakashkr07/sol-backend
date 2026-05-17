// =============================================================================
// widgets/message_bubble.dart — Chat Message Bubble Widget
// =============================================================================
//
// PURPOSE:
//   Renders individual chat messages — both user messages and Nova's replies.
//   Includes: slide-up animation, fade-in, message styling, timestamp.
//
// DESIGN PRINCIPLES:
//   - User messages: right-aligned, dark background (iMessage-style)
//   - Nova's messages: left-aligned, lighter background
//   - Animations: slide up + fade in (makes messages feel alive, not snapped in)
//   - No avatars for Nova in MVP (keep it clean, intimate)
//   - Timestamps: subtle, only shown when tapped (reduces visual noise)
//
// ANIMATION:
//   Each bubble has its own AnimationController. When isNew=true, it plays
//   the entrance animation. Old messages (loaded from history) render instantly.
//
// USAGE:
//   MessageBubble(
//     message: message,
//     isNew: true,  // triggers animation
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message_model.dart';

class MessageBubble extends StatefulWidget {
  final Message message;

  /// If true, plays the entrance animation (slide up + fade in).
  /// Set to false for messages loaded from history — they should appear instantly.
  final bool isNew;

  const MessageBubble({super.key, required this.message, this.isNew = false});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  bool _showTimestamp = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15), // Slides up from slightly below
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // New messages animate in. Old messages appear instantly.
    if (widget.isNew) {
      _controller.forward();
    } else {
      _controller.value = 1.0; // Instantly at end state
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTap: () {
            // Tap to toggle timestamp — subtle, non-intrusive
            setState(() => _showTimestamp = !_showTimestamp);
            HapticFeedback.selectionClick();
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: isUser
                  ? 60.0
                  : 16.0, // User bubbles: right-aligned with left padding
              right: isUser
                  ? 16.0
                  : 60.0, // Nova bubbles: left-aligned with right padding
              top: 2.0,
              bottom: 2.0,
            ),
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                _buildBubble(context, isUser),
                if (_showTimestamp) _buildTimestamp(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context, bool isUser) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      decoration: BoxDecoration(
        color: isUser
            ? const Color(0xFF1A1A1A) // User: near-black (dark, intimate)
            : const Color(0xFF2A2A2A), // Nova: slightly lighter dark
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isUser ? 20 : 4), // Tail on Nova's side
          bottomRight: Radius.circular(isUser ? 4 : 20), // Tail on user's side
        ),
        // Subtle border for Nova's messages — distinguishes without heavy contrast
        border: isUser
            ? null
            : Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        widget.message.content,
        style: TextStyle(
          fontSize: 15.5,
          height: 1.45,
          color: isUser
              ? Colors.white.withOpacity(0.92)
              : Colors.white.withOpacity(0.88),
          fontFamily: 'SF Pro Text', // Falls back to system font on non-Apple
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _buildTimestamp() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: Text(
        _formatTimestamp(widget.message.timestamp),
        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35)),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${dt.day}/${dt.month}';
  }
}
