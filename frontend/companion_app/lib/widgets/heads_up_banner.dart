import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';

class HeadsUpBanner extends StatefulWidget {
  final SolNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismissed;

  const HeadsUpBanner({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismissed,
  });

  static OverlayEntry show(
    BuildContext context, {
    required SolNotification notification,
    VoidCallback? onTap,
  }) {
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => HeadsUpBanner(
        notification: notification,
        onTap: onTap,
        onDismissed: () {
          entry.remove();
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    return entry;
  }

  @override
  State<HeadsUpBanner> createState() => _HeadsUpBannerState();
}

class _HeadsUpBannerState extends State<HeadsUpBanner>
    with SingleTickerProviderStateMixin {
  static const Color _bgDeep = Color(0xFF080A0E);
  static const Color _surface = Color(0xFF10131A);
  static const Color _presenceBlue = Color(0xFF7DA2FF);
  static const Color _warmViolet = Color(0xFFA78BFA);
  static const Color _cream = Color(0xFFE8DDD0);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  Timer? _dismissTimer;
  double _dragDx = 0;
  bool _closing = false;
  bool _replyExpanded = false;
  bool _sendingReply = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      reverseDuration: const Duration(milliseconds: 260),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.32),
      end: Offset.zero,
    ).animate(curved);
    _controller.forward();
    _dismissTimer = Timer(const Duration(seconds: 5), _dismiss);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _replyController.dispose();
    _replyFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) {
      return;
    }
    _closing = true;
    _dismissTimer?.cancel();
    await _controller.reverse();
    widget.onDismissed?.call();
  }

  String get _timeLabel {
    final elapsed = DateTime.now().difference(widget.notification.timestamp);
    if (elapsed.inMinutes < 1) {
      return 'now';
    }
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes}m';
    }
    return '${elapsed.inHours}h';
  }

  void _expandReply() {
    _dismissTimer?.cancel();
    setState(() => _replyExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _replyFocus.requestFocus();
      }
    });
  }

  Future<void> _sendQuickReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sendingReply) {
      return;
    }
    setState(() => _sendingReply = true);
    await NotificationService.playOutboundReplyFeedback();
    unawaited(
      ApiService.sendMessage(
        message: text,
        characterId: widget.notification.chatId,
      ).catchError((_) => null),
    );
    await _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    final name = widget.notification.sender.trim().isEmpty
        ? 'Sol'
        : widget.notification.sender.trim();

    return Positioned(
      top: safeTop + 10,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Transform.translate(
            offset: Offset(_dragDx, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_replyExpanded) {
                  return;
                }
                widget.onTap?.call();
                _dismiss();
              },
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _dragDx += details.delta.dx;
                });
              },
              onHorizontalDragEnd: (details) {
                final fastEnough = details.primaryVelocity != null &&
                    details.primaryVelocity!.abs() > 420;
                if (_dragDx.abs() > 68 || fastEnough) {
                  _dismiss();
                } else {
                  setState(() => _dragDx = 0);
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 78),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: _bgDeep.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _cream.withValues(alpha: 0.075),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _presenceBlue.withValues(alpha: 0.12),
                          blurRadius: 26,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              _Avatar(name: name),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MessageCopy(
                                  name: name,
                                  preview: widget.notification.messagePreview,
                                  timeLabel: _timeLabel,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _ReplyButton(
                                expanded: _replyExpanded,
                                onTap: _expandReply,
                              ),
                            ],
                          ),
                          if (_replyExpanded) ...[
                            const SizedBox(height: 12),
                            _QuickReplyInput(
                              controller: _replyController,
                              focusNode: _replyFocus,
                              sending: _sendingReply,
                              onSend: _sendQuickReply,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageCopy extends StatelessWidget {
  final String name;
  final String preview;
  final String timeLabel;

  const _MessageCopy({
    required this.name,
    required this.preview,
    required this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFE8DDD0),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              timeLabel,
              style: GoogleFonts.jost(
                color: const Color(0xFF5A5568).withValues(alpha: 0.95),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.15,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF9A8C78).withValues(alpha: 0.86),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _QuickReplyInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  const _QuickReplyInput({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: _HeadsUpBannerState._surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _HeadsUpBannerState._warmViolet.withValues(alpha: 0.18),
          width: 0.7,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFE8DDD0).withValues(alpha: 0.92),
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText: 'reply softly...',
                hintStyle: GoogleFonts.jost(
                  color: const Color(0xFF5A5568).withValues(alpha: 0.78),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: _HeadsUpBannerState._presenceBlue.withValues(alpha: sending ? 0.38 : 0.92,),
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF7DA2FF),
                      ),
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ReplyButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _ReplyButton({
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF7DA2FF).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFF7DA2FF).withValues(alpha: 0.18),
            width: 0.7,
          ),
        ),
        child: Text(
          'Reply',
          style: GoogleFonts.jost(
            color: const Color(0xFFE8DDD0).withValues(alpha: 0.82),
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;

  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'S' : name.trim()[0].toUpperCase();
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: _getAvatarGradient(name),
        border: Border.all(
          color: const Color(0xFFE8DDD0).withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFFE8DDD0),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

LinearGradient _getAvatarGradient(String name) {
  final palettes = <List<Color>>[
    [const Color(0xFF7DA2FF), const Color(0xFFA78BFA)],
    [const Color(0xFFA78BFA), const Color(0xFF476C9B)],
    [const Color(0xFF5F7EA8), const Color(0xFFB98EA7)],
    [const Color(0xFF52627E), const Color(0xFF7DA2FF)],
  ];
  final index =
      name.codeUnits.fold<int>(0, (sum, code) => sum + code) % palettes.length;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: palettes[index],
  );
}
