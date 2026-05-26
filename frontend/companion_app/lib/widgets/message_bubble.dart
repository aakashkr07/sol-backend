import 'package:flutter/material.dart';

import '../models/message_model.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isNew;
  final bool isFirst;
  final bool isLast;
  final bool showAvatar;

  const MessageBubble({
    super.key,
    required this.message,
    this.isNew = false,
    this.isFirst = true,
    this.isLast = true,
    this.showAvatar = true,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  static const Color _amber = Color(0xFFF5A623);
  static const Color _navySurface = Color(0xFF1A2035);
  static const Color _textPrimary = Color(0xFFEEE8DF);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _tickGrey = Color(0xFF8B95A7);
  static const Color _tickRead = Color(0xFFF5A623);

  late final AnimationController _entranceCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

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
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
    );

    if (widget.isNew) {
      Future.delayed(const Duration(milliseconds: 40), () {
        if (mounted) {
          _entranceCtrl.forward();
        }
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

    return FadeTransition(
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
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment:
                    isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isUser) _buildNovaAvatar(),
                  if (!isUser) const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: screenWidth * 0.76,
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
      ),
    );
  }

  Widget _buildNovaAvatar() {
    if (!widget.showAvatar) {
      return const SizedBox(width: 28);
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFF5A623), Color(0xFF3D2A00)],
        ),
        boxShadow: [
          BoxShadow(
            color: _amber.withValues(alpha: 0.22),
            blurRadius: 8,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'N',
          style: TextStyle(
            color: Color(0xFFEEE8DF),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(bool isUser) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? _amber : _navySurface,
        borderRadius: _bubbleRadius(),
        border: isUser
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.6),
        boxShadow: [
          BoxShadow(
            color: isUser
                ? _amber.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.22),
            blurRadius: isUser ? 12 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        widget.message.text,
        style: TextStyle(
          color: isUser ? const Color(0xFF0A0E1A) : _textPrimary,
          fontSize: 15.5,
          height: 1.4,
          fontWeight: isUser ? FontWeight.w500 : FontWeight.w400,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

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
            style: TextStyle(
              fontSize: 11,
              color: _textMuted.withValues(alpha: 0.82),
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

  Widget _buildTicks(MessageStatus status) {
    const double iconSize = 13;

    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.schedule_rounded, size: iconSize, color: _tickGrey);
      case MessageStatus.sent:
      case MessageStatus.delivered:
        return _doubleTick(color: _tickGrey, size: iconSize);
      case MessageStatus.read:
        return _doubleTick(color: _tickRead, size: iconSize);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline_rounded,
            size: iconSize, color: Colors.redAccent);
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
