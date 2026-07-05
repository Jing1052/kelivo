import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/eryu/eryu_client.dart';
import 'package:Kelivo/core/services/eryu/eryu_player_controller.dart';
import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import 'music_now_playing_page.dart';

/// One playable entry from our home: title + artist, a NetEase id when we have
/// one, and a cover when the source carries it (词廊 does; 家歌单 doesn't, so we
/// fetch its cover from eryu by name, lazily).
class _HomeRow {
  const _HomeRow(this.title, this.artist, this.nid, this.cover);
  final String title;
  final String artist;
  final String nid;
  final String cover;
}

/// Detail list for a home music source: `songs` = 我们家的歌单 (turntable wall),
/// `lyrics` = 词廊 (lyric corridor). Metadata from the home gateway (peek-cached
/// for instant open), audio resolved and played via eryu.
class MusicHomePlaylistPage extends StatefulWidget {
  const MusicHomePlaylistPage({super.key, required this.source, required this.titleZh, required this.titleEn});

  final String source; // 'songs' | 'lyrics'
  final String titleZh;
  final String titleEn;

  @override
  State<MusicHomePlaylistPage> createState() => _MusicHomePlaylistPageState();
}

class _MusicHomePlaylistPageState extends State<MusicHomePlaylistPage> {
  EryuClient? _eryu;
  bool _loading = true;
  String? _error;
  List<_HomeRow> _rows = const [];
  List<EryuSong> _nidQueue = const [];
  String? _resolvingTitle;
  final Map<String, String> _coverCache = {}; // title -> cover url (fetched from eryu)
  final Set<String> _coverTried = {};

  bool get _isLyrics => widget.source == 'lyrics';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  List<_HomeRow> _fromSongs(List<OurHomeSong> list) => list
      .map((s) => _HomeRow(s.title, s.artist, s.neteaseId, ''))
      .where((r) => r.title.isNotEmpty)
      .toList();

  List<_HomeRow> _fromLyrics(List<OurHomeLyric> list) => list
      .map((l) => _HomeRow(l.title, l.artist, '', l.cover))
      .where((r) => r.title.isNotEmpty)
      .toList();

  void _apply(List<_HomeRow> rows) {
    _rows = rows;
    _nidQueue = [
      for (final r in rows)
        if (r.nid.isNotEmpty) EryuSong(songId: r.nid, name: r.title, artist: r.artist, cover: r.cover),
    ];
  }

  Future<void> _load() async {
    if (!mounted) return;
    final gw = OurHomeGateway.fromContext(context);
    _eryu = EryuClient.fromContext(context);
    if (gw == null) {
      setState(() {
        _loading = false;
        _error = '家里的连接还没配好。';
      });
      return;
    }

    // Instant seed from the on-device cache — no buffering on repeat opens.
    final seed = _isLyrics
        ? _fromLyrics(gw.peekList('/api/home/lyrics', OurHomeLyric.fromJson))
        : _fromSongs(gw.peekList('/api/home/songs?all=1', OurHomeSong.fromJson));
    setState(() {
      if (seed.isNotEmpty) {
        _apply(seed);
        _loading = false;
      }
      _error = null;
    });

    // Refresh in the background.
    List<_HomeRow>? fresh;
    if (_isLyrics) {
      final list = await softFetch(gw.fetchLyrics(), 'corridor');
      if (list != null) fresh = _fromLyrics(list);
    } else {
      final list = await softFetch(gw.fetchSongs(), 'home songs');
      if (list != null) fresh = _fromSongs(list);
    }
    if (!mounted) return;
    setState(() {
      if (fresh != null) _apply(fresh);
      _loading = false;
      _error = _rows.isEmpty ? (fresh == null && seed.isEmpty ? '没读到，检查网络。' : '这里还没有歌。') : null;
    });
  }

  // Lazily resolve a cover for a home song (which carries no cover) by name.
  void _ensureCover(_HomeRow row) {
    if (row.cover.isNotEmpty || _coverCache.containsKey(row.title) || _coverTried.contains(row.title)) return;
    _coverTried.add(row.title);
    final client = _eryu;
    if (client == null) return;
    eryuSoft(client.search('${row.title} ${row.artist}'.trim()), 'cover').then((hits) {
      if (!mounted) return;
      if (hits != null && hits.isNotEmpty && hits.first.cover.isNotEmpty) {
        setState(() => _coverCache[row.title] = hits.first.cover);
      }
    });
  }

  Future<void> _play(_HomeRow row) async {
    final client = _eryu;
    if (client == null) {
      _toast('先在音乐房里连一次 eryu（输一次口令）。');
      return;
    }
    Haptics.soft();
    final cover = row.cover.isNotEmpty ? row.cover : (_coverCache[row.title] ?? '');
    EryuSong? song;
    if (row.nid.isNotEmpty) {
      song = EryuSong(songId: row.nid, name: row.title, artist: row.artist, cover: cover);
    } else {
      setState(() => _resolvingTitle = row.title);
      final hits = await eryuSoft(client.search('${row.title} ${row.artist}'.trim()), 'resolve home song');
      if (!mounted) return;
      setState(() => _resolvingTitle = null);
      song = (hits != null && hits.isNotEmpty) ? hits.first : null;
    }
    if (!mounted) return;
    if (song == null) {
      _toast('eryu 里没找到《${row.title}》。');
      return;
    }
    final queue = _nidQueue.isNotEmpty ? _nidQueue : <EryuSong>[song];
    context.read<EryuPlayerController>().playSong(song, queue: queue);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MusicNowPlayingPage()));
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final settings = context.watch<SettingsProvider>();

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: cs.surface),
        ChatBackdrop(
          rawPath: settings.homeBackgroundActive,
          maskStrength: settings.chatBackgroundMaskStrength,
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
              zh ? widget.titleZh : widget.titleEn,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          body: _buildBody(cs, zh),
        ),
      ],
    );
  }

  Widget _buildBody(ColorScheme cs, bool zh) {
    if (_loading && _rows.isEmpty) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: cs.onSurface.withValues(alpha: 0.5))),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _rows.length,
        itemBuilder: (_, i) {
          final row = _rows[i];
          final cover = row.cover.isNotEmpty ? row.cover : (_coverCache[row.title] ?? '');
          if (cover.isEmpty) _ensureCover(row);
          final resolving = _resolvingTitle == row.title;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StillGlass(
              radius: 12,
              blur: false,
              padding: const EdgeInsets.all(8),
              onTap: resolving ? null : () => _play(row),
              child: Row(
                children: [
                  _ArtBox(url: cover, size: 48, accent: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: cs.onSurface)),
                        if (row.artist.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(row.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45))),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (resolving)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(Lucide.Play, size: 16, color: cs.primary.withValues(alpha: 0.8)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A square album-art box: the cover if we have one, else a music-note tile so
/// the row still reads "art · then name".
class _ArtBox extends StatelessWidget {
  const _ArtBox({required this.url, required this.size, required this.accent});
  final String url;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
          width: size,
          height: size,
          color: accent.withValues(alpha: 0.12),
          child: Icon(Lucide.Music, size: size * 0.42, color: accent.withValues(alpha: 0.5)),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url.isEmpty
          ? placeholder()
          : Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder()),
    );
  }
}
