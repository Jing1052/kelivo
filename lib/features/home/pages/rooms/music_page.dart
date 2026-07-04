import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/eryu/eryu_client.dart';
import 'package:Kelivo/core/services/eryu/eryu_player_controller.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import 'music_now_playing_page.dart';

/// 音乐房 · Music Room — home page. Search, daily picks, recent, playlists, and
/// a tap-to-open mini player. Connects directly to eryu (clmusic).
class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _tokenCtrl = TextEditingController();

  EryuClient? _client;
  bool _loading = true;
  bool _needsSetup = false;
  bool _savingToken = false;

  List<EryuSong> _daily = const [];
  List<EryuSong> _recent = const [];
  List<EryuPlaylist> _playlists = const [];

  List<EryuSong>? _results; // null = not in search mode
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final client = EryuClient.fromContext(context);
    if (client == null) {
      setState(() {
        _needsSetup = true;
        _loading = false;
      });
      return;
    }
    _client = client;
    context.read<EryuPlayerController>().bind(client);
    setState(() {
      _needsSetup = false;
      _loading = _daily.isEmpty && _recent.isEmpty && _playlists.isEmpty;
    });

    final results = await Future.wait<dynamic>([
      eryuSoft(client.daily(), 'daily'),
      eryuSoft(client.recent(), 'recent'),
      eryuSoft(client.playlists(), 'playlists'),
    ]);
    if (!mounted) return;
    final daily = results[0] as List<EryuSong>?;
    final recent = results[1] as List<EryuSong>?;
    final playlists = results[2] as List<EryuPlaylist>?;
    setState(() {
      if (daily != null) _daily = daily;
      if (recent != null) _recent = recent;
      if (playlists != null) _playlists = playlists;
      _loading = false;
    });
  }

  Future<void> _saveToken() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) return;
    setState(() => _savingToken = true);
    await context.read<SettingsProvider>().setEryuToken(token);
    if (!mounted) return;
    setState(() {
      _savingToken = false;
      _loading = true;
    });
    await _load();
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    final client = _client;
    if (client == null) return;
    if (query.isEmpty) {
      setState(() => _results = null);
      return;
    }
    setState(() => _searching = true);
    final hits = await eryuSoft(client.search(query), 'search');
    if (!mounted) return;
    setState(() {
      _results = hits ?? const [];
      _searching = false;
    });
  }

  void _play(EryuSong song, List<EryuSong> queue) {
    Haptics.soft();
    context.read<EryuPlayerController>().playSong(song, queue: queue);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MusicNowPlayingPage()));
  }

  Future<void> _openPlaylist(EryuPlaylist pl) async {
    final client = _client;
    if (client == null) return;
    Haptics.soft();
    final songs = await eryuSoft(client.playlistSongs(pl.id), 'playlist songs');
    if (!mounted || songs == null || songs.isEmpty) return;
    _play(songs.first, songs);
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
              zh ? '音乐房' : 'Music Room',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          body: _needsSetup
              ? _TokenSetup(
                  controller: _tokenCtrl,
                  saving: _savingToken,
                  onSave: _saveToken,
                  zh: zh,
                )
              : Column(
                  children: [
                    _buildSearchBar(cs, zh),
                    Expanded(child: _buildContent(cs, zh)),
                    const _MiniPlayer(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ColorScheme cs, bool zh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Lucide.Search, size: 16, color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: _runSearch,
                style: TextStyle(fontSize: 14, color: cs.onSurface),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: InputBorder.none,
                  hintText: zh ? '搜歌、歌手…' : 'Search songs, artists…',
                  hintStyle: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.3)),
                ),
              ),
            ),
            if (_results != null)
              IosIconButton(
                icon: Lucide.X,
                size: 16,
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _results = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, bool zh) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_results != null) {
      if (_searching) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      if (_results!.isEmpty) {
        return Center(
          child: Text(
            zh ? '没找到这首' : 'No results',
            style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.4)),
          ),
        );
      }
      final hits = _results!;
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: hits.length,
        itemBuilder: (_, i) => _SongRow(song: hits[i], onTap: () => _play(hits[i], hits)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          if (_daily.isNotEmpty) ...[
            _SectionHeader(zh ? '每日推荐' : 'Daily Picks'),
            ..._daily.take(10).map((s) => _SongRow(song: s, onTap: () => _play(s, _daily))),
            const SizedBox(height: 8),
          ],
          if (_recent.isNotEmpty) ...[
            _SectionHeader(zh ? '最近播放' : 'Recently Played'),
            ..._recent.take(20).map((s) => _SongRow(song: s, onTap: () => _play(s, _recent))),
            const SizedBox(height: 8),
          ],
          if (_playlists.isNotEmpty) ...[
            _SectionHeader(zh ? '歌单' : 'Playlists'),
            ..._playlists.map((pl) => _PlaylistTile(playlist: pl, onTap: () => _openPlaylist(pl))),
          ],
          if (_daily.isEmpty && _recent.isEmpty && _playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(
                child: Text(
                  zh ? '搜一首歌开始吧' : 'Search a song to begin',
                  style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.4)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 0, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.7)),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.song, required this.onTap});
  final EryuSong song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StillGlass(
      radius: 12,
      blur: false,
      padding: const EdgeInsets.all(8),
      onTap: onTap,
      child: Row(
        children: [
          _Cover(url: song.cover, size: 44, accent: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.name.isEmpty ? '—' : song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45)),
                ),
              ],
            ),
          ),
          Icon(Lucide.Play, size: 16, color: cs.primary.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist, required this.onTap});
  final EryuPlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return StillGlass(
      radius: 12,
      blur: false,
      padding: const EdgeInsets.all(8),
      onTap: onTap,
      child: Row(
        children: [
          _Cover(url: playlist.cover, size: 44, accent: cs.primary, fallbackIcon: Lucide.ListMusic),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name.isEmpty ? '—' : playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  zh ? '${playlist.count} 首' : '${playlist.count} songs',
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45)),
                ),
              ],
            ),
          ),
          Icon(Lucide.Play, size: 16, color: cs.primary.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.size, required this.accent, this.fallbackIcon});
  final String url;
  final double size;
  final Color accent;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
          width: size,
          height: size,
          color: accent.withValues(alpha: 0.12),
          child: Icon(fallbackIcon ?? Lucide.Music, size: size * 0.4, color: accent.withValues(alpha: 0.5)),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url.isEmpty
          ? placeholder()
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder(),
            ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<EryuPlayerController>(
      builder: (context, player, _) {
        final song = player.current;
        if (song == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: StillGlass(
              radius: 16,
              blur: true,
              padding: const EdgeInsets.all(8),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const MusicNowPlayingPage())),
              child: Row(
                children: [
                  _Cover(url: song.cover, size: 40, accent: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.name.isEmpty ? '—' : song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45)),
                        ),
                      ],
                    ),
                  ),
                  IosIconButton(
                    icon: player.playing ? Lucide.Pause : Lucide.Play,
                    size: 22,
                    color: cs.primary,
                    onTap: player.toggle,
                  ),
                  IosIconButton(icon: Lucide.SkipForward, size: 20, onTap: player.next),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TokenSetup extends StatelessWidget {
  const _TokenSetup({
    required this.controller,
    required this.saving,
    required this.onSave,
    required this.zh,
  });

  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSave;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Lucide.Music, size: 44, color: cs.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              zh ? '连接音乐屋' : 'Connect the Music Room',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              zh ? '输入 eryu 的连接口令，第一次连上后就记住了。' : "Enter eryu's access token — remembered after the first time.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.5), height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => onSave(),
              style: TextStyle(fontSize: 14, color: cs.onSurface),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: cs.onSurface.withValues(alpha: 0.06),
                hintText: zh ? '连接口令…' : 'Access token…',
                hintStyle: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.3)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            IosCardPress(
              onTap: saving ? null : onSave,
              borderRadius: BorderRadius.circular(14),
              baseColor: cs.primary,
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 40),
              child: saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                    )
                  : Text(
                      zh ? '连接' : 'Connect',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onPrimary),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
