// lib/widgets/message_bubble.dart
// Sol · MessageBubble  [DESIGN SYSTEM ALIGNED]
//
// Changes (frontend/visual only — Message model, status enum, all logic untouched):
//
//   · User bubble: solid amber → blue gradient [_blue → _blueSoft] with white text.
//     Amber was the only orange element breaking the blue/violet palette.
//
//   · Companion avatar: amber radial gradient + Sol logo image →
//     initial letter (first char of companion name) on dark surface circle
//     with blue ring. Matches the top-bar avatar and WhatsApp/iMessage convention.
//     When showAvatar=false, placeholder SizedBox width unchanged (28px).
//
//   · Read-tick colour: amber → _blue so it stays in palette.
//
//   · Overflow fix: the SlideTransition begin offset (0, 0.18) was painting
//     ~52px above the widget's layout rect during entrance animation, causing
//     the "overflowed by 52 pixels" debug stripe. Fixed by wrapping the
//     FadeTransition+SlideTransition in a ClipRect so entrance animation
//     is clipped to the item's allocated space.
//
//   · Font: all TextStyle(...) → GoogleFonts.plusJakartaSans for consistency
//     with inbox_screen and chat_screen.
//
//   · Companion bubble surface: 0xFF1A2035 → 0xFF10131A (_surface token).
//
//   · Timestamp and tick colours stay functionally identical, just in-palette.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/message_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — identical to chat_screen.dart and inbox_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

