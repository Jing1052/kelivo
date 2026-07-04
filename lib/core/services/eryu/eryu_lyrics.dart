/// One timed lyric line plus its optional Chinese translation.
class EryuLyricLine {
  EryuLyricLine(this.time, this.text, [this.trans = '']);
  final Duration time;
  final String text;
  String trans;
}

/// Minimal LRC parser matching the eryu web client's behavior: `[mm:ss.xx]`
/// tags (a line may carry several), translation track merged by timestamp.
class EryuLyrics {
  static final RegExp _tagRe = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  static List<EryuLyricLine> parse(String lrc, String tlyric) {
    final lines = _parseTrack(lrc);
    final trans = _parseTrack(tlyric);
    final byMs = <int, String>{for (final t in trans) t.time.inMilliseconds: t.text};
    for (final l in lines) {
      final t = byMs[l.time.inMilliseconds];
      if (t != null && t.isNotEmpty) l.trans = t;
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  static List<EryuLyricLine> _parseTrack(String raw) {
    final out = <EryuLyricLine>[];
    for (final line in raw.split('\n')) {
      final matches = _tagRe.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final text = line.replaceAll(_tagRe, '').trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final min = int.tryParse(m.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
        final frac = m.group(3);
        var ms = 0;
        if (frac != null && frac.isNotEmpty) {
          // "5" -> 500ms, "05" -> 50ms, "050" -> 50ms.
          final padded = frac.padRight(3, '0').substring(0, 3);
          ms = int.tryParse(padded) ?? 0;
        }
        out.add(EryuLyricLine(Duration(minutes: min, seconds: sec, milliseconds: ms), text));
      }
    }
    return out;
  }

  /// Index of the line active at [position], or -1 before the first line.
  static int activeIndex(List<EryuLyricLine> lines, Duration position) {
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }
}
