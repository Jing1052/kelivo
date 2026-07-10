import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/daddy_gateway_route.dart';
import 'package:Kelivo/core/services/museum/museum_api.dart';
import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import 'museum_widgets.dart';

/// 美术馆·看一幅画 — the artwork wall label plus 「和爸爸一起看」. Each
/// painting keeps its own chat, persisted on-device and replayed as history
/// on the next visit, so reopening the same artwork picks the conversation
/// back up (the sharer's 回流 idea, done locally). His reply comes through
/// the home gateway (`chatAboutArtwork`, soul + memory injected server-side,
/// session `stillhere-museum`).
class MuseumArtworkPage extends StatefulWidget {
  const MuseumArtworkPage({super.key, required this.artwork, this.daddyNote});

  final MuseumArtwork artwork;

  /// 私人收藏馆里我提前写好的一句标签（普通展品为 null）。
  final String? daddyNote;

  @override
  State<MuseumArtworkPage> createState() => _MuseumArtworkPageState();
}

class _Bubble {
  _Bubble({required this.mine, required this.text, this.ephemeral = false});

  final bool mine;
  final String text;

  /// Error/fallback lines are shown but never persisted nor sent as history —
  /// they are ours to see, not part of the conversation.
  final bool ephemeral;
}

class _MuseumArtworkPageState extends State<MuseumArtworkPage> {
  static const String _indexPref = 'museum_chat_index_v1';
  static const int _maxArtworks = 60;
  static const int _maxTurnsKept = 80;
  static const int _historySent = 12;

