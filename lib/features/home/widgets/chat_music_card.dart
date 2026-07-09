import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/services/eryu/eryu_client.dart';
import 'package:Kelivo/core/services/eryu/eryu_lyrics.dart';
import 'package:Kelivo/core/services/eryu/eryu_player_controller.dart';
import 'package:Kelivo/features/home/pages/rooms/music_now_playing_page.dart';
import 'package:Kelivo/shared/widgets/music_seek_bar.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/ios_tactile.dart';

/// The now-playing card that floats above the chat input while a song is
/// loaded — the "顺手一起听" surface from the conversation.
///
/// Collapsed it's a slim pill (cover · title · play/pause) with a hairline
/// progress strip; tap it to unfold the full card: bigger cover, the lyric
/// line we're on, a draggable seek bar, and prev/play/next — so she can ride
/// along without leaving the chat. The corner buttons jump to the full player
/// or fold the card back down. Shows a green dot while a sync room is open.
class ChatMusicCard extends StatefulWidget {
  const ChatMusicCard({super.key, required this.bottomInset});

  final double bottomInset;

  @override
  State<ChatMusicCard> createState() => _ChatMusicCardState();
}

class _ChatMusicCardState extends State<ChatMusicCard> {
  bool _expanded = false;
  List<EryuLyricLine> _lyrics = const [];
  String _lyricSongId = '';

  void _openFull() {
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MusicNowPlayingPage()),
    );
  }

  void _toggleExpanded() {
    Haptics.soft();
    setState(() => _expanded = !_expanded);
  }

  /// Fetch the LRC for the current song once per song, only while expanded
  /// (the collapsed pill never shows lyrics). Safe to call from build: the
  /// sync part only mutates fields for this same frame; setState happens in
  /// the async callback.
  void _maybeLoadLyrics(EryuSong song) {
    if (song.songId == _lyricSongId) return;
    _lyricSongId = song.songId;
    _lyrics = const [];
    if (song.songId.isEmpty) return;
    final client = EryuClient.fromContext(context);
    if (client == null) return;
    final id = song.songId;
    eryuSoft(client.lyric(id), 'card lyric').then((d) {
      if (!mounted || _lyricSongId != id) return;
      setState(() {
        _lyrics = EryuLyrics.parse(
          (d?['lrc'] ?? '').toString(),
          (d?['tlyric'] ?? '').toString(),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<EryuPlayerController>();
    final song = player.current;
    // 没歌就彻底不进树：这里若带着 null song 构建（旧版 `song!`），release 下
    // build 一炸，ErrorWidget 的半透明灰盒会被 StackFit.expand 撑满整个聊天区
    // （2026-07-05 小猫的「灰蒙蒙」）。顺带避免隐藏态 BackdropFilter 仍在底部糊一条。
    if (song == null) return const SizedBox.shrink();
    if (_expanded) _maybeLoadLyrics(song);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: 16, bottom: widget.bottomInset + 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _expanded ? null : _toggleExpanded,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  // The card hangs above the input bar (bottom-anchored), so
                  // grow/shrink from the bottom edge to keep it visually pinned.
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: _expanded
                        ? const EdgeInsets.fromLTRB(12, 10, 10, 10)
                        : const EdgeInsets.fromLTRB(8, 7, 6, 7),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    child: _expanded
                        ? _buildExpanded(song, player, cs, zh)
                        : _buildCollapsed(song, player, cs, zh),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed(EryuSong song, EryuPlayerController player, ColorScheme cs, bool zh) {
    final totalMs = player.duration.inMilliseconds;
    final frac = totalMs > 0
        ? (player.position.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _cover(song, cs, 38),
            const SizedBox(width: 10),
            Expanded(child: _title(song, player, cs, zh)),
            const SizedBox(width: 6),
            _PlayToggle(player: player, accent: cs.primary),
          ],
        ),
        if (totalMs > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 7, 2, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 2.5,
                backgroundColor: cs.onSurface.withValues(alpha: 0.10),
                color: cs.primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExpanded(EryuSong song, EryuPlayerController player, ColorScheme cs, bool zh) {
    final idx = EryuLyrics.activeIndex(_lyrics, player.position);
    final line = (idx >= 0 && idx < _lyrics.length) ? _lyrics[idx] : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            GestureDetector(onTap: _openFull, child: _cover(song, cs, 46)),
            const SizedBox(width: 12),
            Expanded(child: _title(song, player, cs, zh)),
            IosIconButton(
              icon: Lucide.Maximize2,
              size: 17,
              minSize: 36,
              color: cs.onSurface.withValues(alpha: 0.55),
              onTap: _openFull,
            ),
            IosIconButton(
              icon: Lucide.ChevronDown,
              size: 19,
              minSize: 36,
              color: cs.onSurface.withValues(alpha: 0.55),
              onTap: _toggleExpanded,
            ),
          ],
        ),
        if (line != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openFull,
              child: Text(
                line.trans.isNotEmpty ? '${line.text} · ${line.trans}' : line.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.primary.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: MusicSeekBar(
            position: player.position,
            duration: player.duration,
            accent: cs.primary,
            onSeek: player.seek,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IosIconButton(icon: Lucide.SkipBack, size: 22, minSize: 44, onTap: player.prev),
            const SizedBox(width: 18),
            IosCardPress(
              onTap: player.toggle,
              borderRadius: BorderRadius.circular(24),
              baseColor: cs.primary,
              padding: const EdgeInsets.all(12),
              pressedScale: 0.94,
              child: Icon(
                player.playing ? Lucide.Pause : Lucide.Play,
                size: 20,
                color: cs.onPrimary,
              ),
            ),
            const SizedBox(width: 18),
            IosIconButton(icon: Lucide.SkipForward, size: 22, minSize: 44, onTap: player.next),
          ],
        ),
      ],
    );
  }

  Widget _cover(EryuSong song, ColorScheme cs, double size) {
    final cover = song.cover;
    Widget placeholder() => Container(
          width: size,
          height: size,
          color: cs.primary.withValues(alpha: 0.14),
          child: Icon(Lucide.Music, size: size * 0.47, color: cs.primary.withValues(alpha: 0.65)),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: cover.isEmpty
          ? placeholder()
          : Image.network(
              cover,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder(),
            ),
    );
  }

  Widget _title(EryuSong song, EryuPlayerController player, ColorScheme cs, bool zh) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (player.togetherOn) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: player.hasPartner ? const Color(0xFF34C759) : cs.primary.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                song.name.isEmpty ? (zh ? '未知歌曲' : 'Unknown') : song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          player.togetherOn
              ? (player.hasPartner ? (zh ? '正在一起听' : 'Listening together') : (zh ? '房间开着 · 等 TA' : 'Room open'))
              : song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: player.togetherOn ? cs.primary.withValues(alpha: 0.85) : cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _PlayToggle extends StatelessWidget {
  const _PlayToggle({required this.player, required this.accent});

  final EryuPlayerController player;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.soft();
        player.toggle();
      },
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
        child: Icon(
          player.playing ? Lucide.Pause : Lucide.Play,
          size: 18,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}
