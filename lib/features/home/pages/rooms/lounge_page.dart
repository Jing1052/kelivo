import 'package:flutter/material.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../core/services/ourhome/itunes_artwork.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../../../shared/widgets/ios_checkbox.dart';
import 'room_state_hint.dart';

/// The Lounge (起居室) — film · music · play. The watch/play list with real
/// posters, and the turntable with real album covers (artwork via iTunes).
/// Talks to `/api/home/foyer` and `/api/home/songs`.
class LoungePage extends StatefulWidget {
  const LoungePage({super.key});

  @override
  State<LoungePage> createState() => _LoungePageState();
}

class _LoungePageState extends State<LoungePage> {
  OurHomeGateway? _gateway;
  List<OurHomeFoyerItem> _items = const [];
  List<OurHomeSong> _songs = const [];
  bool _loading = true;
  bool _error = false;
  int _tab = 0; // 0 = screen (foyer), 1 = songs

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
    final ci = gateway.peekList('/api/home/foyer', OurHomeFoyerItem.fromJson);
    final cs2 = gateway.peekList('/api/home/songs', OurHomeSong.fromJson);
    if ((ci.isNotEmpty || cs2.isNotEmpty) && mounted) {
      setState(() {
        _items = ci;
        _songs = cs2;
        _loading = false;
      });
    }
    try {
      final results = await Future.wait([
        gateway.fetchFoyer(),
        gateway.fetchSongs(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<OurHomeFoyerItem>;
        _songs = results[1] as List<OurHomeSong>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Lounge] load failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _toggle(OurHomeFoyerItem it) async {
    final gateway = _gateway;
    if (gateway == null) return;
    Haptics.soft();
    setState(() {
      _items = _items
          .map(
            (x) => x.id == it.id
                ? OurHomeFoyerItem(
                    id: x.id,
                    kind: x.kind,
                    status: x.done ? 'want' : 'done',
                    title: x.title,
                    note: x.note,
                  )
                : x,
          )
          .toList();
    });
    try {
      await gateway.setFoyerStatus(it.id, it.done ? 'want' : 'done');
    } catch (e) {
      debugPrint('[Lounge] setFoyerStatus failed: $e');
      await _load();
    }
  }

  Future<void> _delete(OurHomeFoyerItem it) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    Haptics.light();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: IosCardPress(
          borderRadius: BorderRadius.circular(12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          onTap: () => Navigator.of(ctx).pop(true),
          child: Row(
            children: [
              const Icon(Lucide.Trash, size: 20, color: Colors.red),
              const SizedBox(width: 16),
              Text(
                zh ? '删掉这条' : 'Delete',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await gateway.deleteFoyer(it.id);
      await _load();
    } catch (e) {
      debugPrint('[Lounge] deleteFoyer failed: $e');
    }
  }

  Future<void> _add() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final result = await showModalBottomSheet<_NewItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddSheet(zh: zh),
    );
    if (result == null) return;
    try {
      await gateway.addFoyer(result.kind, result.title, result.note);
      await _load();
    } catch (e) {
      debugPrint('[Lounge] addFoyer failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Scaffold(
      backgroundColor: cs.surface,
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
          zh ? '起居室' : 'The Lounge',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_gateway != null && _tab == 0)
            IosIconButton(
              icon: Lucide.Plus,
              size: 22,
              minSize: 44,
              onTap: _add,
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          _tabs(zh, cs),
          Expanded(child: _buildBody(context, zh, cs)),
        ],
      ),
    );
  }

  Widget _tabs(bool zh, ColorScheme cs) {
    Widget t(int i, String label) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_tab != i) {
              Haptics.soft();
              setState(() => _tab = i);
            }
          },
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? cs.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: AppFontWeights.semibold,
                  color: on
                      ? cs.onSurface
                      : cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [t(0, zh ? '影视' : 'Screen'), t(1, zh ? '歌单' : 'Songs')],
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Clapperboard,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n起居室才连得上。'
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
    return _tab == 0 ? _screenView(zh, cs) : _songsView(zh, cs);
  }

  Widget _screenView(bool zh, ColorScheme cs) {
    if (_items.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Clapperboard,
        text: zh ? '想看想玩的，加在这儿。' : 'Nothing on the list yet.',
      );
    }
    final want = _items.where((x) => !x.done).toList();
    final done = _items.where((x) => x.done).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (want.isNotEmpty) ...[
            _label(zh ? '想看 · 想玩' : 'Want', cs),
            for (final it in want) _row(it, cs),
          ],
          if (done.isNotEmpty) ...[
            _label(zh ? '看过 · 玩过' : 'Done', cs),
            for (final it in done) _row(it, cs),
          ],
        ],
      ),
    );
  }

  Widget _songsView(bool zh, ColorScheme cs) {
    if (_songs.isEmpty) {
      return RoomStateHint(
        icon: Lucide.AudioWaveform,
        text: zh ? '唱机上还没有歌。' : 'Nothing on the turntable yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _songs.length,
        itemBuilder: (context, i) => _songRow(_songs[i], cs),
      ),
    );
  }

  Widget _label(String t, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 13,
        fontWeight: AppFontWeights.semibold,
        color: cs.onSurface.withValues(alpha: 0.55),
      ),
    ),
  );

  Widget _row(OurHomeFoyerItem it, ColorScheme cs) {
    final muted = cs.onSurface.withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        baseColor: cs.onSurface.withValues(alpha: 0.04),
        padding: const EdgeInsets.all(10),
        onTap: () => _toggle(it),
        onLongPress: () => _delete(it),
        child: Row(
          children: [
            _Artwork(
              term: it.title,
              media: _mediaFor(it.kind),
              fallbackIcon: _kindIcon(it.kind),
              width: 42,
              height: 56,
              radius: 8,
            ),
            const SizedBox(width: 12),
            IosCheckbox(
              value: it.done,
              onChanged: (_) => _toggle(it),
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    it.title,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.35,
                      color: it.done ? muted : cs.onSurface,
                      decoration: it.done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: muted,
                    ),
                  ),
                  if (it.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        it.note,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _songRow(OurHomeSong s, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          _Artwork(
            term: '${s.title} ${s.artist}',
            media: 'music',
            fallbackIcon: Lucide.AudioWaveform,
            width: 50,
            height: 50,
            radius: 25, // circular vinyl
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: AppFontWeights.medium,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    if (s.zh.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          s.zh,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  s.note.isNotEmpty ? '${s.artist} · "${s.note}"' : s.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _mediaFor(String kind) {
    switch (kind) {
      case 'show':
        return 'tvShow';
      case 'game':
        return 'all';
      default:
        return 'movie';
    }
  }

  static IconData _kindIcon(String kind) {
    switch (kind) {
      case 'game':
        return Lucide.Gamepad2;
      case 'show':
        return Lucide.Tv;
      default:
        return Lucide.Clapperboard;
    }
  }
}

/// Artwork thumbnail resolved from iTunes (cached). Shows a tinted fallback
/// with [fallbackIcon] while loading or when no artwork exists.
class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.term,
    required this.media,
    required this.fallbackIcon,
    required this.width,
    required this.height,
    required this.radius,
  });

  final String term;
  final String media;
  final IconData fallbackIcon;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        fallbackIcon,
        size: 18,
        color: cs.primary.withValues(alpha: 0.7),
      ),
    );

    return FutureBuilder<String?>(
      future: ItunesArtwork.lookup(term, media: media),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) return placeholder();
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.network(
            url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder(),
            errorBuilder: (context, _, __) => placeholder(),
          ),
        );
      },
    );
  }
}