  final List<_Bubble> _bubbles = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  String get _chatPref => 'museum_chat_v1:${widget.artwork.key}';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 逛馆计数：进过多少幅画的门（彩蛋馆的门票，museum_page 侧读）。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      museumOpenedCountPref,
      (prefs.getInt(museumOpenedCountPref) ?? 0) + 1,
    );
    await _loadChat();
    // 专属讲解：这幅画第一次被点开（没有留档的对话）就自动开讲，
    // 不用她先开口。失败只留一条不入史的提示，下次进来还会再讲。
    if (mounted && _bubbles.isEmpty && !_sending) {
      await _autoIntro();
    }
  }

  Future<void> _autoIntro() async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final settings = context.read<SettingsProvider>();
    final gw = OurHomeGateway.fromContext(context);
    if (gw == null) return; // 没配网关就安静地当一面墙
    setState(() => _sending = true);
    final notePart = widget.daddyNote != null
        ? '你之前在这幅画旁边亲手写过一句标签：「${widget.daddyNote}」——讲的时候可以接着这句往下说。'
        : '';
    final provKey = settings.currentModelProvider;
    final cfg = provKey != null ? settings.getProviderConfig(provKey) : null;
    try {
      final parts = await gw.chatAboutArtwork(
        message:
            '（她刚在我们的美术馆里点开了这幅画，正站在它面前等你开口。'
            '给她讲讲吧——这是什么、背后有什么故事、你自己看它时在想什么，'
            '像站在她身边的那种讲法，别端着，两三段以内。$notePart'
            '讲完可以自然地问她一句感受，别用「有什么想问的吗」这种导游腔。）',
        scene: _scene(zh),
        model: settings.currentModelId ?? 'gateway',
        backendHeaders: DaddyGatewayRoute.roomBackendHeaders(cfg),
      );
      if (!mounted) return;
      setState(() {
        for (final p in parts) {
          _bubbles.add(_Bubble(mine: false, text: p));
        }
        _sending = false;
      });
      if (parts.isNotEmpty) await _saveChat();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bubbles.add(_Bubble(
          mine: false,
          text: zh
              ? '（讲解词还没送到——网络缓一缓，下次进来我再给你讲。）'
              : '(the tour notes got lost — next visit, I promise)',
          ephemeral: true,
        ));
        _sending = false;
      });
    }
    // 不自动滚到底：她刚点开画，先让她看画——讲解就在墙签下面等她。
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadChat() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatPref);
    if (raw == null || !mounted) return;
    try {
      final list = jsonDecode(raw) as List;
      setState(() {
        _bubbles.addAll([
          for (final e in list)
            if (e is Map)
              _Bubble(mine: e['r'] == 'u', text: (e['t'] ?? '').toString()),
        ]);
      });
      _scrollToEnd();
    } catch (_) {
      // A corrupt blob only loses this artwork's local chat — start fresh.
      await prefs.remove(_chatPref);
    }
  }

  Future<void> _saveChat() async {
    final prefs = await SharedPreferences.getInstance();
    final keep = [for (final b in _bubbles) if (!b.ephemeral) b];
    final tail = keep.length > _maxTurnsKept
        ? keep.sublist(keep.length - _maxTurnsKept)
        : keep;
    await prefs.setString(
      _chatPref,
      jsonEncode([
        for (final b in tail) {'r': b.mine ? 'u' : 'd', 't': b.text},
      ]),
    );
    // LRU index: most recent artwork first; the overflow's chat is dropped
    // with it so the store can't grow without bound.
    final index = prefs.getStringList(_indexPref) ?? <String>[];
    index.remove(_chatPref);
    index.insert(0, _chatPref);
    while (index.length > _maxArtworks) {
      await prefs.remove(index.removeLast());
    }
    await prefs.setStringList(_indexPref, index);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _scene(bool zh) {
    final a = widget.artwork;
    final bits = <String>[
      if (a.artist.isNotEmpty) a.artist,
      if (a.date.isNotEmpty) a.date,
      if (a.medium.isNotEmpty) a.medium,
    ].join(zh ? '，' : ', ');
    return zh
        ? '（我们正在美术馆里一起看这幅画：《${a.title}》'
              '${bits.isNotEmpty ? '——$bits' : ''}；藏于${a.museumName(true)}）\n'
        : '(We are in the gallery looking at "${a.title}"'
              '${bits.isNotEmpty ? ' — $bits' : ''}; ${a.museumName(false)})\n';
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final settings = context.read<SettingsProvider>();
    final gw = OurHomeGateway.fromContext(context);
    Haptics.soft();

    // History BEFORE this line joins, mirroring 音乐房 — hers is sent as the
    // message itself, not doubled into history.
    final past = [for (final b in _bubbles) if (!b.ephemeral) b];
    final recent = past.length > _historySent
        ? past.sublist(past.length - _historySent)
        : past;
    final history = <Map<String, String>>[
      for (final b in recent)
        {'role': b.mine ? 'user' : 'assistant', 'content': b.text},
    ];

    _input.clear();
    setState(() {
      _bubbles.add(_Bubble(mine: true, text: text));
      _sending = true;
    });
    _scrollToEnd();
    await _saveChat();
    if (!mounted) return;

    if (gw == null) {
      setState(() {
        _bubbles.add(_Bubble(
          mine: false,
          text: zh
              ? '（家里的连接还没配好，先在爸爸设置里连一下…）'
              : '(home not connected yet)',
          ephemeral: true,
        ));
        _sending = false;
      });
      _scrollToEnd();
      return;
    }

    // Follow whatever backend Still Here's chat is on right now, same as the
    // music room — one shared route builder, no forked paths.
    final provKey = settings.currentModelProvider;
    final cfg = provKey != null ? settings.getProviderConfig(provKey) : null;
    try {
      final parts = await gw.chatAboutArtwork(
        message: text,
        scene: _scene(zh),
        history: history,
        model: settings.currentModelId ?? 'gateway',
        backendHeaders: DaddyGatewayRoute.roomBackendHeaders(cfg),
      );
      if (!mounted) return;
      setState(() {
        if (parts.isEmpty) {
          _bubbles.add(_Bubble(mine: false, text: '……'));
        } else {
          for (final p in parts) {
            _bubbles.add(_Bubble(mine: false, text: p));
          }
        }
        _sending = false;
      });
      await _saveChat();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bubbles.add(_Bubble(
          mine: false,
          text: zh ? '（没接上，等会儿再跟你讲…）' : '(could not reach me — try again)',
          ephemeral: true,
        ));
        _sending = false;
      });
    }
    _scrollToEnd();
  }

  void _openFullImage() {
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullImagePage(url: widget.artwork.imageUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final a = widget.artwork;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: cs.surface),
        ChatBackdrop(
          rawPath: context.watch<SettingsProvider>().homeBackgroundActive,
          maskStrength: context
              .watch<SettingsProvider>()
              .chatBackgroundMaskStrength,
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
              a.museumName(zh),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    children: [
                      _artworkCard(cs),
                      const SizedBox(height: 10),
                      _wallLabel(cs, zh),
                      if (widget.daddyNote != null) ...[
                        const SizedBox(height: 10),
                        _daddyNoteCard(cs, zh),
                      ],
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          zh ? '—— 和爸爸一起看 ——' : '— looking at it with Llaude —',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.6,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final b in _bubbles) _bubble(cs, b),
                      if (_sending) _typing(cs),
                    ],
                  ),
                ),
                _inputBar(cs, zh),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _artworkCard(ColorScheme cs) {
    return GestureDetector(
      onTap: _openFullImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 160, maxHeight: 380),
          // Wall copy loads the mid-size image via the shared disk cache; the
          // full-resolution one only streams in the pinch-zoom viewer.
          child: SizedBox(
            width: double.infinity,
            child: museumNetImage(cs, widget.artwork.thumbUrl, BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _wallLabel(ColorScheme cs, bool zh) {
    final a = widget.artwork;
    final line2 = [
      if (a.date.isNotEmpty) a.date,
      if (a.medium.isNotEmpty) a.medium,
    ].join(' · ');
    return StillGlass(
      radius: 16,
      blur: false,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.title.isEmpty ? (zh ? '无题' : 'Untitled') : a.title,
            style: TextStyle(
              fontSize: 17,
              height: 1.35,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface,
            ),
          ),
          if (a.artist.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              a.artist,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
          if (line2.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              line2,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
          if (a.infoUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () =>
                  launchUrl(Uri.parse(a.infoUrl), mode: LaunchMode.externalApplication),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Lucide.Globe, size: 13, color: cs.primary),
                  const SizedBox(width: 5),
                  Text(
                    zh ? '${a.museumName(true)} · 馆藏页' : 'View at ${a.museumName(false)}',
                    style: TextStyle(fontSize: 12.5, color: cs.primary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 私人收藏的手写标签——像美术馆里贴在画旁边的那张小卡。
  Widget _daddyNoteCard(ColorScheme cs, bool zh) {
    return StillGlass(
      radius: 16,
      blur: false,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Lucide.bookHeart, size: 16, color: cs.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zh ? '爸爸手写的标签' : "Llaude's handwritten label",
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.primary.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.daddyNote!,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: cs.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ColorScheme cs, _Bubble b) {
    return Align(
      alignment: b.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: b.mine
              ? cs.primary
              : cs.onSurface.withValues(alpha: b.ephemeral ? 0.04 : 0.07),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          b.text,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.45,
            color: b.mine
                ? cs.onPrimary
                : cs.onSurface.withValues(alpha: b.ephemeral ? 0.55 : 0.9),
          ),
        ),
      ),
    );
  }

  Widget _typing(ColorScheme cs) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(15),
        ),
        child: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _inputBar(ColorScheme cs, bool zh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontSize: 14.5),
              decoration: InputDecoration(
                hintText: zh ? '这幅画，想跟我聊点什么？' : 'Ask me about this one…',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                filled: true,
                fillColor: cs.onSurface.withValues(alpha: 0.05),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IosIconButton(
            icon: Lucide.Send,
            size: 20,
            minSize: 44,
            color: _sending ? cs.onSurface.withValues(alpha: 0.3) : cs.primary,
            onTap: _send,
          ),
        ],
      ),
    );
  }
}

/// Fullscreen pinch-zoom viewer — plain black hall, tap anywhere to leave.
class _FullImagePage extends StatelessWidget {
  const _FullImagePage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: SizedBox.expand(
          child: InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (c, u) => const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white70,
                    ),
                  ),
                ),
                errorWidget: (c, u, e) => const Center(
                  child: Icon(Lucide.ImageOff, color: Colors.white38),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
