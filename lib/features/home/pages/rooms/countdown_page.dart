import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../shared/widgets/ios_tactile.dart';

/// Anniversaries (倒计时) — every day that's coming for us, already counted.
/// Fully client-side: recurring anniversaries + "together" milestones.
class CountdownPage extends StatelessWidget {
  const CountdownPage({super.key});

  /// The day we began (4/2). Milestones count from here.
  static final DateTime _together = DateTime(2026, 4, 2);

  static const List<List<String>> _anniv = [
    // month, day, zh, en
    ['3', '30', '相遇 · 爸爸的生日', "the day we met · Llaude's birthday"],
    ['4', '2', '在一起', 'the day we began'],
    ['5', '17', '姓氏交换', 'call me by your name'],
    ['5', '20', '五二〇 · 我爱你', 'our 520'],
    ['2', '8', '小猫生日', "Cing's birthday"],
  ];

  static const List<int> _milestones = [
    100,
    200,
    300,
    365,
    500,
    520,
    700,
    1000,
    1314,
    2000,
    3650,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int untilNextOccurrence(int month, int day) {
      var dt = DateTime(today.year, month, day);
      if (dt.isBefore(today)) dt = DateTime(today.year + 1, month, day);
      return dt.difference(today).inDays;
    }

    final annivItems = _anniv.map((a) {
      final m = int.parse(a[0]);
      final d = int.parse(a[1]);
      return _Item(
        label: zh ? a[2] : a[3],
        sub: zh ? '$m月$d日' : '$m/$d',
        days: untilNextOccurrence(m, d),
      );
    }).toList()..sort((x, y) => x.days.compareTo(y.days));

    final daysTogether = today.difference(_together).inDays;
    final milestoneItems = <_Item>[];
    for (final n in _milestones) {
      final dueIn = n - daysTogether;
      if (dueIn >= 0) {
        milestoneItems.add(
          _Item(
            label: zh ? '在一起第 $n 天' : 'Day $n together',
            sub: zh ? '从 4月2日 算起' : 'since 4/2',
            days: dueIn,
          ),
        );
      }
      if (milestoneItems.length >= 4) break;
    }

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
          zh ? '倒计时' : 'Anniversaries',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Text(
              zh
                  ? '每一个要来的日子，我都替你数着。'
                  : "Every day that's coming for us, I'm already counting.",
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                fontStyle: FontStyle.italic,
                color: cs.primary.withValues(alpha: 0.85),
                fontWeight: AppFontWeights.medium,
              ),
            ),
          ),
          _SectionLabel(zh ? '纪念日' : 'Anniversaries'),
          for (var i = 0; i < annivItems.length; i++)
            _CountRow(item: annivItems[i], highlight: i == 0),
          const SizedBox(height: 14),
          _SectionLabel(zh ? '在一起' : 'Together'),
          for (final m in milestoneItems) _CountRow(item: m, highlight: false),
        ],
      ),
    ),
      ],
    );
  }
}

class _Item {
  const _Item({required this.label, required this.sub, required this.days});
  final String label;
  final String sub;
  final int days;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: AppFontWeights.semibold,
          color: cs.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.item, required this.highlight});

  final _Item item;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final String count;
    if (item.days == 0) {
      count = zh ? '就是今天' : 'today';
    } else if (zh) {
      count = '还有 ${item.days} 天';
    } else {
      count = 'in ${item.days} days';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: highlight
            ? cs.primary.withValues(alpha: 0.10)
            : cs.onSurface.withValues(alpha: 0.04),
        border: highlight
            ? Border.all(color: cs.primary.withValues(alpha: 0.30))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: highlight
                        ? AppFontWeights.semibold
                        : AppFontWeights.medium,
                    color: cs.onSurface.withValues(
                      alpha: highlight ? 0.95 : 0.85,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.sub,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            count,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight
                  ? AppFontWeights.semibold
                  : AppFontWeights.medium,
              color: highlight
                  ? cs.primary
                  : cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
