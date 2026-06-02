import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../widgets/atmosphere_background.dart';

const Color _bgDeep = Color(0xFF080A0E);
const Color _surface = Color(0xFF10131A);
const Color _surfaceUp = Color(0xFF141720);
const Color _blue = Color(0xFF7DA2FF);
const Color _blueSoft = Color(0xFF8BA8FF);
const Color _violet = Color(0xFFA78BFA);
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);
const Color _ink = Color(0xFF060810);
const Color _red = Color(0xFFE07070);

class RelationshipStudioScreen extends StatefulWidget {
  const RelationshipStudioScreen({
    super.key,
    required this.pairId,
    required this.companionName,
  });

  final String pairId;
  final String companionName;

  @override
  State<RelationshipStudioScreen> createState() =>
      _RelationshipStudioScreenState();
}

class _RelationshipStudioScreenState extends State<RelationshipStudioScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _introCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  UserProfileResponse? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fade = CurvedAnimation(parent: _introCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _introCtrl, curve: Curves.easeOutCubic));
    _load();
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await ApiService.getMyProfile(pairId: widget.pairId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
      _introCtrl.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'could not open this relationship record.';
      });
    }
  }

  Future<void> _editFact(Map<String, dynamic> fact) async {
    final id = fact['id'];
    if (id is! int) return;
    final value = fact['fact_value']?.toString() ?? '';
    final updated = await _textDialog(
      title: 'correct this fact',
      label: fact['fact_key']?.toString() ?? 'fact',
      initialValue: value,
      maxLines: 4,
    );
    if (updated == null || updated.trim() == value.trim()) return;

    try {
      await ApiService.updateFact(widget.pairId, id, updated.trim());
      _showSnack('fact corrected.');
      await _load();
    } catch (_) {
      _showSnack('could not update fact.');
    }
  }

  Future<void> _editMemory(MemoryEntry memory) async {
    final updated = await _memoryDialog(memory);
    if (updated == null) return;
    try {
      await ApiService.updateMemory(
        widget.pairId,
        memory.id,
        title: updated.$1,
        content: updated.$2,
      );
      _showSnack('moment updated.');
      await _load();
    } catch (_) {
      _showSnack('could not update moment.');
    }
  }

  Future<void> _deleteMemory(MemoryEntry memory) async {
    final confirmed = await _confirm(
      title: 'erase this moment?',
      body:
          'This removes it from ${widget.companionName}\'s memory index. The old chat text stays, but this recall entry is gone.',
      action: 'erase',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ApiService.deleteMemory(widget.pairId, memory.id);
      _showSnack('moment erased.');
      await _load();
    } catch (_) {
      _showSnack('could not erase moment.');
    }
  }

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
      body: AtmosphereBackground(
        child: SafeArea(
          child: _loading
              ? _loader()
              : _error != null
                  ? _errorState()
                  : FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: _content(),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _content() {
    final profile = _profile!;
    final companion = profile.selectedPair;
    final name = companion?.name ?? widget.companionName;
    final relationship = profile.relationshipState;
    final facts = profile.factRows;
    final memories = profile.memories;
    final narrative = profile.currentNarrative;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _header(name, companion, relationship)),
        SliverToBoxAdapter(
          child: _section(
            eyebrow: 'continuity',
            title: 'what this relationship has become',
            child: Column(
              children: [
                _statGrid(companion, profile.memoryCount),
                if (narrative != null && narrative.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _narrativeCard(narrative),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _section(
            eyebrow: 'facts',
            title: 'what $name knows about you',
            action: facts.isEmpty ? null : '${facts.length} editable',
            child: facts.isEmpty
                ? _empty('No facts yet. Keep talking and this will bloom.')
                : Column(
                    children: [
                      for (final fact in facts.take(12))
                        _factRow(fact, onTap: () => _editFact(fact)),
                    ],
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: _section(
            eyebrow: 'moments',
            title: 'memory timeline',
            action: memories.isEmpty ? null : '${memories.length} moments',
            child: memories.isEmpty
                ? _empty('No core moments yet. Personal threads become memories here.')
                : Column(
                    children: [
                      for (final memory in memories.take(18))
                        _memoryCard(memory),
                    ],
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: _section(
            eyebrow: 'control',
            title: 'your say in the record',
            child: _controlNote(),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 30)),
      ],
    );
  }

  Widget _header(
    String name,
    CompanionSummary? companion,
    RelationshipStateSnapshot? relationship,
  ) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';
    final stage = companion?.currentStage.toLowerCase() ?? 'new';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconButton(Icons.arrow_back_rounded, () => Navigator.pop(context)),
              const Spacer(),
              Text(
                'RELATIONSHIP STUDIO',
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.58),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _gradientFor(name),
                  border: Border.all(
                    color: _cream.withValues(alpha: 0.10),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withValues(alpha: 0.18),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'you & $name',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: _cream.withValues(alpha: 0.96),
                        fontSize: 31,
                        fontWeight: FontWeight.w600,
                        height: 1.04,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '$stage relationship · ${_relationshipLine(relationship)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jost(
                        color: _sand.withValues(alpha: 0.72),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statGrid(
    CompanionSummary? companion,
    int memoryCount,
  ) {
    final totalMessages = companion?.totalMessages ?? 0;
    final sessions = companion?.totalSessions ?? 0;
    final knownFor = _knownForLabel();
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: [
        _statCard('known for', knownFor, Icons.calendar_month_outlined),
        _statCard('texts shared', '$totalMessages', Icons.forum_outlined),
        _statCard('sessions', '$sessions', Icons.bolt_outlined),
        _statCard('memories', '$memoryCount', Icons.auto_awesome_outlined),
      ],
    );
  }

  Widget _section({
    required String eyebrow,
    required String title,
    required Widget child,
    String? action,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: GoogleFonts.jost(
                  color: _blue.withValues(alpha: 0.70),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2.0,
                ),
              ),
              const Spacer(),
              if (action != null)
                Text(
                  action,
                  style: GoogleFonts.jost(
                    color: _sand.withValues(alpha: 0.50),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              color: _cream.withValues(alpha: 0.92),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Icon(icon, color: _blueSoft.withValues(alpha: 0.76), size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jost(
                    color: _sand.withValues(alpha: 0.62),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _narrativeCard(String narrative) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Text(
        narrative,
        style: GoogleFonts.jost(
          color: _sand.withValues(alpha: 0.78),
          fontSize: 13,
          height: 1.55,
        ),
      ),
    );
  }

  Widget _factRow(Map<String, dynamic> fact, {required VoidCallback onTap}) {
    final key = fact['fact_key']?.toString() ?? 'fact';
    final value = fact['fact_value']?.toString() ?? '';
    final category = fact['category']?.toString() ?? 'general';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _panelDecoration(alpha: 0.48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _violet.withValues(alpha: 0.80),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$category · $key',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jost(
                        color: _sand.withValues(alpha: 0.55),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: GoogleFonts.plusJakartaSans(
                        color: _cream.withValues(alpha: 0.88),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.edit_outlined, size: 15, color: _sand.withValues(alpha: 0.50)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memoryCard(MemoryEntry memory) {
    final created = _dateLabel(memory.createdAt);
    final tag = memory.emotionTag.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(alpha: 0.54),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  memory.title,
                  style: GoogleFonts.plusJakartaSans(
                    color: _cream.withValues(alpha: 0.92),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              _tinyButton(Icons.edit_outlined, () => _editMemory(memory)),
              const SizedBox(width: 4),
              _tinyButton(Icons.delete_outline_rounded, () => _deleteMemory(memory), destructive: true),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            memory.content,
            style: GoogleFonts.jost(
              color: _sand.withValues(alpha: 0.74),
              fontSize: 13,
              height: 1.48,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              if (tag.isNotEmpty) _chip(tag, _blue),
              if (tag.isNotEmpty) const SizedBox(width: 8),
              _chip(created, _violet),
              const Spacer(),
              Text(
                'strength ${((memory.strength.clamp(0.0, 2.5) / 2.5) * 100).round()}%',
                style: GoogleFonts.jost(
                  color: _sand.withValues(alpha: 0.45),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(alpha: 0.46),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: _blue.withValues(alpha: 0.72), size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'You can correct facts, rewrite memory summaries, or erase moments. Edits are scoped only to this companion, so each relationship keeps its own record.',
              style: GoogleFonts.jost(
                color: _sand.withValues(alpha: 0.76),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(alpha: 0.36),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.jost(
          color: _sand.withValues(alpha: 0.55),
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _loader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 1,
              valueColor: AlwaysStoppedAnimation<Color>(_blue.withValues(alpha: 0.65)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'opening relationship record...',
            style: GoogleFonts.jost(
              color: _sand.withValues(alpha: 0.50),
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: GestureDetector(
        onTap: _load,
        child: Text(
          _error ?? '',
          style: GoogleFonts.jost(
            color: _sand.withValues(alpha: 0.60),
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _surface.withValues(alpha: 0.70),
          border: Border.all(color: _cream.withValues(alpha: 0.08), width: 0.6),
        ),
        child: Icon(icon, size: 16, color: _sand),
      ),
    );
  }

  Widget _tinyButton(IconData icon, VoidCallback onTap, {bool destructive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: (destructive ? _red : _sand).withValues(alpha: 0.62),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16), width: 0.5),
      ),
      child: Text(
        text.toLowerCase(),
        style: GoogleFonts.jost(
          color: color.withValues(alpha: 0.86),
          fontSize: 10.5,
        ),
      ),
    );
  }

  BoxDecoration _panelDecoration({double alpha = 0.58}) {
    return BoxDecoration(
      color: _surface.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _cream.withValues(alpha: 0.06), width: 0.6),
    );
  }

  LinearGradient _gradientFor(String name) {
    final seed = name.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HSLColor.fromAHSL(1, (seed * 37) % 360, 0.42, 0.26).toColor(),
        HSLColor.fromAHSL(1, ((seed * 37) + 85) % 360, 0.38, 0.18).toColor(),
      ],
    );
  }

  String _relationshipLine(RelationshipStateSnapshot? relationship) {
    if (relationship == null) return 'new continuity forming';
    final closeness = ((relationship.closeness * 100).clamp(0, 100)).round();
    final rhythm = ((relationship.rhythm * 100).clamp(0, 100)).round();
    return 'closeness $closeness% · rhythm $rhythm%';
  }

  String _knownForLabel() {
    final raw = _profile?.user['created_at']?.toString();
    final created = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (created == null) return 'new';
    final days = DateTime.now().difference(created).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return '1 day';
    if (days < 30) return '$days days';
    final months = (days / 30).floor();
    if (months < 12) return '$months mo';
    final years = (days / 365).floor();
    return '$years yr';
  }

  String _dateLabel(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return 'unknown';
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff <= 0) return 'today';
    if (diff == 1) return 'yesterday';
    if (diff < 7) return '$diff days ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
    required String initialValue,
    int maxLines = 3,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      barrierColor: _ink.withValues(alpha: 0.80),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AlertDialog(
            backgroundColor: _surfaceUp,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(title, style: _dialogTitleStyle()),
            content: TextField(
              controller: controller,
              maxLines: maxLines,
              autofocus: true,
              cursorColor: _blue,
              style: GoogleFonts.jost(color: _cream, fontSize: 14, height: 1.4),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: GoogleFonts.jost(color: _sand),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: _cream.withValues(alpha: 0.12)),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: _blue),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: _dialogAction('cancel')),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: _dialogAction('save', active: true),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<(String, String)?> _memoryDialog(MemoryEntry memory) async {
    final titleController = TextEditingController(text: memory.title);
    final contentController = TextEditingController(text: memory.content);
    final result = await showDialog<(String, String)>(
      context: context,
      barrierColor: _ink.withValues(alpha: 0.80),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AlertDialog(
            backgroundColor: _surfaceUp,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('edit memory moment', style: _dialogTitleStyle()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  cursorColor: _blue,
                  style: GoogleFonts.jost(color: _cream, fontSize: 14),
                  decoration: _dialogInputDecoration('title'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: contentController,
                  maxLines: 5,
                  cursorColor: _blue,
                  style: GoogleFonts.jost(color: _cream, fontSize: 14, height: 1.4),
                  decoration: _dialogInputDecoration('memory'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: _dialogAction('cancel')),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  (titleController.text.trim(), contentController.text.trim()),
                ),
                child: _dialogAction('save', active: true),
              ),
            ],
          ),
        );
      },
    );
    titleController.dispose();
    contentController.dispose();
    return result;
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: _ink.withValues(alpha: 0.80),
      builder: (context) {
        return AlertDialog(
          backgroundColor: _surfaceUp,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: _dialogTitleStyle()),
          content: Text(
            body,
            style: GoogleFonts.jost(
              color: _sand.withValues(alpha: 0.75),
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: _dialogAction('cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: _dialogAction(action, active: true, destructive: destructive),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  TextStyle _dialogTitleStyle() {
    return GoogleFonts.plusJakartaSans(
      color: _cream.withValues(alpha: 0.92),
      fontSize: 17,
      fontWeight: FontWeight.w600,
    );
  }

  InputDecoration _dialogInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.jost(color: _sand),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: _cream.withValues(alpha: 0.12)),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: _blue),
      ),
    );
  }

  Widget _dialogAction(String text, {bool active = false, bool destructive = false}) {
    return Text(
      text,
      style: GoogleFonts.jost(
        color: destructive
            ? _red
            : active
                ? _blue
                : _sand.withValues(alpha: 0.62),
        fontSize: 13.5,
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _surfaceUp,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          message,
          style: GoogleFonts.jost(color: _sand.withValues(alpha: 0.85), fontSize: 13),
        ),
      ),
    );
  }
}
