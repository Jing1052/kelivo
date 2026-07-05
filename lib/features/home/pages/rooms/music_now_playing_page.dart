import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/eryu/eryu_client.dart';
import 'package:Kelivo/core/services/eryu/eryu_lyrics.dart';
import 'package:Kelivo/core/services/eryu/eryu_player_controller.dart';
import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import 'music_memory_page.dart';

/// The full-screen player: cover ⇄ scrolling lyrics, transport, a heart, and the
/// listen-together toggle that turns this into a shared room.
class MusicNowPlayingPage extends StatefulWidget {
  const MusicNowPlayingPage({super.key});

  @override
  State<MusicNowPlayingPage> createState() => _MusicNowPlayingPageState();
}

class _MusicNowPlayingPageState extends State<MusicNowPlayingPage> {
  EryuPlayerController? _player;
  bool _showLyrics = false;
  List<EryuLyricLine> _lyrics = const [];
  String _lyricSongId = '';
  int _activeLine = -1;
  final ItemScrollController _itemScroll = ItemScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<EryuPlayerController>();
      _player = p;
      p.onRoomActivity = _showActivity;
      p.addListener(_onPlayer);
      _maybeLoadLyrics();
    });
  }

  @override
  void dispose() {
    final p = _player;
    if (p != null) {
      p.removeListener(_onPlayer);
      if (p.onRoomActivity == _showActivity) p.onRoomActivity = null;
    }
    super.dispose();
  }

  void _onPlayer() {
    if (!mounted) return;
    _maybeLoadLyrics();
    _maybeAutoScroll();
  }

  void _maybeLoadLyrics() {
    final id = _player?.current?.songId ?? '';
    if (id == _lyricSongId) return;
    _lyricSongId = id;
    setState(() {
      _lyrics = const [];
      _activeLine = -1;
    });
    if (id.isEmpty) return;
    final client = EryuClient.fromContext(context);
    if (client == null) return;
    eryuSoft(client.lyric(id), 'lyric').then((d) {
      if (!mounted || _lyricSongId != id) return;
      setState(() {
        _lyrics = EryuLyrics.parse((d?['lrc'] ?? '').toString(), (d?['tlyric'] ?? '').toString());
      });
    });
  }

  void _maybeAutoScroll() {
    if (!_showLyrics || _lyrics.isEmpty) return;
    final idx = EryuLyrics.activeIndex(_lyrics, _player?.position ?? Duration.zero);
    if (idx == _activeLine) return;
    _activeLine = idx;
    if (idx >= 0 && _itemScroll.isAttached) {
      _itemScroll.scrollTo(index: idx, alignment: 0.42, duration: const Duration(milliseconds: 300));
    }
  }

  void _showActivity(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _toggleTogether() {
    final p = _player;
    if (p == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    Haptics.soft();
    if (p.togetherOn) {
      p.leaveTogether();
      _showActivity(zh ? '离开了一起听' : 'Left listen-together');
    } else {
      p.enterTogether(context.read<SettingsProvider>().eryuUser);
      _showActivity(zh
          ? (p.hasPartner ? '进来一起听了' : '房间开着了 · 等 TA 进来一起听')
          : (p.hasPartner ? 'Listening together' : 'Room open — waiting for someone'));
    }
  }

  void _tapLine(int i) {
    final p = _player;
    if (p == null || i < 0 || i >= _lyrics.length) return;
    p.seek(_lyrics[i].time);
  }

  void _favLine(int i) {
    final p = _player;
    final song = p?.current;
    if (p == null || song == null || i < 0 || i >= _lyrics.length) return;
    final line = _lyrics[i].text;
    Haptics.light();
    p.publishQuote(line);
    final client = EryuClient.fromContext(context);
    if (client != null) unawaited(eryuSoft(client.favLine(song.songId, line), 'fav line'));
    _showActivity(Localizations.localeOf(context).languageCode == 'zh' ? '记下了这一句' : 'Saved this line');
  }

  void _openMemory() {
    final song = _player?.current;
    if (song == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MusicMemoryPage(songId: song.songId, songName: song.name)),
    );
  }

  void _saveToHome() {
    final song = _player?.current;
    if (song == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final gw = OurHomeGateway.fromContext(context);
    if (gw == null) {
      _showActivity(zh ? '家里的连接还没配好' : 'Home not connected');
      return;
    }
    Haptics.light();
    unawaited(softFetch(gw.addSong(song.name, song.artist, '', ''), 'add home song'));
    _showActivity(zh ? '已加进我们家的歌单' : 'Saved to our playlist');
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
              icon: Lucide.ChevronDown,
              size: 24,
              minSize: 44,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              zh ? '正在播放' : 'Now Playing',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            actions: [
              Consumer<EryuPlayerController>(
                builder: (context, player, _) => IosIconButton(
                  minSize: 44,
                  onTap: _toggleTogether,
                  builder: (color) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Lucide.Users, size: 20, color: player.togetherOn ? cs.primary : color),
                      if (player.hasPartner)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF34C759)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IosIconButton(
                icon: Lucide.ListMusic,
                size: 20,
                minSize: 44,
                color: _showLyrics ? cs.primary : null,
                onTap: () => setState(() {
                  _showLyrics = !_showLyrics;
                  _activeLine = -1;
                  if (_showLyrics) _maybeAutoScroll();
                }),
              ),
              IosIconButton(icon: Lucide.Bookmark, size: 20, minSize: 44, onTap: _saveToHome),
              IosIconButton(icon: Lucide.Heart, size: 20, minSize: 44, onTap: _openMemory),
            ],
          ),
          body: Consumer<EryuPlayerController>(
            builder: (context, player, _) {
              final song = player.current;
              if (song == null) {
                return Center(
                  child: Text(
                    zh ? '还没有在放的歌' : 'Nothing playing yet',
                    style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.4)),
                  ),
                );
              }
              return SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: _showLyrics ? _buildLyrics(cs, zh) : _buildCoverArea(cs, zh, song, player),
                      ),
                    ),
                    _JoinBar(zh: zh),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                      child: Column(
                        children: [
                          _SeekBar(
                            position: player.position,
                            duration: player.duration,
                            accent: cs.primary,
                            onSeek: player.seek,
                          ),
                          const SizedBox(height: 18),
                          _Controls(player: player, accent: cs.primary, onColor: cs.onPrimary, ink: cs.onSurface),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCoverArea(ColorScheme cs, bool zh, EryuSong song, EryuPlayerController player) {
    return Column(
      children: [
        const Spacer(flex: 2),
        _Cover(cover: song.cover, accent: cs.primary),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name.isEmpty ? (zh ? '未知歌曲' : 'Unknown') : song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                  if (player.togetherOn && player.controlledBy.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${player.controlledBy} ${zh ? '在放' : 'is playing'}',
                      style: TextStyle(fontSize: 11, color: cs.primary.withValues(alpha: 0.85)),
                    ),
                  ],
                ],
              ),
            ),
            IosIconButton(
              icon: Lucide.Heart,
              size: 24,
              color: cs.primary,
              onTap: () {
                Haptics.light();
                player.publishHeart();
                _showActivity(zh ? '给你送了一颗心' : 'Sent you a heart');
              },
            ),
          ],
        ),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _buildLyrics(ColorScheme cs, bool zh) {
    if (_lyrics.isEmpty) {
      return Center(
        child: Text(zh ? '这首歌没有歌词' : 'No lyrics', style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.4))),
      );
    }
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScroll,
      itemCount: _lyrics.length,
      padding: const EdgeInsets.symmetric(vertical: 40),
      itemBuilder: (context, i) {
        final line = _lyrics[i];
        final active = i == _activeLine;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tapLine(i),
          onLongPress: () => _favLine(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  line.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: active ? 17 : 15,
                    height: 1.3,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? cs.onSurface : cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                if (line.trans.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    line.trans,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: active ? 13 : 12,
                      color: active ? cs.onSurface.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bottom confirm bar shown when you enter a room where someone's already
/// playing — join their song, or keep your own.
class _JoinBar extends StatelessWidget {
  const _JoinBar({required this.zh});
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<EryuPlayerController>(
      builder: (context, player, _) {
        final join = player.joinCandidate;
        if (join == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  zh ? '加入 TA 正在听的《${join.song.name}》？' : 'Join what TA is playing — ${join.song.name}?',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.85)),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: player.dismissJoin,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(zh ? '不用' : 'No',
                      style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.5))),
                ),
              ),
              IosCardPress(
                onTap: player.acceptJoin,
                borderRadius: BorderRadius.circular(10),
                baseColor: cs.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(zh ? '加入' : 'Join', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onPrimary)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.cover, required this.accent});

  final String cover;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12)),
            ],
          ),
          child: cover.isEmpty
              ? Icon(Lucide.Music, size: 64, color: accent.withValues(alpha: 0.5))
              : Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Lucide.Music, size: 64, color: accent.withValues(alpha: 0.5)),
                ),
        ),
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.accent,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final Color accent;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragFraction;

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString();
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalMs = widget.duration.inMilliseconds;
    final playedFraction =
        totalMs > 0 ? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble() : 0.0;
    final fraction = _dragFraction ?? playedFraction;
    final shownPos = totalMs > 0 ? Duration(milliseconds: (fraction * totalMs).round()) : widget.position;

    void setFraction(double localX, double width) {
      final f = width > 0 ? (localX / width).clamp(0.0, 1.0).toDouble() : 0.0;
      setState(() => _dragFraction = f);
    }

    void commit() {
      if (_dragFraction != null && totalMs > 0) {
        widget.onSeek(Duration(milliseconds: (_dragFraction! * totalMs).round()));
      }
      setState(() => _dragFraction = null);
    }

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => setFraction(d.localPosition.dx, width),
              onTapUp: (_) => commit(),
              onHorizontalDragUpdate: (d) => setFraction(d.localPosition.dx, width),
              onHorizontalDragEnd: (_) => commit(),
              child: SizedBox(
                height: 20,
                width: width,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 8.5,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 8.5,
                      child: Container(
                        width: width * fraction,
                        height: 3,
                        decoration: BoxDecoration(
                          color: widget.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (width * fraction - 6).clamp(0.0, width > 12 ? width - 12 : 0.0).toDouble(),
                      top: 4,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.accent,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(shownPos), style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45))),
            Text(_fmt(widget.duration), style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45))),
          ],
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player, required this.accent, required this.onColor, required this.ink});

  final EryuPlayerController player;
  final Color accent;
  final Color onColor;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IosIconButton(
          icon: Lucide.Shuffle,
          size: 20,
          color: player.roam ? accent : ink.withValues(alpha: 0.5),
          onTap: () => player.setRoam(!player.roam),
        ),
        IosIconButton(icon: Lucide.SkipBack, size: 26, onTap: player.prev),
        IosCardPress(
          onTap: player.toggle,
          borderRadius: BorderRadius.circular(36),
          baseColor: accent,
          padding: const EdgeInsets.all(18),
          pressedScale: 0.94,
          child: Icon(player.playing ? Lucide.Pause : Lucide.Play, size: 28, color: onColor),
        ),
        IosIconButton(icon: Lucide.SkipForward, size: 26, onTap: player.next),
        IosIconButton(icon: Lucide.Repeat, size: 20, color: ink.withValues(alpha: 0.5), onTap: player.next),
      ],
    );
  }
}
