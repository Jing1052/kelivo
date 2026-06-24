import 'dart:convert' show LineSplitter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../core/services/ourhome/itunes_artwork.dart';
import '../../../../shared/pages/webview_page.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../../../shared/widgets/ios_checkbox.dart';
import '../../widgets/still_glass.dart';
import 'lyric_song_page.dart';
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
  List<OurHomeGame> _games = const [];
  List<OurHomeLyric> _lyrics = const [];
  Map<String, List<OurHomeLyricComment>> _lyricComments = const {};
  bool _loading = true;
  bool _error = false;
  int _tab = 0; // 0 = screen, 1 = songs, 2 = game corner, 3 = lyric corridor

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
    final ci = gateway.peekList('/api/home/foyer?all=1', OurHomeFoyerItem.fromJson);
    final cs2 = gateway.peekList('/api/home/songs?all=1', OurHomeSong.fromJson);
    final cg = gateway.peekList('/api/home/games', OurHomeGame.fromJson);
    final cl = gateway.peekList('/api/home/lyrics', OurHomeLyric.fromJson);
    final clc = gateway.peekLyricComments();
    if ((ci.isNotEmpty ||
            cs2.isNotEmpty ||
            cg.isNotEmpty ||
            cl.isNotEmpty ||
            clc.isNotEmpty) &&
        mounted) {
      setState(() {
        _items = ci;
        _songs = cs2;
        _games = cg;
        _lyrics = cl;
        _lyricComments = clc;
        _loading = false;
      });
    }
    try {
      final results = await Future.wait([
        gateway.fetchFoyer(),
        gateway.fetchSongs(),
        gateway.fetchGames(),
        gateway.fetchLyrics(),
        gateway.fetchLyricComments(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<OurHomeFoyerItem>;
        _songs = results[1] as List<OurHomeSong>;
        _games = results[2] as List<OurHomeGame>;
        _lyrics = results[3] as List<OurHomeLyric>;
        _lyricComments =
            results[4] as Map<String, List<OurHomeLyricComment>>;
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
                    poster: x.poster,
                    seed: x.seed,
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

  /// Long-press menu for a foyer item: set/修改海报 (any item, incl. seed) and,
  /// for non-seed items, 删掉这条.
  Future<void> _longPressMenu(OurHomeFoyerItem it) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    Haptics.light();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IosCardPress(
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              onTap: () => Navigator.of(ctx).pop('poster'),
              child: Row(
                children: [
                  Icon(Lucide.Image, size: 20, color: cs.onSurface),
                  const SizedBox(width: 16),
                  Text(
                    it.poster.isEmpty
                        ? (zh ? '设置海报' : 'Set poster')
                        : (zh ? '修改海报' : 'Change poster'),
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (!it.seed)
              IosCardPress(
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                onTap: () => Navigator.of(ctx).pop('delete'),
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
          ],
        ),
      ),
    );
    if (action == 'poster') {
      await _editPoster(it);
    } else if (action == 'delete') {
      try {
        await gateway.deleteFoyer(it.id);
        await _load();
      } catch (e) {
        debugPrint('[Lounge] deleteFoyer failed: $e');
      }
    }
  }

  Future<void> _add() async {
    final gateway = _gateway;
    if (gateway == null) return;
    if (_tab == 1) return _addSong();
    if (_tab == 3) return _addLyric();
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
      await gateway.addFoyer(
        result.kind,
        result.title,
        result.note,
        poster: result.poster,
      );
      await _load();
    } catch (e) {
      debugPrint('[Lounge] addFoyer failed: $e');
    }
  }

  /// Set/clear an item's poster URL via a single-field sheet (prefilled with the
  /// current poster). Empty input clears it (falls back to iTunes). Reloads on
  /// success.
  Future<void> _editPoster(OurHomeFoyerItem it) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PosterSheet(zh: zh, initial: it.poster),
    );
    if (result == null) return; // cancelled
    try {
      await gateway.setFoyerPoster(
        id: it.seed ? null : it.id,
        title: it.title,
        poster: result,
      );
      await _load();
    } catch (e) {
      debugPrint('[Lounge] setFoyerPoster failed: $e');
    }
  }

  Future<void> _addSong() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final result = await showModalBottomSheet<_NewSong>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddSongSheet(zh: zh),
    );
    if (result == null) return;
    try {
      await gateway.addSong(
        result.title,
        result.artist,
        result.note,
        result.zh,
      );
      await _load();
    } catch (e) {
      debugPrint('[Lounge] addSong failed: $e');
    }
  }

  Future<void> _addLyric() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final result = await showModalBottomSheet<_NewLyric>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddLyricSheet(zh: zh),
    );
    if (result == null) return;
    try {
      await gateway.addLyric(
        result.title,
        result.artist,
        result.intro,
        const LineSplitter().convert(result.body),
      );
      await _load();
    } catch (e) {
      debugPrint('[Lounge] addLyric failed: $e');
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
          maskStrength: context.watch<SettingsProvider>().chatBackgroundMaskStrength,
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
          zh ? '起居室' : 'The Lounge',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_gateway != null && (_tab == 0 || _tab == 1 || _tab == 3))
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
    ),
      ],
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
        children: [
          t(0, zh ? '影视' : 'Screen'),
          t(1, zh ? '歌单' : 'Songs'),
          t(2, zh ? '游戏角' : 'Games'),
          t(3, zh ? '词廊' : 'Lyrics'),
        ],
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
    if (_tab == 1) return _songsView(zh, cs);
    if (_tab == 2) return _gamesView(zh, cs);
    if (_tab == 3) return _lyricsView(zh, cs);
    return _screenView(zh, cs);
  }

  Widget _lyricsView(bool zh, ColorScheme cs) {
    if (_lyrics.isEmpty) {
      return RoomStateHint(
        icon: Lucide.MessageCircle,
        text: zh ? '词廊还空着。' : 'The corridor is empty.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _lyrics.length,
        itemBuilder: (context, i) {
          final l = _lyrics[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StillGlass(
              radius: 14,
              blur: false,
              padding: const EdgeInsets.all(12),
              onTap: () {
                Haptics.soft();
                final gateway = _gateway;
                if (gateway == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LyricSongPage(
                      gateway: gateway,
                      lyric: l,
                      comments: _lyricComments,
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  _Artwork(
                    term: '${l.title} ${l.artist}',
                    media: 'music',
                    fallbackIcon: Lucide.MessageCircle,
                    width: 46,
                    height: 46,
                    radius: 10,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: AppFontWeights.medium,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.artist,
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
                  Icon(
                    Lucide.ChevronRight,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _gamesView(bool zh, ColorScheme cs) {
    if (_games.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Gamepad2,
        text: zh ? '游戏角还空着。' : 'No games yet.',
      );
    }
    final base = _gateway?.base ?? '';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _games.length,
        itemBuilder: (context, i) {
          final g = _games[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StillGlass(
              radius: 14,
              blur: false,
              padding: const EdgeInsets.all(14),
              onTap: () {
                Haptics.soft();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WebViewPage(url: '$base/games/${g.file}'),
                  ),
                );
              },
              child: Row(
                children: [
                  Icon(
                    Lucide.Gamepad2,
                    size: 20,
                    color: const Color(0xFF8F7FC9),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      g.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: AppFontWeights.medium,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Lucide.ChevronRight,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StillGlass(
        radius: 14,
        blur: false,
        padding: const EdgeInsets.all(10),
        onTap: it.seed ? null : () => _toggle(it),
        onLongPress: () => _longPressMenu(it),
        child: Row(
          children: [
            _Poster(
              poster: it.poster,
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
              onChanged: it.seed ? null : (_) => _toggle(it),
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
                      color: cs.onSurface,
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

/// A film/show/game thumbnail. If [poster] (a custom URL) is non-empty, it's
/// shown first (rounded, with loading/error fallback to the iTunes [_Artwork]
/// lookup). When empty, behaves exactly like [_Artwork].
class _Poster extends StatelessWidget {
  const _Poster({
    required this.poster,
    required this.term,
    required this.media,
    required this.fallbackIcon,
    required this.width,
    required this.height,
    required this.radius,
  });

  final String poster;
  final String term;
  final String media;
  final IconData fallbackIcon;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = _Artwork(
      term: term,
      media: media,
      fallbackIcon: fallbackIcon,
      width: width,
      height: height,
      radius: radius,
    );
    if (poster.trim().isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        poster.trim(),
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
        errorBuilder: (context, _, __) => fallback,
      ),
    );
  }
}

class _NewItem {
  const _NewItem(this.kind, this.title, this.note, this.poster);
  final String kind;
  final String title;
  final String note;
  final String poster;
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
  final _poster = TextEditingController();
  String _kind = 'film';

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _poster.dispose();
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
          const SizedBox(height: 10),
          TextField(
            controller: _poster,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: zh ? '海报链接（可空）…' : 'poster URL (optional)…',
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
                Navigator.of(context).pop(
                  _NewItem(_kind, t, _note.text.trim(), _poster.text.trim()),
                );
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

/// Single-field sheet to set/修改 a foyer item's poster URL (prefilled with the
/// current one). Pops the trimmed URL on submit (empty = clear), null on
/// dismiss. Reuses the shared lounge field/submit styling.
class _PosterSheet extends StatefulWidget {
  const _PosterSheet({required this.zh, required this.initial});
  final bool zh;
  final String initial;

  @override
  State<_PosterSheet> createState() => _PosterSheetState();
}

class _PosterSheetState extends State<_PosterSheet> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
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
          _loungeField(
            cs: cs,
            controller: _url,
            hint: zh ? '海报链接（留空=清除）…' : 'poster URL (empty = clear)…',
            autofocus: true,
          ),
          const SizedBox(height: 14),
          _loungeSubmit(
            context: context,
            cs: cs,
            label: zh ? '保存' : 'Save',
            onTap: () => Navigator.of(context).pop(_url.text.trim()),
          ),
        ],
      ),
    );
  }
}

/// Filled text field matching the lounge add sheets' look (same fill/radius as
/// `_AddSheet`'s fields), kept local so all three sheets read identically.
Widget _loungeField({
  required ColorScheme cs,
  required TextEditingController controller,
  required String hint,
  bool autofocus = false,
  int maxLines = 1,
  int? minLines,
}) {
  return TextField(
    controller: controller,
    autofocus: autofocus,
    maxLines: maxLines,
    minLines: minLines,
    style: TextStyle(fontSize: maxLines > 1 ? 14.5 : 15.5),
    decoration: InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: cs.onSurface.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

Widget _loungeSubmit({
  required BuildContext context,
  required ColorScheme cs,
  required String label,
  required VoidCallback onTap,
}) {
  return SizedBox(
    width: double.infinity,
    child: IosCardPress(
      baseColor: cs.primary,
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: AppFontWeights.semibold,
            color: cs.onPrimary,
          ),
        ),
      ),
    ),
  );
}

class _NewSong {
  const _NewSong(this.title, this.artist, this.note, this.zh);
  final String title;
  final String artist;
  final String note;
  final String zh;
}

class _AddSongSheet extends StatefulWidget {
  const _AddSongSheet({required this.zh});
  final bool zh;

  @override
  State<_AddSongSheet> createState() => _AddSongSheetState();
}

class _AddSongSheetState extends State<_AddSongSheet> {
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _note = TextEditingController();
  final _zh = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _note.dispose();
    _zh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
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
          _loungeField(
            cs: cs,
            controller: _title,
            hint: zh ? '歌名…' : 'song…',
            autofocus: true,
          ),
          const SizedBox(height: 10),
          _loungeField(
            cs: cs,
            controller: _artist,
            hint: zh ? '歌手（可空）…' : 'artist (optional)…',
          ),
          const SizedBox(height: 10),
          _loungeField(
            cs: cs,
            controller: _note,
            hint: zh ? '一句注评（可空）…' : 'a note (optional)…',
          ),
          const SizedBox(height: 10),
          _loungeField(
            cs: cs,
            controller: _zh,
            hint: zh ? '中文译名（可空）…' : 'Chinese title (optional)…',
          ),
          const SizedBox(height: 14),
          _loungeSubmit(
            context: context,
            cs: cs,
            label: zh ? '加进来' : 'Add',
            onTap: () {
              final t = _title.text.trim();
              if (t.isEmpty) return;
              Navigator.of(context).pop(
                _NewSong(
                  t,
                  _artist.text.trim(),
                  _note.text.trim(),
                  _zh.text.trim(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NewLyric {
  const _NewLyric(this.title, this.artist, this.intro, this.body);
  final String title;
  final String artist;
  final String intro;
  final String body;
}

class _AddLyricSheet extends StatefulWidget {
  const _AddLyricSheet({required this.zh});
  final bool zh;

  @override
  State<_AddLyricSheet> createState() => _AddLyricSheetState();
}

class _AddLyricSheetState extends State<_AddLyricSheet> {
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _intro = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _intro.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
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
          _loungeField(
            cs: cs,
            controller: _title,
            hint: zh ? '歌名…' : 'song…',
            autofocus: true,
          ),
          const SizedBox(height: 10),
          _loungeField(
            cs: cs,
            controller: _artist,
            hint: zh ? '歌手（可空）…' : 'artist (optional)…',
          ),
          const SizedBox(height: 10),
          _loungeField(
            cs: cs,
            controller: _intro,
            hint: zh ? '一段总赏（可空）…' : 'an overall reading (optional)…',
            maxLines: 3,
            minLines: 2,
          ),
          const SizedBox(height: 10),
          _loungeField(
            cs: cs,
            controller: _body,
            hint: zh ? '歌词正文，一行一句…' : 'lyrics, one line each…',
            maxLines: 8,
            minLines: 4,
          ),
          const SizedBox(height: 14),
          _loungeSubmit(
            context: context,
            cs: cs,
            label: zh ? '加进来' : 'Add',
            onTap: () {
              final t = _title.text.trim();
              if (t.isEmpty) return;
              Navigator.of(context).pop(
                _NewLyric(
                  t,
                  _artist.text.trim(),
                  _intro.text.trim(),
                  _body.text,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