const Color _blue = Color(0xFF7DA2FF);
const Color _blueSoft = Color(0xFF8BA8FF);
const Color _surface = Color(0xFF10131A);
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);
const Color _dusty = Color(0xFF5A5568);

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isNew;
  final bool isFirst;
  final bool isLast;
  final bool showAvatar;
  final String companionName;
  final Message? parentMessage;
  final ValueChanged<Message>? onSwiped;

  const MessageBubble({
    super.key,
    required this.message,
    this.isNew = false,
    this.isFirst = true,
    this.isLast = true,
    this.showAvatar = true,
    this.companionName = '',
    this.parentMessage,
    this.onSwiped,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  double _dragOffset = 0.0;
  bool _hasTriggeredHaptic = false;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.isNew ? 240 : 0),
    );
    _fade = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic));

    if (widget.isNew) {
      Future.delayed(const Duration(milliseconds: 40), () {
        if (mounted) _entranceCtrl.forward();
      });
    } else {
      _entranceCtrl.value = 1;
    }
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  BorderRadius _bubbleRadius() {
    const double full = 18;
    const double grouped = 6;
    const double tail = 4;

    if (widget.message.isUser) {
      return BorderRadius.only(
        topLeft: const Radius.circular(full),
        topRight: Radius.circular(widget.isFirst ? full : grouped),
        bottomLeft: const Radius.circular(full),
        bottomRight: Radius.circular(widget.isLast ? tail : grouped),
      );
    }

    return BorderRadius.only(
      topLeft: Radius.circular(widget.isFirst ? full : grouped),
      topRight: const Radius.circular(full),
      bottomLeft: Radius.circular(widget.isLast ? tail : grouped),
      bottomRight: const Radius.circular(full),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.isUser;
    final screenWidth = MediaQuery.of(context).size.width;

    return ClipRect(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Padding(
            padding: EdgeInsets.only(
              left: isUser ? 70 : 12,
              right: isUser ? 12 : 70,
              top: widget.isFirst ? 8 : 2,
              bottom: widget.isLast ? 3 : 0,
            ),
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                // Dragging from left to right (dx > 0)
                if (details.delta.dx > 0) {
                  setState(() {
                    _dragOffset =
                        (_dragOffset + details.delta.dx).clamp(0.0, 70.0);
                  });
                  if (_dragOffset >= 50.0 && !_hasTriggeredHaptic) {
                    HapticFeedback.lightImpact();
                    _hasTriggeredHaptic = true;
                  }
                }
              },
              onHorizontalDragEnd: (details) {
                if (_dragOffset >= 50.0) {
                  widget.onSwiped?.call(widget.message);
                }
                setState(() {
                  _dragOffset = 0.0;
                  _hasTriggeredHaptic = false;
                });
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: -40,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 100),
                        opacity: _dragOffset > 20
                            ? (_dragOffset / 70.0).clamp(0.0, 1.0)
                            : 0.0,
                        child: const Icon(
                          Icons.reply_rounded,
                          color: _blue,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration:
                        Duration(milliseconds: _dragOffset == 0 ? 180 : 0),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(_dragOffset, 0, 0),
                    child: Column(
                      crossAxisAlignment: isUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: isUser
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isUser) _buildCompanionAvatar(),
                            if (!isUser) const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: screenWidth * 0.65,
                                minWidth: 54,
                              ),
                              child: _buildBubble(isUser),
                            ),
                          ],
                        ),
                        if (widget.isLast) _buildTimestamp(isUser),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Companion avatar — initial letter, blue ring ────────────────────────────
  Widget _buildCompanionAvatar() {
    if (!widget.showAvatar) {
      return const SizedBox(width: 28);
    }

    final initial = widget.companionName.isNotEmpty
        ? widget.companionName[0].toUpperCase()
        : '?';

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _surface,
        border: Border.all(
          color: _blue.withValues(alpha: 0.40),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _blue.withValues(alpha: 0.14),
            blurRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.plusJakartaSans(
            color: _cream.withValues(alpha: 0.82),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  // ── Parent Message Preview ──────────────────────────────────────────────────
  Widget _buildParentMessagePreview(bool isUser) {
    final parent = widget.parentMessage;
    if (parent == null) return const SizedBox.shrink();

    final senderName = parent.isUser
        ? "You"
        : (widget.companionName.isNotEmpty
            ? widget.companionName
            : "Companion");
    final accentColor = parent.isUser ? _blue : const Color(0xFFA78BFA);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: accentColor, width: 3.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            style: GoogleFonts.plusJakartaSans(
              color: accentColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            parent.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: isUser
                  ? Colors.white.withValues(alpha: 0.70)
                  : _cream.withValues(alpha: 0.70),
              fontSize: 13,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bubble ───────────────────────────────────────────────────────────────────
  Widget _buildBubble(bool isUser) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: isUser
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_blue, _blueSoft],
              )
            : null,
        color: isUser ? null : _surface,
        borderRadius: _bubbleRadius(),
        border: isUser
            ? null
            : Border.all(
                color: Colors.white.withValues(alpha: 0.06),
                width: 0.6,
              ),
        boxShadow: [
          BoxShadow(
            color: isUser
                ? _blue.withValues(alpha: 0.20)
                : Colors.black.withValues(alpha: 0.18),
            blurRadius: isUser ? 12 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.parentMessage != null) _buildParentMessagePreview(isUser),
          Text(
            widget.message.text,
            style: GoogleFonts.plusJakartaSans(
              color: isUser
                  ? Colors.white.withValues(alpha: 0.95)
                  : _cream.withValues(alpha: 0.88),
              fontSize: 15,
              height: 1.45,
              fontWeight: isUser ? FontWeight.w500 : FontWeight.w400,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── Timestamp row ─────────────────────────────────────────────────────────────
  Widget _buildTimestamp(bool isUser) {
    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        left: isUser ? 0 : 34,
        right: isUser ? 4 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Text(
            widget.message.timeLabel,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: _dusty.withValues(alpha: 0.75),
              height: 1.0,
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 4),
            _buildTicks(widget.message.status),
          ],
        ],
      ),
    );
  }

  // ── Status ticks ──────────────────────────────────────────────────────────────
  Widget _buildTicks(MessageStatus status) {
    const double iconSize = 13;
    const Color tickGrey = _sand;
    const Color tickRead = _blue;

    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.schedule_rounded,
            size: iconSize, color: tickGrey.withValues(alpha: 0.55));
      case MessageStatus.sent:
      case MessageStatus.delivered:
        return _doubleTick(color: tickGrey.withValues(alpha: 0.55), size: iconSize);
      case MessageStatus.read:
        return _doubleTick(color: tickRead, size: iconSize);
      case MessageStatus.failed:
        return Icon(Icons.error_outline_rounded,
            size: iconSize, color: const Color(0xFFBB7070));
    }
  }

  Widget _doubleTick({required Color color, required double size}) {
    return SizedBox(
      width: size + 8,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: Icon(Icons.check, size: size, color: color),
          ),
          Positioned(
            left: 5,
            child: Icon(Icons.check, size: size, color: color),
          ),
        ],
      ),
    );
  }
}
