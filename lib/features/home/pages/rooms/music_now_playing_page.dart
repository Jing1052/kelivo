import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/eryu/eryu_player_controller.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../shared/widgets/ios_tactile.dart';

/// The full-screen player. Big cover + seek + transport. Lyrics, 一起听 and
/// "这首歌的回忆" arrive in Step 2.
class MusicNowPlayingPage extends StatelessWidget {
  const MusicNowPlayingPage({super.key});

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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      _Cover(cover: song.cover, accent: cs.primary),
                      const SizedBox(height: 36),
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
                      const Spacer(flex: 2),
                      _SeekBar(
                        position: player.position,
                        duration: player.duration,
                        accent: cs.primary,
                        onSeek: (d) => player.seek(d),
                      ),
                      const SizedBox(height: 20),
                      _Controls(player: player, accent: cs.primary, onColor: cs.onPrimary, ink: cs.onSurface),
                      const Spacer(flex: 1),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
                  errorBuilder: (_, __, ___) =>
                      Icon(Lucide.Music, size: 64, color: accent.withValues(alpha: 0.5)),
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
    final playedFraction = totalMs > 0
        ? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final fraction = _dragFraction ?? playedFraction;
    final shownPos = totalMs > 0
        ? Duration(milliseconds: (fraction * totalMs).round())
        : widget.position;

    void seekTo(double localX, double width) {
      final f = width > 0 ? (localX / width).clamp(0.0, 1.0).toDouble() : 0.0;
      setState(() => _dragFraction = f);
    }

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => seekTo(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx, width),
              onHorizontalDragEnd: (_) {
                if (_dragFraction != null && totalMs > 0) {
                  widget.onSeek(Duration(milliseconds: (_dragFraction! * totalMs).round()));
                }
                setState(() => _dragFraction = null);
              },
              onTapUp: (_) {
                if (_dragFraction != null && totalMs > 0) {
                  widget.onSeek(Duration(milliseconds: (_dragFraction! * totalMs).round()));
                }
                setState(() => _dragFraction = null);
              },
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
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
                          ],
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
  const _Controls({
    required this.player,
    required this.accent,
    required this.onColor,
    required this.ink,
  });

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
        IosIconButton(
          icon: Lucide.Repeat,
          size: 20,
          color: ink.withValues(alpha: 0.5),
          onTap: player.next,
        ),
      ],
    );
  }
}