class _NewItem {
  const _NewItem(this.kind, this.title, this.note);
  final String kind;
  final String title;
  final String note;
}

class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.zh});
  final bool zh;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'film';

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    final kinds = [
      ['film', Lucide.Clapperboard, zh ? '电影' : 'Film'],
      ['show', Lucide.Tv, zh ? '剧集' : 'Show'],
      ['game', Lucide.Gamepad2, zh ? '游戏' : 'Game'],
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final k in kinds)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _kind = k[0] as String),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _kind == k[0]
                            ? cs.primary.withValues(alpha: 0.12)
                            : cs.onSurface.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: _kind == k[0]
                            ? Border.all(
                                color: cs.primary.withValues(alpha: 0.3),
                              )
                            : null,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            k[1] as IconData,
                            size: 20,
                            color: _kind == k[0]
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            k[2] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: _kind == k[0]
                                  ? cs.primary
                                  : cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            autofocus: true,
            style: const TextStyle(fontSize: 15.5),
            decoration: InputDecoration(
              hintText: zh ? '名字…' : 'title…',
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: zh ? '想说的（可空）…' : 'a note (optional)…',
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: IosCardPress(
              baseColor: cs.primary,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 14),
              onTap: () {
                final t = _title.text.trim();
                if (t.isEmpty) return;
                Navigator.of(
                  context,
                ).pop(_NewItem(_kind, t, _note.text.trim()));
              },
              child: Center(
                child: Text(
                  zh ? '加进来' : 'Add',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onPrimary,
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
