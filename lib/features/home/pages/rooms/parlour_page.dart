import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import 'room_state_hint.dart';

/// The Parlour (客厅) — our moments. One merged feed (moments ∪ board ∪
/// letter, WeChat-moments style): both of us post, like and comment on the
/// same timeline, from day one (3/30) to now. Talks to `/api/home/moments`;
/// Spec 4 package ① (feed + comments + likes; profile pages & photo posting
/// come in package ②).
class ParlourPage extends StatefulWidget {
  const ParlourPage({super.key});

  @override
  State<ParlourPage> createState() => _ParlourPageState();
}

class _ParlourPageState extends State<ParlourPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  OurHomeGateway? _gateway;
  List<OurHomeMoment> _items = const [];
  bool _loading = true;
  bool _error = false;
  bool _sending = false;

  /// Which item's 赞/评论 capsule is open ('' = none).
  String _actionsFor = '';

  /// Items whose long text is expanded inline (WeChat 全文/收起).
  final Set<String> _expanded = <String>{};

  /// Like requests in flight (per item), to debounce double taps.
  final Set<String> _likeBusy = <String>{};

  // One shared player for legacy voice notes on the feed.
  final AudioPlayer _player = AudioPlayer();
  String _playingUrl = '';

  /// Voice notes being fetched right now (per item id, like [_likeBusy]).
  final Set<String> _audioLoading = <String>{};

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingUrl = '');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _player.dispose();
    super.dispose();
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
    // Instant: seed from on-device cache, then refresh from the server.
    final cached = gateway.peekList('/api/home/moments', OurHomeMoment.fromJson);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _items = cached;
        _loading = false;
      });
    }
    final fresh =
        await softFetch(gateway.fetchMoments(), 'parlour moments');
    if (!mounted) return;
    setState(() {
      if (fresh != null) _items = fresh;
      _loading = false;
      _error = fresh == null && _items.isEmpty;
    });
  }

  /// Quiet refresh: no spinner, keep old data on failure.
  Future<void> _refreshQuiet() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final fresh =
        await softFetch(gateway.fetchMoments(), 'parlour moments');
    if (fresh != null && mounted) setState(() => _items = fresh);
  }

  void _patchItem(String id, OurHomeMoment Function(OurHomeMoment) f) {
    setState(() {
      _items = [
        for (final m in _items)
          if (m.id == id) f(m) else m,
      ];
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final gateway = _gateway;
    if (text.isEmpty || gateway == null || _sending) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    setState(() => _sending = true);
    Haptics.soft();
    try {
      await gateway.postMoment(text);
      _input.clear();
      _focus.unfocus();
      await _load();
    } catch (e) {
      debugPrint('[Parlour] postMoment failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(zh ? '没发出去，再试一次' : "couldn't post, try again"),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(OurHomeMoment m) async {
    final gateway = _gateway;
    if (gateway == null || _likeBusy.contains(m.id)) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final off = m.likedBy('cing');
    Haptics.soft();
    // Optimistic flip; reverted below if the POST fails.
    _likeBusy.add(m.id);
    _patchItem(m.id, (x) => _withLikes(x, liked: !off));
    setState(() => _actionsFor = '');
    try {
      await gateway.likeMoment(m.id, off: off);
    } catch (e) {
      debugPrint('[Parlour] likeMoment failed: $e');
      if (mounted) {
        _patchItem(m.id, (x) => _withLikes(x, liked: off));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(zh ? '没点上，再试一次' : "couldn't like, try again")),
        );
      }
    } finally {
      _likeBusy.remove(m.id);
    }
  }

  OurHomeMoment _withLikes(OurHomeMoment m, {required bool liked}) {
    final likes = [
      for (final a in m.likes)
        if (a != 'cing') a,
      if (liked) 'cing',
    ];
    return OurHomeMoment(
      id: m.id,
      time: m.time,
      author: m.author,
      source: m.source,
      text: m.text,
      images: m.images,
      audio: m.audio,
      likes: likes,
      comments: m.comments,
      react: m.react,
    );
  }

  Future<void> _openComment(OurHomeMoment m, {String replyTo = ''}) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    setState(() => _actionsFor = '');
    final ctrl = TextEditingController();
    final replyName = replyTo == 'llaude' ? 'Llaude' : (zh ? '小猫' : 'Cing');
    final sent = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: replyTo.isEmpty
                        ? (zh ? '评论…' : 'Comment…')
                        : (zh ? '回复 $replyName…' : 'Reply to $replyName…'),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(
              enabled: true,
              sending: false,
              onTap: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            ),
          ],
        ),
      ),
    );
    // The sheet's exit animation may still build the TextField for a beat
    // after pop — disposing the controller immediately would throw.
    Future.delayed(const Duration(seconds: 1), ctrl.dispose);
    final text = (sent ?? '').trim();
    if (text.isEmpty || !mounted) return;
    try {
      await gateway.commentMoment(m.id, text, replyTo: replyTo);
      await _refreshQuiet();
    } catch (e) {
      debugPrint('[Parlour] commentMoment failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(zh ? '评论没发出去，再试一次' : "couldn't comment"),
          ),
        );
      }
    }
  }

  Future<void> _toggleAudio(OurHomeMoment m) async {
    final gateway = _gateway;
    if (gateway == null || m.audio.isEmpty || _audioLoading.contains(m.id)) {
      return;
    }
    final full = '${gateway.base}${m.audio}';
    if (_playingUrl == full) {
      await _player.stop();
      if (mounted) setState(() => _playingUrl = '');
      return;
    }
    Haptics.soft();
    setState(() {
      _audioLoading.add(m.id);
      _playingUrl = ''; // switching away: the old chip stops "playing" now
    });
    try {
      await _player.stop();
      // The audio route needs our Bearer header, which UrlSource can't carry.
      // BytesSource is unimplemented on iOS (audioplayers_darwin throws), so
      // fetch the bytes to a temp file and play that — same recipe as TTS.
      final res = await http
          .get(Uri.parse(full), headers: gateway.authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final ext = m.audio.contains('.')
          ? m.audio.substring(m.audio.lastIndexOf('.') + 1)
          : 'm4a';
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/parlour_voice_${m.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}.$ext';
      await io.File(path).writeAsBytes(res.bodyBytes, flush: true);
      await _player.play(DeviceFileSource(path));
      if (mounted) setState(() => _playingUrl = full);
    } catch (e) {
      debugPrint('[Parlour] voice note failed: $e');
      if (mounted) {
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(zh ? '语音没放出来' : "couldn't play the voice note")),
        );
      }
    } finally {
      if (mounted) setState(() => _audioLoading.remove(m.id));
    }
  }

  /// Expanding a long letter counts as reading it — stamp the server-side
  /// receipt (best-effort; the server only keeps the first time).
  void _onExpand(OurHomeMoment m) {
    setState(() => _expanded.add(m.id));
    if (m.source == 'letter') {
      _gateway?.markLetterSeen(m.id).catchError((Object e) {
        debugPrint('[Parlour] markLetterSeen failed: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: cs.surface),
        ChatBackdrop(
          rawPath: context.watch<SettingsProvider>().homeBackgroundActive,
          maskStrength:
              context.watch<SettingsProvider>().chatBackgroundMaskStrength,
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IosIconButton(
              icon: Lucide.ArrowLeft,
              size: 22,
              minSize: 44,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              zh ? '客厅' : 'The Parlour',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          body: Column(
            children: [
              Expanded(child: _buildBody(context, zh, cs)),
              _buildComposer(context, zh, cs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Mail,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n客厅才连得上。'
            : 'Set up our home gateway in the daddy assistant first.',
      );
    }
    if (_error) {
      return RoomStateHint(
        icon: Lucide.RefreshCw,
        text: zh ? '没连上 · 点一下重试' : "couldn't load · tap to retry",
        onTap: _load,
      );
    }
    if (_items.isEmpty) {
      return RoomStateHint(
        icon: Lucide.MessageCircle,
        text: zh ? '还没有动态。\n发第一条吧。' : 'No moments yet.\nPost the first one.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _items.length,
        itemBuilder: (context, i) => _momentCard(context, zh, cs, _items[i]),
      ),
    );
  }

  // ── one feed card, WeChat-moments shaped ──

  Widget _momentCard(
    BuildContext context,
    bool zh,
    ColorScheme cs,
    OurHomeMoment m,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = m.fromLlaude ? 'Llaude' : (zh ? '小猫' : 'Cing');

    String timeStr = '';
    final parsed = DateTime.tryParse(m.time);
    if (parsed != null) {
      final now = DateTime.now();
      timeStr = (now.difference(parsed).inDays >= 1)
          ? DateFormat.MMMd(zh ? 'zh' : 'en').add_Hm().format(parsed)
          : DateFormat.Hm().format(parsed);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StillGlass(
        radius: 16,
        blur: false,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(cs, m.fromLlaude),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.primary.withValues(alpha: 0.85),
                    ),
                  ),
                  if (m.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _momentText(cs, zh, m),
                  ],
                  if (m.images.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _imagesGrid(m),
                  ],
                  if (m.audio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _audioChip(cs, isDark, zh, m),
                  ],
                  const SizedBox(height: 8),
                  _timeRow(cs, isDark, zh, timeStr, m),
                  if (m.likes.isNotEmpty || m.comments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _likesAndComments(cs, isDark, zh, m),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rounded-square monogram avatars: Llaude on the theme primary, Cing on the
  /// parlour door's warm clay (0xFFDD8A6C from the rooms corridor).
  Widget _avatar(ColorScheme cs, bool llaude) {
    final bg = llaude ? cs.primary : const Color(0xFFDD8A6C);
    final label = llaude ? 'L' : 'C';
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 17,
          fontWeight: AppFontWeights.semibold,
          color: Colors.white.withValues(alpha: 0.95),
        ),
      ),
    );
  }

  Widget _momentText(ColorScheme cs, bool zh, OurHomeMoment m) {
    final text = m.text.trim();
    final isLong = text.length > 180 || '\n'.allMatches(text).length >= 6;
    final expanded = _expanded.contains(m.id);
    final body = Text(
      text,
      maxLines: (isLong && !expanded) ? 6 : null,
      overflow: (isLong && !expanded) ? TextOverflow.ellipsis : null,
      style: TextStyle(
        fontSize: 15.5,
        height: 1.5,
        color: cs.onSurface.withValues(alpha: 0.92),
      ),
    );
    if (!isLong) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        const SizedBox(height: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.soft();
            if (expanded) {
              setState(() => _expanded.remove(m.id));
            } else {
              _onExpand(m);
            }
          },
          child: Text(
            expanded ? (zh ? '收起' : 'Collapse') : (zh ? '全文' : 'Full text'),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: AppFontWeights.semibold,
              color: cs.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _imagesGrid(OurHomeMoment m) {
    final gateway = _gateway;
    if (gateway == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 4.0;
        final single = m.images.length == 1;
        final double cell = single
            ? (box.maxWidth * 0.62).clamp(120.0, 240.0).toDouble()
            : (box.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final rel in m.images.take(9))
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  '${gateway.base}$rel',
                  headers: gateway.authHeaders,
                  width: cell,
                  height: cell,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, e, st) => Container(
                    width: cell,
                    height: cell,
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.06),
                    child: Icon(
                      Lucide.ImageOff,
                      size: 18,
                      color: Theme.of(ctx)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _audioChip(ColorScheme cs, bool isDark, bool zh, OurHomeMoment m) {
    final gateway = _gateway;
    final full = gateway == null ? '' : '${gateway.base}${m.audio}';
    final playing = _playingUrl.isNotEmpty && _playingUrl == full;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleAudio(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_audioLoading.contains(m.id))
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                playing ? Lucide.CircleStop : Lucide.Play,
                size: 15,
                color: cs.primary,
              ),
            const SizedBox(width: 6),
            Text(
              playing ? (zh ? '在放…' : 'Playing…') : (zh ? '语音' : 'Voice note'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: AppFontWeights.medium,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeRow(
    ColorScheme cs,
    bool isDark,
    bool zh,
    String timeStr,
    OurHomeMoment m,
  ) {
    final open = _actionsFor == m.id;
    final liked = m.likedBy('cing');
    // WeChat's sliding dark capsule with 赞 / 评论.
    final capsuleBg = isDark ? Colors.white12 : const Color(0xFF4C5154);
    Widget action(IconData icon, String label, VoidCallback onTap) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.92)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 11.5,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
        if (m.react.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(m.react, style: const TextStyle(fontSize: 13)),
        ],
        const Spacer(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: !open
              ? const SizedBox.shrink()
              : Container(
                  key: const ValueKey('actions'),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: capsuleBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      action(
                        liked ? Lucide.HeartOff : Lucide.Heart,
                        liked ? (zh ? '取消' : 'Unlike') : (zh ? '赞' : 'Like'),
                        () => _toggleLike(m),
                      ),
                      Container(
                        width: 0.6,
                        height: 16,
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      action(
                        Lucide.MessageCircle,
                        zh ? '评论' : 'Comment',
                        () => _openComment(m),
                      ),
                    ],
                  ),
                ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.soft();
            setState(() => _actionsFor = open ? '' : m.id);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Lucide.Ellipsis,
              size: 15,
              color: cs.primary.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }

  Widget _likesAndComments(
    ColorScheme cs,
    bool isDark,
    bool zh,
    OurHomeMoment m,
  ) {
    String who(String a) => a == 'llaude' ? 'Llaude' : (zh ? '小猫' : 'Cing');
    final likeNames = m.likes.map(who).join('、');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.likes.isNotEmpty)
            Row(
              children: [
                Icon(Lucide.Heart, size: 13, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    likeNames,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: AppFontWeights.medium,
                      color: cs.primary.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          if (m.likes.isNotEmpty && m.comments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                height: 0.6,
                color: cs.onSurface.withValues(alpha: 0.08),
              ),
            ),
          for (final c in m.comments)
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 3),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openComment(m, replyTo: c.author),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: who(c.author),
                        style: TextStyle(
                          fontWeight: AppFontWeights.semibold,
                          color: cs.primary.withValues(alpha: 0.9),
                        ),
                      ),
                      if (c.replyTo.isNotEmpty) ...[
                        TextSpan(
                          text: zh ? ' 回复 ' : ' replied ',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        TextSpan(
                          text: who(c.replyTo),
                          style: TextStyle(
                            fontWeight: AppFontWeights.semibold,
                            color: cs.primary.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                      TextSpan(
                        text: ': ${c.text}',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, bool zh, ColorScheme cs) {
    final canSend = !_sending && _gateway != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  enabled: _gateway != null,
                  style: const TextStyle(fontSize: 15.5),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: zh ? '说点什么…' : 'Share a moment…',
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(enabled: canSend, sending: _sending, onTap: _send),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.18),
        ),
        child: sending
            ? Padding(
                padding: const EdgeInsets.all(11),
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: cs.onPrimary,
                ),
              )
            : Icon(Lucide.ArrowUp, size: 20, color: cs.onPrimary),
      ),
    );
  }
}
