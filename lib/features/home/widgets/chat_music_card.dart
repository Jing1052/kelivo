import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/services/eryu/eryu_client.dart';
import 'package:Kelivo/core/services/eryu/eryu_player_controller.dart';
import 'package:Kelivo/features/home/pages/rooms/music_now_playing_page.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../core/services/haptics.dart';

/// A slim now-playing pill that floats above the chat input while a song is
/// loaded — the "顺手一起听" entry from the conversation. Tap the body to open
/// the full player (with 一起听); the inline button toggles play/pause. Shows a
/// green dot while a listen-together room is open.
class ChatMusicCard extends StatelessWidget {
  const ChatMusicCard({super.key, required this.bottomInset});

  final double bottomInset;

  void _open(BuildContext context) {
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MusicNowPlayingPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<EryuPlayerController>();
    final song = player.current;
    // 没歌就彻底不进树：这里若带着 null song 构建（旧版 `song!`），release 下
    // build 一炸，ErrorWidget 的半透明灰盒会被 StackFit.expand 撑满整个聊天区
    // （2026-07-05 小猫的「灰蒙蒙」）。顺带避免隐藏态 BackdropFilter 仍在底部糊一条。
    if (song == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomInset + 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _open(context),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
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
                  child: Row(
                    children: [
                      _cover(song, cs),
                      const SizedBox(width: 10),
                      Expanded(child: _title(song, player, cs, zh)),
                      const SizedBox(width: 6),
                      _PlayToggle(player: player, accent: cs.primary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(EryuSong? song, ColorScheme cs) {
    final cover = song?.cover ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: cover.isEmpty
          ? Container(
              width: 38,
              height: 38,
              color: cs.primary.withValues(alpha: 0.14),
              child: Icon(Lucide.Music, size: 18, color: cs.primary.withValues(alpha: 0.65)),
            )
          : Image.network(
              cover,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 38,
                height: 38,
                color: cs.primary.withValues(alpha: 0.14),
                child: Icon(Lucide.Music, size: 18, color: cs.primary.withValues(alpha: 0.65)),
              ),
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
