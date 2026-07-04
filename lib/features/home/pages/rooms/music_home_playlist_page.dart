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

/// One playable entry drawn from our home (老家网关): a title + artist, and a
/// NetEase id when we have one. Playback is resolved against eryu — a `nid`
/// plays directly; without one we search eryu by "title artist".
class _HomeRow {
  const _HomeRow(this.title, this.artist, this.nid);
  final String title;
  final String artist;
  final String nid;
}

/// Detail list for a home music source: `songs` = 我们家的歌单 (turntable wall),
/// `lyrics` = 词廊 (lyric corridor). Fetched from the home gateway, played via eryu.
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
  List<EryuSong> _nidQueue = const []; // songs with a nid, for continuous play
  String? _resolvingTitle; // title currently being searched on eryu

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });

    List<_HomeRow> rows;
    if (widget.source == 'lyrics') {
      final list = await softFetch(gw.fetchLyrics(), 'corridor');
      rows = (list ?? const [])
          .map((l) => _HomeRow(l.title, l.artist, ''))
          .where((r) => r.title.isNotEmpty)
          .toList();
    } else {
      final list = await softFetch(gw.fetchSongs(), 'home songs');
      rows = (list ?? const [])
          .map((s) => _HomeRow(s.title, s.artist, s.neteaseId))
          .where((r) => r.title.isNotEmpty)
          .toList();
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _nidQueue = [
        for (final r in rows)
          if (r.nid.isNotEmpty) EryuSong(songId: r.nid, name: r.title, artist: r.artist, cover: ''),
      ];
      _loading = false;
      _error = rows.isEmpty ? '这里还没有歌。' : null;
    });
  }

  Future<void> _play(_HomeRow row) async {
    final client = _eryu;
    if (client == null) {
      _toast('先在音乐房里连一次 eryu（输一次口令）。');
      return;
    }
    Haptics.soft();
    EryuSong? song;
    if (row.nid.isNotEmpty) {
      song = EryuSong(songId: row.nid, name: row.title, artist: row.artist, cover: '');
    } else {
      setState(() => _resolvingTitle = row.title);
      final query = '${row.title} ${row.artist}'.trim();
      final hits = await eryuSoft(client.search(query), 'resolve home song');
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
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
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
          final resolving = _resolvingTitle == row.title;
          return StillGlass(
            radius: 12,
            blur: false,
            padding: const EdgeInsets.all(10),
            onTap: resolving ? null : () => _play(row),
            child: Row(
              children: [
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
                if (resolving)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(Lucide.Play, size: 16, color: cs.primary.withValues(alpha: 0.8)),
              ],
            ),
          );
        },
      ),
    );
  }
}
