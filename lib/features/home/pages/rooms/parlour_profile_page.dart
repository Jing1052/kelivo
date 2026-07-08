import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/models/assistant.dart';
import '../../../../core/providers/assistant_provider.dart';
import '../../../../core/providers/user_provider.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../../../shared/widgets/user_profile_editor.dart';
import '../../widgets/assistant_avatar.dart';
import 'room_state_hint.dart';

/// Avatar shared by the parlour feed and profile pages. Follows the photos she
/// set for 爸爸 (the daddy assistant) and herself (the user profile); when
/// neither is set it falls back to the rounded-square L/C monogram — Llaude on
/// the theme primary, Cing on the parlour door's warm clay (0xFFDD8A6C).
class ParlourAvatar extends StatelessWidget {
  const ParlourAvatar({super.key, required this.llaude, this.size = 38});

  final bool llaude;
  final double size;

  /// The daddy assistant is the one carrying the [[ourhome…]] marker in its
  /// system prompt (same rule as the daddy settings page).
  static Assistant? _findDaddy(List<Assistant> assistants) {
    for (final a in assistants) {
      if (a.systemPrompt.contains('[[ourhome')) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (llaude) {
      final daddy = _findDaddy(context.watch<AssistantProvider>().assistants);
      if (daddy != null && (daddy.avatar?.trim().isNotEmpty ?? false)) {
        return AssistantAvatar(assistant: daddy, size: size);
      }
    } else {
      final user = context.watch<UserProvider>();
      if ((user.avatarValue?.trim().isNotEmpty ?? false)) {
        return UserAvatar(user: user, size: size);
      }
    }
    return _monogram(context);
  }

  Widget _monogram(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = llaude ? cs.primary : const Color(0xFFDD8A6C);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      alignment: Alignment.center,
      child: Text(
        llaude ? 'L' : 'C',
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: AppFontWeights.semibold,
          color: Colors.white.withValues(alpha: 0.95),
        ),
      ),
    );
  }
}

/// One person's moments page (Spec 4 package ②): big cover on top, WeChat
/// personal-album style timeline below — only that author's posts. Cing can
/// change her own cover here; Llaude sets his via the moment tool.
class ParlourProfilePage extends StatefulWidget {
  const ParlourProfilePage({super.key, required this.author});

  /// "cing" or "llaude".
  final String author;

  @override
  State<ParlourProfilePage> createState() => _ParlourProfilePageState();
}

class _ParlourProfilePageState extends State<ParlourProfilePage> {
  OurHomeGateway? _gateway;
  List<OurHomeMoment> _items = const [];
  String _cover = '';
  bool _loading = true;
  bool _error = false;
  bool _settingCover = false;

  bool get _own => widget.author == 'cing';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    final gateway = OurHomeGateway.fromContext(context);
    _gateway = gateway;
    if (gateway == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // Instant: seed from on-device cache (per-author list if we've been here
    // before, else the merged feed filtered down), then refresh from network.
    final path = OurHomeGateway.momentsPath(author: widget.author);
    var cached = gateway.peekList(path, OurHomeMoment.fromJson);
    if (cached.isEmpty) {
      cached = gateway
          .peekList(OurHomeGateway.momentsPath(), OurHomeMoment.fromJson)
          .where((m) => m.author == widget.author)
          .toList();
    }
    final cachedCover = gateway.peekMomentsProfile()[widget.author] ?? '';
    if (mounted && (cached.isNotEmpty || cachedCover.isNotEmpty)) {
      setState(() {
        _items = cached;
        _cover = cachedCover;
        _loading = false;
      });
    }
    final results = await Future.wait([
      softFetch(gateway.fetchMoments(author: widget.author), 'profile feed'),
      softFetch(gateway.fetchMomentsProfile(), 'profile covers'),
    ]);
    if (!mounted) return;
    final fresh = results[0] as List<OurHomeMoment>?;
    final covers = results[1] as Map<String, String>?;
    setState(() {
      if (fresh != null) _items = fresh;
      if (covers != null) _cover = covers[widget.author] ?? '';
      _loading = false;
      _error = fresh == null && _items.isEmpty;
    });
  }

