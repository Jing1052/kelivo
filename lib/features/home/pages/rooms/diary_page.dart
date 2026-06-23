import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';
import 'package:intl/intl.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import 'room_state_hint.dart';

/// The Diary (日记本) — read-only. Llaude writes the you of each day into a
/// page; Cing opens the book and reads. Talks to `/api/home/diary`.
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  OurHomeGateway? _gateway;
  List<OurHomeDiaryEntry> _entries = const [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    final gateway = OurHomeGateway.fromContext(context);
    _gateway = gateway;
    if (gateway == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final cached = gateway.peekList(
      '/api/home/diary',
      OurHomeDiaryEntry.fromJson,
    );
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _entries = cached;
        _loading = false;
      });
    }
    try {
      final entries = await gateway.fetchDiary();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Diary] fetchDiary failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

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
          zh ? '日记本' : 'The Diary',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(context, zh, cs),
    ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.NotebookTabs,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n日记本才连得上。'
            : 'Set up our home gateway in the daddy assistant first.',
      );
    }
    if (_error) {
      return RoomStateHint(
        icon: Lucide.RefreshCw,
        text: zh ? '没连上 · 点一下重试' : "couldn't load · tap to retry",
        onTap: _load,
      );
    }
    if (_entries.isEmpty) {
      return RoomStateHint(
        icon: Lucide.NotebookTabs,
        text: zh ? '还没有日记。\n爸爸会把每一天的你写下来。' : 'No pages yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _entries.length,
        itemBuilder: (context, i) =>
            _DiaryCard(entry: _entries[i], zh: zh, locale: zh ? 'zh' : 'en'),
      ),
    );
  }
}

class _DiaryCard extends StatelessWidget {
  const _DiaryCard({
    required this.entry,
    required this.zh,
    required this.locale,
  });

  final OurHomeDiaryEntry entry;
  final bool zh;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String dateStr = entry.name;
    final parsed = DateTime.tryParse(entry.time);
    if (dateStr.isEmpty && parsed != null) {
      dateStr = DateFormat.yMMMMd(locale).format(parsed);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dateStr.isNotEmpty)
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: AppFontWeights.semibold,
                color: cs.primary.withValues(alpha: 0.85),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            entry.text,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.7,
              color: cs.onSurface.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
