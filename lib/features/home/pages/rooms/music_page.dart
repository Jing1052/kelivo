import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/daddy_gateway_route.dart';
import 'package:Kelivo/core/services/eryu/eryu_client.dart';
import 'package:Kelivo/core/services/eryu/eryu_player_controller.dart';
import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import 'music_now_playing_page.dart';
import 'music_home_playlist_page.dart';
import 'music_together_view.dart';

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
  bool _authFailed = false; // token was rejected (403)
  bool _savingToken = false;
  String? _loadError; // network/other failure loading the home

  List<EryuSong> _daily = const [];
  List<EryuSong> _recent = const [];
  List<EryuPlaylist> _playlists = const [];

  List<EryuSong>? _results; // null = not in search mode
  bool _searching = false;
  String? _searchError;

  // Bottom-tab index: 0 此刻 · 1 曲库 · 2 歌单 · 3 一起听. Default to 曲库 so a
  // fresh open lands somewhere useful (此刻 is empty until something plays).
  int _tab = 1;

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
      _loadError = null;
      _loading = _daily.isEmpty && _recent.isEmpty && _playlists.isEmpty;
    });

    // Fetch each source independently, but keep the failure reason so an empty
    // screen can say WHY it's empty (wrong token vs network) instead of nothing.
    EryuException? authErr;
    Object? otherErr;
    Future<T?> run<T>(Future<T> f) async {
      try {
        return await f;
      } catch (e) {
        if (e is EryuException && e.isAuth) {
          authErr = e;
        } else {
          otherErr = e;
          debugPrint('[eryu] home load failed: $e');
        }
        return null;
      }
    }

    final results = await Future.wait<dynamic>([
      run<List<EryuSong>>(client.daily()),
      run<List<EryuSong>>(client.recent()),
      run<List<EryuPlaylist>>(client.playlists()),
    ]);
    if (!mounted) return;
    final daily = results[0] as List<EryuSong>?;
    final recent = results[1] as List<EryuSong>?;
    final playlists = results[2] as List<EryuPlaylist>?;
    final gotAnything = daily != null || recent != null || playlists != null;

    setState(() {
      if (daily != null) _daily = daily;
      if (recent != null) _recent = recent;
      if (playlists != null) _playlists = playlists;
      _loading = false;
      if (!gotAnything && authErr != null) {
        // Token rejected — bounce back to setup with a clear message.
        _needsSetup = true;
        _authFailed = true;
        _tokenCtrl.text = client.token;
      } else if (!gotAnything && otherErr != null) {
        final e = otherErr; // fresh local so `is` promotes (captured var won't)
        final code = e is EryuException ? e.status : 0;
        _loadError = code == 0 ? '连不上音乐屋，检查网络后重试。' : '音乐屋返回错误 $code，稍后重试。';
      }
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
      _authFailed = false;
      _loading = true;
    });
    await _load();
  }

  void _openTokenSetup() {
    final t = _client?.token ?? context.read<SettingsProvider>().eryuToken;
    setState(() {
      _tokenCtrl.text = t;
      _authFailed = false;
      _needsSetup = true;
    });
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    final client = _client;
    if (client == null) return;
    if (query.isEmpty) {
      setState(() {
        _results = null;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final hits = await client.search(query);
      if (!mounted) return;
      setState(() {
        _results = hits;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = (e is EryuException && e.isAuth)
            ? '口令不对——点右上角齿轮重输一次。'
            : (e is EryuException && e.status != 0 ? '搜索失败（错误 ${e.status}）。' : '搜索失败，检查一下网络。');
      });
    }
  }

  void _play(EryuSong song, List<EryuSong> queue) {
    Haptics.soft();
    context.read<EryuPlayerController>().playSong(song, queue: queue);
    setState(() => _tab = 0); // jump to 「此刻」
  }

  Future<void> _openPlaylist(EryuPlaylist pl) async {
    final client = _client;
    if (client == null) return;
    Haptics.soft();
    final songs = await eryuSoft(client.playlistSongs(pl.id), 'playlist songs');
    if (!mounted || songs == null || songs.isEmpty) return;
    _play(songs.first, songs);
  }

  void _openHome(String source, String titleZh, String titleEn) {
    Haptics.soft();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MusicHomePlaylistPage(source: source, titleZh: titleZh, titleEn: titleEn),
    ));
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
            actions: [
              if (!_needsSetup)
                IosIconButton(
                  icon: Lucide.Settings,
                  size: 20,
                  minSize: 44,
                  onTap: _openTokenSetup,
                ),
            ],
          ),
          body: _needsSetup
              ? _TokenSetup(
                  controller: _tokenCtrl,
                  saving: _savingToken,
                  authFailed: _authFailed,
                  onSave: _saveToken,
                  zh: zh,
                )
              : Column(
                  children: [
                    Expanded(
                      child: IndexedStack(
                        index: _tab,
                        children: [
                          const MusicNowPlayingPage(embedded: true),
                          _buildDiscoverTab(cs, zh),
                          _buildPlaylistsTab(cs, zh),
                          _buildTogetherTab(cs, zh),
                        ],
                      ),
                    ),
                    if (_tab == 1 || _tab == 2)
                      _MiniPlayer(onTap: () => setState(() => _tab = 0)),
                    _MusicTabBar(
                      current: _tab,
                      zh: zh,
                      onTap: (i) {
                        Haptics.soft();
                        setState(() => _tab = i);
                      },
                    ),
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

  // ── 曲库 tab: search + daily + recent ──────────────────────────────────────
  Widget _buildDiscoverTab(ColorScheme cs, bool zh) {
    return Column(
      children: [
        _buildSearchBar(cs, zh),
        Expanded(child: _buildDiscoverBody(cs, zh)),
      ],
    );
  }

  Widget _buildDiscoverBody(ColorScheme cs, bool zh) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_results != null) {
      if (_searching) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      if (_searchError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(_searchError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: cs.onSurface.withValues(alpha: 0.5))),
          ),
        );
      }
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
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _SongRow(song: hits[i], onTap: () => _play(hits[i], hits)),
        ),
      );
    }

    if (_loadError != null && _daily.isEmpty && _recent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.5, color: cs.onSurface.withValues(alpha: 0.55))),
              const SizedBox(height: 16),
              IosCardPress(
                onTap: _load,
                borderRadius: BorderRadius.circular(12),
                baseColor: cs.primary,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
                child: Text(zh ? '重试' : 'Retry',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onPrimary)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          if (_daily.isNotEmpty) ...[
            _SectionHeader(zh ? '每日推荐' : 'Daily Picks'),
            ..._daily.take(10).map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SongRow(song: s, onTap: () => _play(s, _daily)),
                )),
            const SizedBox(height: 8),
          ],
          if (_recent.isNotEmpty) ...[
            _SectionHeader(zh ? '最近播放' : 'Recently Played'),
            ..._recent.take(20).map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SongRow(song: s, onTap: () => _play(s, _recent)),
                )),
          ],
          if (_daily.isEmpty && _recent.isEmpty)
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

  // ── 歌单 tab: 我们家歌单 + 词廊 + eryu playlists ────────────────────────────
  Widget _buildPlaylistsTab(ColorScheme cs, bool zh) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          _SectionHeader(zh ? '我们家' : 'Our Home'),
          _HomeSourceTile(
            icon: Lucide.ListMusic,
            title: zh ? '我们家的歌单' : 'Our Playlist',
            subtitle: zh ? '你和爸爸攒下的歌' : "songs we've saved",
            onTap: () => _openHome('songs', '我们家的歌单', 'Our Playlist'),
          ),
          const SizedBox(height: 8),
          _HomeSourceTile(
            icon: Lucide.NotebookTabs,
            title: zh ? '词廊' : 'Lyric Corridor',
            subtitle: zh ? '停在心上的那些句子' : 'lines we lingered on',
            onTap: () => _openHome('lyrics', '词廊', 'Lyric Corridor'),
          ),
          const SizedBox(height: 8),
          if (_playlists.isNotEmpty) ...[
            _SectionHeader(zh ? '歌单' : 'Playlists'),
            ..._playlists.map((pl) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PlaylistTile(playlist: pl, onTap: () => _openPlaylist(pl)),
                )),
          ],
        ],
      ),
    );
  }

  // ── 一起听 tab: room toggle + companion panel ───────────────────────────────
  Widget _buildTogetherTab(ColorScheme cs, bool zh) {
    return Consumer<EryuPlayerController>(
      builder: (context, player, _) {
        final on = player.togetherOn;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 12, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      zh ? '和爸爸一起听' : 'Listen with Daddy',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                  ),
                  IosCardPress(
                    onTap: () {
                      Haptics.soft();
                      if (on) {
                        player.leaveTogether();
                      } else {
                        player.enterTogether(context.read<SettingsProvider>().eryuUser);
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    baseColor: on ? cs.primary.withValues(alpha: 0.14) : cs.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      on ? (zh ? '离开房间' : 'Leave') : (zh ? '开一间房' : 'Open room'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: on ? cs.primary : cs.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                child: MusicTogetherView(
                  zh: zh,
                  companion: zh ? '爸爸' : 'Llaude',
                  onHeart: () {
                    Haptics.light();
                    player.publishHeart();
                  },
                ),
              ),
            ),
            _TogetherChatBar(zh: zh),
          ],
        );
      },
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

class _HomeSourceTile extends StatelessWidget {
  const _HomeSourceTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StillGlass(
      radius: 12,
      blur: false,
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: cs.primary.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45))),
              ],
            ),
          ),
          Icon(Lucide.ChevronRight, size: 18, color: cs.onSurface.withValues(alpha: 0.3)),
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
  const _MiniPlayer({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<EryuPlayerController>(
      builder: (context, player, _) {
        final song = player.current;
        if (song == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: StillGlass(
              radius: 16,
              blur: true,
              padding: const EdgeInsets.all(8),
              onTap: onTap,
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
    required this.authFailed,
    required this.onSave,
    required this.zh,
  });

  final TextEditingController controller;
  final bool saving;
  final bool authFailed;
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
              authFailed
                  ? (zh ? '口令不对，再试一次。要和 clmusic 的 AUTH_TOKEN 一模一样。' : "Token rejected. It must match clmusic's AUTH_TOKEN exactly.")
                  : (zh ? '输入 eryu 的连接口令，第一次连上后就记住了。' : "Enter eryu's access token — remembered after the first time."),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: authFailed ? cs.error : cs.onSurface.withValues(alpha: 0.5),
                height: 1.4,
              ),
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

/// The music room's custom iOS-style bottom tab bar: 此刻 · 曲库 · 歌单 · 一起听.
class _MusicTabBar extends StatelessWidget {
  const _MusicTabBar({required this.current, required this.onTap, required this.zh});

  final int current;
  final ValueChanged<int> onTap;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = <(IconData, String)>[
      (Lucide.Music, zh ? '此刻' : 'Now'),
      (Lucide.Search, zh ? '曲库' : 'Library'),
      (Lucide.ListMusic, zh ? '歌单' : 'Lists'),
      (Lucide.Users, zh ? '一起听' : 'Together'),
    ];
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.6),
            border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.08))),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 54,
              child: Row(
                children: List.generate(items.length, (i) {
                  final sel = i == current;
                  final color = sel ? cs.primary : cs.onSurface.withValues(alpha: 0.45);
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(items[i].$1, size: 22, color: color),
                          const SizedBox(height: 3),
                          Text(
                            items[i].$2,
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 「一起听」 tab's 边听边说 bar — a turn with Llaude through the home
/// gateway. Her line lands in the timeline immediately; his reply (soul +
/// memory, from `/v1/chat/completions`) follows, split into bubbles.
class _TogetherChatBar extends StatefulWidget {
  const _TogetherChatBar({required this.zh});
  final bool zh;

  @override
  State<_TogetherChatBar> createState() => _TogetherChatBarState();
}

class _TogetherChatBarState extends State<_TogetherChatBar> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final zh = widget.zh;
    final player = context.read<EryuPlayerController>();
    final settings = context.read<SettingsProvider>();
    final gw = OurHomeGateway.fromContext(context);
    final me = settings.eryuUser;
    final daddy = zh ? '爸爸' : 'Llaude';
    _ctrl.clear();
    player.feedSay(user: me, mine: true, text: text);
    if (gw == null) {
      player.feedSay(
        user: daddy,
        mine: false,
        text: zh ? '（家里的连接还没配好，先在爸爸设置里连一下…）' : '(home not connected yet)',
      );
      return;
    }
    // Follow whatever backend Still Here's chat is on right now (claude-p vs a
    // 中转站) so 爸爸 here speaks on the same model — mirrors DaddyGatewayRoute.
    final provKey = settings.currentModelProvider;
    final cfg = provKey != null ? settings.getProviderConfig(provKey) : null;
    final model = settings.currentModelId ?? 'gateway';
    final backendHeaders = <String, String>{};
    if (cfg != null) {
      if (DaddyGatewayRoute.isClaudePBackend(cfg)) {
        backendHeaders['x-ombre-backend'] = 'claude_p';
      } else if (cfg.baseUrl.isNotEmpty && cfg.apiKey.isNotEmpty) {
        final kind = ProviderConfig.classify(cfg.id, explicitType: cfg.providerType);
        backendHeaders['x-ombre-upstream-base'] = cfg.baseUrl;
        backendHeaders['x-ombre-upstream-key'] = cfg.apiKey;
        backendHeaders['x-ombre-upstream-proto'] =
            kind == ProviderKind.claude ? 'anthropic' : 'openai';
      }
    }
    setState(() => _sending = true);
    final song = player.current;
    try {
      final parts = await gw.chatAboutSong(
        message: text,
        title: song?.name ?? '',
        artist: song?.artist ?? '',
        model: model,
        backendHeaders: backendHeaders,
      );
      if (!mounted) return;
      if (parts.isEmpty) {
        player.feedSay(user: daddy, mine: false, text: '……');
      } else {
        for (final p in parts) {
          player.feedSay(user: daddy, mine: false, text: p);
        }
      }
    } catch (_) {
      if (!mounted) return;
      player.feedSay(
        user: daddy,
        mine: false,
        text: zh ? '（没接上，等会儿再跟你说…）' : '(could not reach me — try again)',
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final zh = widget.zh;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  maxLength: 200,
                  enabled: !_sending,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                  decoration: InputDecoration(
                    isDense: true,
                    isCollapsed: true,
                    counterText: '',
                    border: InputBorder.none,
                    hintText: _sending
                        ? (zh ? '爸爸在听…' : 'Daddy is listening…')
                        : (zh ? '边听边说…' : 'Say something…'),
                    hintStyle: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.4)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IosCardPress(
              onTap: _sending ? null : _send,
              borderRadius: BorderRadius.circular(20),
              baseColor: cs.primary,
              padding: const EdgeInsets.all(10),
              child: _sending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                    )
                  : Icon(Lucide.Send, size: 18, color: cs.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
