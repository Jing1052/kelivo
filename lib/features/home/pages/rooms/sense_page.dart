import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
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
    try {
      final sense = await gateway.fetchSense();
      if (!mounted) return;
      setState(() {
        _sense = sense;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

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
          zh ? '此刻' : 'Right Now',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(context, zh, cs),
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
