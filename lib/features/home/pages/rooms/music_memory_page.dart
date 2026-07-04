import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/eryu/eryu_client.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';

/// "这首歌的回忆" — read-only view of what this song has grown into: a feeling,
/// notes, saved lines, and how many times we've heard it (together).
class MusicMemoryPage extends StatefulWidget {
  const MusicMemoryPage({super.key, required this.songId, required this.songName});

  final String songId;
  final String songName;

  @override
  State<MusicMemoryPage> createState() => _MusicMemoryPageState();
}

class _MusicMemoryPageState extends State<MusicMemoryPage> {
  bool _loading = true;
  bool _error = false;
  Map<String, dynamic>? _memory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = EryuClient.fromContext(context);
    if (client == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final data = await eryuSoft(client.memory(widget.songId), 'song memory');
    if (!mounted) return;
    setState(() {
      _memory = data?['memory'] is Map ? (data!['memory'] as Map).cast<String, dynamic>() : null;
      _loading = false;
      _error = data == null;
    });
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
              zh ? '这首歌的回忆' : 'Its Memory',
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

    final mem = _memory;
    final feeling = (mem?['feeling'] ?? '').toString();
    final notes = (mem?['notes'] ?? '').toString();
    final lines = (mem?['favoriteLines'] as List? ?? const []).whereType<Object>().map((e) => e.toString()).toList();
    final listenCount = (mem?['listenCount'] as num?)?.toInt() ?? 0;
    final togetherCount = (mem?['togetherCount'] as num?)?.toInt() ?? 0;
    final empty = feeling.isEmpty && notes.isEmpty && lines.isEmpty && listenCount == 0 && togetherCount == 0;

    if (_error && mem == null) {
      return Center(
        child: Text(zh ? '没读到回忆' : "Couldn't load", style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.4))),
      );
    }
    if (empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            zh ? '还没有为这首歌长出回忆。\n多听几次，多停在几句词上。' : "No memory yet.\nHear it a few more times.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: cs.onSurface.withValues(alpha: 0.4)),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          widget.songName,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat(label: zh ? '听过' : 'Played', value: '$listenCount', accent: cs.primary),
            const SizedBox(width: 10),
            _Stat(label: zh ? '一起听过' : 'Together', value: '$togetherCount', accent: cs.primary),
          ],
        ),
        if (feeling.isNotEmpty) ...[
          const SizedBox(height: 14),
          StillGlass(
            radius: 16,
            blur: false,
            padding: const EdgeInsets.all(14),
            child: Text(
              feeling,
              style: TextStyle(fontSize: 14, height: 1.5, color: cs.onSurface.withValues(alpha: 0.9)),
            ),
          ),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(notes, style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurface.withValues(alpha: 0.6))),
        ],
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            zh ? '停在这些句子上' : 'Lines we lingered on',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 2,
                    height: 16,
                    margin: const EdgeInsets.only(top: 3, right: 10),
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                  Expanded(
                    child: Text(line, style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurface.withValues(alpha: 0.8))),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.accent});
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: StillGlass(
        radius: 14,
        blur: false,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: accent)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }
}