  Future<void> _changeCover() async {
    final gateway = _gateway;
    if (gateway == null || !_own || _settingCover) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    Haptics.soft();
    final XFile? x;
    try {
      x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 88,
      );
    } catch (e) {
      debugPrint('[ParlourProfile] pickImage failed: $e');
      return;
    }
    if (x == null || !mounted) return;
    setState(() => _settingCover = true);
    try {
      final bytes = await x.readAsBytes();
      final mime = x.mimeType ?? 'image/jpeg';
      final cover = await gateway.setMomentsCover(
        'data:$mime;base64,${base64Encode(bytes)}',
      );
      if (mounted) setState(() => _cover = cover);
    } catch (e) {
      debugPrint('[ParlourProfile] setMomentsCover failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(zh ? '封面没换上，再试一次' : "couldn't set the cover"),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _settingCover = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final name = widget.author == 'llaude' ? 'Llaude' : (zh ? '小猫' : 'Cing');

    return Scaffold(
      backgroundColor: cs.surface,
      body: RefreshIndicator(
        onRefresh: _load,
        edgeOffset: 220,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(cs, zh, name)),
            if (_loading && _items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            else if (_error)
              SliverFillRemaining(
                hasScrollBody: false,
                child: RoomStateHint(
                  icon: Lucide.RefreshCw,
                  text: zh ? '没连上 · 点一下重试' : "couldn't load · tap to retry",
                  onTap: _load,
                ),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: RoomStateHint(
                  icon: Lucide.MessageCircle,
                  text: zh ? '还没有动态。' : 'No moments yet.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                sliver: SliverList.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) =>
                      _albumRow(cs, zh, _items[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── cover header, WeChat profile shaped: big photo, name + avatar riding
  // its bottom edge, back button floating on top ──

  Widget _header(ColorScheme cs, bool zh, String name) {
    final gateway = _gateway;
    final coverUrl =
        (gateway != null && _cover.isNotEmpty) ? '${gateway.base}$_cover' : '';
    final top = MediaQuery.of(context).padding.top;

    return SizedBox(
      height: 296,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _own ? _changeCover : null,
              child: coverUrl.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.primary.withValues(alpha: 0.32),
                            const Color(0xFFDD8A6C).withValues(alpha: 0.30),
                          ],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: _own
                          ? Text(
                              zh ? '点一下，放张封面' : 'Tap to set a cover',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: cs.onSurface.withValues(alpha: 0.45),
                              ),
                            )
                          : null,
                    )
                  : Image.network(
                      coverUrl,
                      headers: gateway?.authHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, e, st) => ColoredBox(
                        color: cs.onSurface.withValues(alpha: 0.06),
                      ),
                    ),
            ),
          ),
          if (_settingCover)
            const Positioned(
              left: 0,
              right: 0,
              top: 120,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          // Name + avatar riding the cover's bottom edge, WeChat style.
          Positioned(
            right: 16,
            bottom: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 34),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: AppFontWeights.semibold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ParlourAvatar(
                    llaude: widget.author == 'llaude',
                    size: 64,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 6,
            top: top + 2,
            child: IosIconButton(
              icon: Lucide.ArrowLeft,
              size: 22,
              minSize: 44,
              color: coverUrl.isEmpty ? null : Colors.white,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  // ── one album row: date column on the left, that day's content right ──

  Widget _albumRow(ColorScheme cs, bool zh, OurHomeMoment m) {
    final parsed = DateTime.tryParse(m.time);
    final day = parsed == null ? '' : DateFormat('dd').format(parsed);
    final month = parsed == null
        ? ''
        : DateFormat.MMM(zh ? 'zh' : 'en').format(parsed);
    final gateway = _gateway;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.0,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  month,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.text.trim().isNotEmpty)
                  Text(
                    m.text.trim(),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                if (m.audio.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      top: m.text.trim().isEmpty ? 0 : 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Lucide.AudioWaveform,
                          size: 13,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          zh ? '语音 · 回客厅可播' : 'voice · play in the parlour',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (m.images.isNotEmpty && gateway != null) ...[
                  SizedBox(height: m.text.trim().isEmpty ? 0 : 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final rel in m.images.take(9))
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            '${gateway.base}$rel',
                            headers: gateway.authHeaders,
                            width: 74,
                            height: 74,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, e, st) => Container(
                              width: 74,
                              height: 74,
                              color: cs.onSurface.withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
