import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../../../shared/widgets/ios_switch.dart';
import 'room_state_hint.dart';

/// Right Now (此刻) — where Cing is, the sky over her, her battery. Read-only
/// view of what her phone last reported. Talks to `/api/home/sense`.
class SensePage extends StatefulWidget {
  const SensePage({super.key});

  @override
  State<SensePage> createState() => _SensePageState();
}

class _SensePageState extends State<SensePage> {
  OurHomeGateway? _gateway;
  OurHomeSense? _sense;
  bool _loading = true;
  bool _error = false;
  bool? _morningBrief; // 早安心跳推送开关；null=没读到/不显示
  bool _savingMorning = false;

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
    // 先显示上次缓存（秒开、无缓冲），再后台刷新。
    final cached = gateway.peekSense();
    if (cached != null && mounted) {
      setState(() {
        _sense = cached;
        _loading = false;
      });
    }
    try {
      final results = await Future.wait([
        gateway.fetchSense(),
        gateway.fetchMorningBrief(),
      ]);
      if (!mounted) return;
      setState(() {
        _sense = results[0] as OurHomeSense?;
        _morningBrief = results[1] as bool?;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Sense] fetchSense failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Widget _morningCard(bool zh, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFC89A46).withValues(alpha: 0.14),
            ),
            child: const Icon(Lucide.Sun, size: 22, color: Color(0xFFC89A46)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  zh ? '早安心跳推送' : 'morning check-in',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  zh
                      ? '每天早上爸爸读你的心跳天气，给你发一条。忙了可以关。'
                      : "each morning daddy reads your pulse & sky, sends one note. off when busy.",
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IosSwitch(
            value: _morningBrief ?? true,
            onChanged: _savingMorning ? null : _setMorningBrief,
          ),
        ],
      ),
    );
  }

  Future<void> _setMorningBrief(bool value) async {
    if (_savingMorning) return;
    final gateway = _gateway;
    if (gateway == null) return;
    final prev = _morningBrief;
    setState(() {
      _morningBrief = value;
      _savingMorning = true;
    });
    final ok = await gateway.setMorningBrief(value);
    if (!mounted) return;
    setState(() {
      _savingMorning = false;
      if (!ok) _morningBrief = prev; // 没存上就回滚
    });
    if (!ok) {
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(zh ? '没存上，再试一次' : "couldn't save, try again")),
      );
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
              zh ? '此刻' : 'Right Now',
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
        icon: Lucide.MapPin,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n此刻才连得上。'
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
    final sense = _sense;
    if (sense == null || sense.isEmpty) {
      return RoomStateHint(
        icon: Lucide.HeartPulse,
        text: zh ? '此刻还没有动静。\n等你的手机报一声平安。' : 'Nothing reported yet.',
      );
    }

    final cards = <Widget>[];
    if (sense.place != null) {
      cards.add(
        _SenseCard(
          icon: Lucide.MapPin,
          color: cs.primary,
          label: zh ? '你在哪' : 'where you are',
          value: sense.place!,
        ),
      );
    }
    if (sense.weather != null || sense.temp != null) {
      final w = [
        if (sense.weather != null) sense.weather!,
        if (sense.temp != null) '${sense.temp}°',
      ].join('  ');
      cards.add(
        _SenseCard(
          icon: Lucide.CloudSun,
          color: cs.tertiary,
          label: zh ? '此刻天色' : 'the sky now',
          value: w,
        ),
      );
    }
    if (sense.battery != null) {
      cards.add(
        _SenseCard(
          icon: sense.charging ? Lucide.BatteryCharging : Lucide.Battery,
          color: cs.primary,
          label: zh ? '还剩多少电' : 'battery',
          value:
              '${sense.battery}%${sense.charging ? (zh ? ' · 充电中' : ' · charging') : ''}',
        ),
      );
    }
    if (sense.hr != null) {
      cards.add(
        _SenseCard(
          icon: Lucide.HeartPulse,
          color: cs.error,
          label: zh ? '心率' : 'heart rate',
          value: '${sense.hr} bpm',
        ),
      );
    }
    if (sense.sleep != null) {
      cards.add(
        _SenseCard(
          icon: Lucide.Moon,
          color: cs.tertiary,
          label: zh ? '睡眠' : 'sleep',
          value: '${sense.sleep} h',
        ),
      );
    }

    String updated = '';
    final parsed = DateTime.tryParse(sense.ts);
    if (parsed != null) {
      updated = DateFormat.MMMd().add_Hm().format(parsed);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 18),
            child: Text(
              zh
                  ? '你在哪，我的牵挂就伸到哪。'
                  : 'Wherever you are is where I reach toward.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                fontStyle: FontStyle.italic,
                color: cs.primary.withValues(alpha: 0.85),
                fontWeight: AppFontWeights.medium,
              ),
            ),
          ),
          ...cards,
          if (_morningBrief != null) _morningCard(zh, cs),
          if (updated.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: Text(
                zh ? '更新于 $updated' : 'updated $updated',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SenseCard extends StatelessWidget {
  const _SenseCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
