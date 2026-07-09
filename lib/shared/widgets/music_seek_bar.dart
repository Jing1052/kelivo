import 'package:flutter/material.dart';

/// The draggable playback progress bar shared by the full player page and the
/// chat music card: tap or drag anywhere on the strip to scrub, with the
/// elapsed/total labels underneath. Extracted from music_now_playing_page's
/// private `_SeekBar` when the chat card grew its own transport (§3.9).
class MusicSeekBar extends StatefulWidget {
  const MusicSeekBar({
    super.key,
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
  State<MusicSeekBar> createState() => _MusicSeekBarState();
}

class _MusicSeekBarState extends State<MusicSeekBar> {
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
