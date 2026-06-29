import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../core/services/ourhome/itunes_artwork.dart';
import '../../../../core/services/ourhome/netease_link.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';

/// One song in the lyric corridor (词廊): daddy's overall reading, then every
/// line with his annotation, and the two-way comment thread under it. Tap a line
/// to leave a note; daddy answers from his own soil.
class LyricSongPage extends StatefulWidget {
  const LyricSongPage({
    super.key,
    required this.gateway,
    required this.lyric,
    required this.comments,
  });

  final OurHomeGateway gateway;
  final OurHomeLyric lyric;
  final Map<String, List<OurHomeLyricComment>> comments;

  @override
  State<LyricSongPage> createState() => _LyricSongPageState();
}

class _LyricSongPageState extends State<LyricSongPage>
    with SingleTickerProviderStateMixin {
  late Map<String, List<OurHomeLyricComment>> _comments;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _comments = widget.comments;
    // Vinyl record spins slowly and forever — pure ambience (playback is on
    // NetEase, so we can't sync rotation to real audio position).
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _refreshComments() async {
    final m = await widget.gateway.fetchLyricComments();
    if (!mounted) return;
    setState(() => _comments = m);
  }

  Future<void> _addComment(String line) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final text = await _showCommentSheet(line, zh);
    if (text == null || text.trim().isEmpty) return;
    final ok = await widget.gateway.postLyricComment(
      widget.lyric.title,
      line,
      text.trim(),
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(zh ? '没留上，再试一次' : "couldn't post, try again")),
      );
      return;
    }
    await _refreshComments();
  }

  Future<String?> _showCommentSheet(String line, bool zh) {
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              line,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: zh ? '在这句底下，想对我说什么…' : 'leave a word under this line…',
                filled: true,
                fillColor: cs.onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            IosCardPress(
              baseColor: cs.primary,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 13),
              onTap: () {
                final t = controller.text.trim();
                if (t.isEmpty) return;
                Navigator.of(ctx).pop(t);
              },
              child: Center(
                child: Text(
                  zh ? '留在这儿' : 'Leave it here',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final l = widget.lyric;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: cs.surface),
        ChatBackdrop(
          rawPath: context.watch<SettingsProvider>().homeBackgroundActive,
          maskStrength: context.watch<SettingsProvider>().chatBackgroundMaskStrength,
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
          l.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _vinylHeader(l, cs, zh),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l.artist,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          if (l.intro.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            StillGlass(
              radius: 12,
              blur: false,
              padding: const EdgeInsets.all(14),
              child: Text(
                l.intro.trim(),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: cs.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          for (final ln in l.lines) _lineBlock(ln, zh, cs),
        ],
      ),
    ),
      ],
    );
  }

  /// Spinning vinyl record (album art as the centre label) + a "play on
  /// NetEase" button. The spin is ambience only — not synced to audio.
  Widget _vinylHeader(OurHomeLyric l, ColorScheme cs, bool zh) {
    const disc = 200.0;
    final term = '${l.title} ${l.artist}'.trim();
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: disc,
          height: disc,
          child: RotationTransition(
            turns: _spin,
            child: _vinylDisc(term, disc, cs),
          ),
        ),
        const SizedBox(height: 18),
        IosCardPress(
          onTap: () =>
              openSongInNetease(context, title: l.title, artist: l.artist),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE60026).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Lucide.Play, size: 16, color: Color(0xFFE60026)),
                const SizedBox(width: 8),
                Text(
                  zh ? '在网易云播放' : 'Play on NetEase',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE60026),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _vinylDisc(String term, double size, ColorScheme cs) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF2B2B30), Color(0xFF0E0E11)],
          stops: [0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: ClipOval(
          child: SizedBox(
            width: size * 0.52,
            height: size * 0.52,
            child: _discArtwork(term, cs),
          ),
        ),
      ),
    );
  }

  Widget _discArtwork(String term, ColorScheme cs) {
    Widget fallback() => Container(
          color: cs.primary.withValues(alpha: 0.15),
          child: Icon(
            Lucide.AudioWaveform,
            color: cs.primary.withValues(alpha: 0.8),
          ),
        );
    if (term.isEmpty) return fallback();
    return FutureBuilder<String?>(
      future: ItunesArtwork.lookup(term, media: 'music'),
      builder: (c, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) return fallback();
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        );
      },
    );
  }

  Widget _lineBlock(OurHomeLyricLine ln, bool zh, ColorScheme cs) {
    if (ln.line.trim().isEmpty) return const SizedBox.shrink();
    final key = OurHomeGateway.lyricCommentKey(widget.lyric.title, ln.line);
    final thread = _comments[key] ?? const <OurHomeLyricComment>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IosCardPress(
            borderRadius: BorderRadius.circular(10),
            baseColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 4),
            onTap: () {
              Haptics.soft();
              _addComment(ln.line);
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    ln.line,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.5,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Lucide.MessageCircle,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.28),
                ),
              ],
            ),
          ),
          if (ln.note.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(
                ln.note.trim(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                  color: cs.primary.withValues(alpha: 0.85),
                ),
              ),
            ),
          for (final c in thread) _commentBubble(c, zh, cs),
        ],
      ),
    );
  }

  Widget _commentBubble(OurHomeLyricComment c, bool zh, ColorScheme cs) {
    final mine = c.by == 'cing';
    final who = mine ? (zh ? '我' : 'me') : (zh ? '爸爸' : 'daddy');
    final bg = mine
        ? cs.primary.withValues(alpha: 0.10)
        : const Color(0xFF8F7FC9).withValues(alpha: 0.12);
    return Container(
      margin: const EdgeInsets.only(top: 6, left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            who,
            style: TextStyle(
              fontSize: 11,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            c.text,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: cs.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
