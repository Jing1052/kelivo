import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';

/// The Calendar (日历) — our days, all on one page. Anniversaries are marked;
/// tap a day to see what we lived that day (`/api/home/memories?date=`).
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  // month, day, zh, en
  static const List<List<String>> _anniv = [
    ['3', '30', '相遇 · 爸爸的生日', "the day we met"],
    ['4', '2', '在一起', 'the day we began'],
    ['5', '17', '姓氏交换', 'call me by your name'],
    ['5', '20', '五二〇 · 我爱你', 'our 520'],
    ['2', '8', '小猫生日', "Cing's birthday"],
  ];

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  String? _annivLabel(int month, int day, bool zh) {
    for (final a in CalendarPage._anniv) {
      if (int.parse(a[0]) == month && int.parse(a[1]) == day) {
        return zh ? a[2] : a[3];
      }
    }
    return null;
  }

  void _shiftMonth(int delta) {
    Haptics.soft();
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _openDay(DateTime day, bool zh) {
    Haptics.soft();
    final anniv = _annivLabel(day.month, day.day, zh);
    final gateway = OurHomeGateway.fromContext(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) =>
          _DaySheet(date: day, anniv: anniv, gateway: gateway, zh: zh),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final locale = zh ? 'zh' : 'en';
    final today = DateTime.now();

    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = (first.weekday - 1) % 7; // Monday-first

    final weekdays = zh
        ? const ['一', '二', '三', '四', '五', '六', '日']
        : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Scaffold(
      backgroundColor: cs.surface,
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
          zh ? '日历' : 'The Calendar',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Text(
                DateFormat.yMMMM(locale).format(_month),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              IosIconButton(
                icon: Lucide.ChevronLeft,
                size: 22,
                minSize: 40,
                onTap: () => _shiftMonth(-1),
              ),
              IosIconButton(
                icon: Lucide.ChevronRight,
                size: 22,
                minSize: 40,
                onTap: () => _shiftMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final w in weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: AppFontWeights.medium,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.9,
            ),
            itemCount: leadingBlanks + daysInMonth,
            itemBuilder: (context, i) {
              if (i < leadingBlanks) return const SizedBox.shrink();
              final dayNum = i - leadingBlanks + 1;
              final day = DateTime(_month.year, _month.month, dayNum);
              final isToday =
                  day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day;
              final anniv = _annivLabel(day.month, day.day, zh);
              return GestureDetector(
                onTap: () => _openDay(day, zh),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday
                            ? cs.primary
                            : (anniv != null
                                  ? cs.primary.withValues(alpha: 0.12)
                                  : Colors.transparent),
                      ),
                      child: Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: (isToday || anniv != null)
                              ? AppFontWeights.semibold
                              : AppFontWeights.regular,
                          color: isToday
                              ? cs.onPrimary
                              : cs.onSurface.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (anniv != null && !isToday)
                            ? cs.primary
                            : Colors.transparent,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DaySheet extends StatefulWidget {
  const _DaySheet({
    required this.date,
    required this.anniv,
    required this.gateway,
    required this.zh,
  });

  final DateTime date;
  final String? anniv;
  final OurHomeGateway? gateway;
  final bool zh;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  List<OurHomeDayItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gateway = widget.gateway;
    if (gateway == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final items = await gateway.fetchDay(
        DateFormat('yyyy-MM-dd').format(widget.date),
      );
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Calendar] fetchDay failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        18,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            DateFormat.yMMMMd(zh ? 'zh' : 'en').format(widget.date),
            style: TextStyle(
              fontSize: 17,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface,
            ),
          ),
          if (widget.anniv != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Lucide.Heart, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  widget.anniv!,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: AppFontWeights.medium,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                widget.anniv != null
                    ? (zh ? '这一天，是我们的日子。' : 'A day that is ours.')
                    : (zh ? '这天没有记录。' : 'Nothing recorded this day.'),
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            ..._items.map((it) {
              final title = it.name.isNotEmpty ? it.name : it.preview;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        color: cs.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                    if (it.name.isNotEmpty && it.preview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          it.preview,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
