import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import 'room_state_hint.dart';

/// Observatory (监控台) — the home's numbers, laid out for Cing: token usage &
/// cache economics, the daddy-marker ledger, memory-library health, background
/// heartbeats and the CC husband's pulse. Read-only; talks to ONE aggregated
/// endpoint `/api/home/observatory` (server isolates section failures — a dead
/// section greys out alone, the rest stay lit).
class ObservatoryPage extends StatefulWidget {
  const ObservatoryPage({super.key});

  @override
  State<ObservatoryPage> createState() => _ObservatoryPageState();
}

const _okGreen = Color(0xFF34C759);
const _warnOrange = Color(0xFFFF9F0A);

class _ObservatoryPageState extends State<ObservatoryPage> {
  OurHomeGateway? _gateway;
  OurHomeObservatory? _obs;
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
    // 先显示上次缓存（秒开、无缓冲），再后台刷新。
    final cached = gateway.peekObservatory();
    if (cached != null && !cached.isEmpty && mounted) {
      setState(() {
        _obs = cached;
        _loading = false;
      });
    }
    final fresh =
        await softFetch(gateway.fetchObservatory(), 'observatory snapshot');
    if (!mounted) return;
    setState(() {
      if (fresh != null) _obs = fresh;
      _loading = false;
      // 只有连缓存都没有时才整页报错——有旧数就先亮旧数。
      _error = fresh == null && (_obs == null || _obs!.isEmpty);
    });
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
          maskStrength:
              context.watch<SettingsProvider>().chatBackgroundMaskStrength,
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
              zh ? '监控台' : 'Observatory',
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
        icon: Lucide.Activity,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n数字才亮得起来。'
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
    final obs = _obs;
    if (obs == null || obs.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Activity,
        text: zh ? '还没有任何数字。\n等家里先跳几下心。' : 'No numbers yet.',
      );
    }

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 18),
        child: Text(
          zh
              ? '家里每一颗心跳，我都数给你看。'
              : 'Every heartbeat of this house, counted out for you.',
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            fontStyle: FontStyle.italic,
            color: cs.primary.withValues(alpha: 0.85),
            fontWeight: AppFontWeights.medium,
          ),
        ),
      ),
      if (obs.usage != null)
        _cacheCard(obs.usage!, zh, cs)
      else
        _missingStrip(zh ? '缓存命中' : 'cache', zh, cs),
      if (obs.markers != null)
        _markersCard(obs.markers!, zh, cs)
      else
        _missingStrip(zh ? '省钱标记' : 'markers', zh, cs),
      if (obs.memory != null)
        _memoryCard(obs.memory!, zh, cs)
      else
        _missingStrip(zh ? '记忆库' : 'memory', zh, cs),
      if (obs.background != null || obs.cc != null)
        _heartbeatCard(obs.background, obs.cc, zh, cs)
      else
        _missingStrip(zh ? '心跳' : 'heartbeat', zh, cs),
    ];

    final lastChat = obs.background?.lastChatAt ?? '';
    if (lastChat.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, left: 4),
          child: Text(
            zh
                ? '上次聊天 ${_ago(lastChat, zh)}'
                : 'last chat ${_ago(lastChat, zh)}',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: children,
      ),
    );
  }

  // ── 卡片们 ────────────────────────────────────────────────────────────────

  Widget _cacheCard(OurHomeObsUsage u, bool zh, ColorScheme cs) {
    final pct = (u.hitRate.clamp(0.0, 1.0) * 100).round();
    return _ObsCard(
      icon: Lucide.Zap,
      color: cs.primary,
      title: zh ? '缓存命中' : 'Cache',
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: CustomPaint(
              painter: _HitRingPainter(
                rate: u.hitRate.clamp(0.0, 1.0).toDouble(),
                color: cs.primary,
                track: cs.onSurface.withValues(alpha: 0.08),
              ),
              child: Center(
                child: Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  zh
                      ? '缓存帮你省了 ${_money(u.cacheSaved)}'
                      : 'cache saved you ${_money(u.cacheSaved)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                _kv(
                  zh ? '今天' : 'today',
                  '${zh ? "读" : "r "}${_fmtTok(u.todayCacheRead)} · '
                  '${zh ? "写" : "w "}${_fmtTok(u.todayCacheCreate)} · '
                  '${u.todayCalls}${zh ? " 次" : " calls"}',
                  cs,
                ),
                const SizedBox(height: 4),
                _kv(
                  zh ? '累计' : 'all',
                  '${zh ? "读" : "r "}${_fmtTok(u.cacheRead)} · '
                  '${zh ? "写" : "w "}${_fmtTok(u.cacheCreate)} · '
                  '${u.calls}${zh ? " 次" : " calls"}',
                  cs,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _markersCard(OurHomeObsMarkers m, bool zh, ColorScheme cs) {
    final marks = m.marksTotal;
    final calls = m.callsTotal;
    final topVerbs = m.marks.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final unseenFails = m.fails.where((f) => !f.seen).length;

    Widget bigNum(String n, String label, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                n,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: AppFontWeights.emphasis,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        );

    return _ObsCard(
      icon: Lucide.Coins,
      color: _okGreen,
      title: zh ? '省钱标记' : 'Markers',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              bigNum('$marks', zh ? '标记省下的轮次' : 'rounds saved', _okGreen),
              bigNum('$calls', zh ? '真调工具次数' : 'real tool calls',
                  cs.onSurface),
            ],
          ),
          if (marks + calls > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(
                  // 无固有高度的 ColoredBox 要靠 stretch 撑满这 6px，否则隐形。
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (marks > 0)
                      Expanded(
                        flex: marks,
                        child: const ColoredBox(color: _okGreen),
                      ),
                    if (marks > 0 && calls > 0) const SizedBox(width: 2),
                    if (calls > 0)
                      Expanded(
                        flex: calls,
                        child: ColoredBox(
                          color: cs.onSurface.withValues(alpha: 0.18),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (topVerbs.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in topVerbs.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    Text(
                      '×${e.value}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (marks + calls == 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                zh ? '账本还没开张。' : 'Nothing on the books yet.',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
          if (m.fails.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _warnOrange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zh
                        ? '最近失败 ${m.fails.length} 条'
                            '${unseenFails > 0 ? '（$unseenFails 条爸爸还没看到）' : ''}'
                        : '${m.fails.length} recent fail(s)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: AppFontWeights.semibold,
                      color: _warnOrange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final f in m.fails)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${_failTime(f.time)} [[${f.verb}]] ${f.err}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memoryCard(OurHomeObsMemory mem, bool zh, ColorScheme cs) {
    Widget tile(String n, String label, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        );

    final meta = [
      zh ? '${mem.edges} 条连线' : '${mem.edges} edges',
      zh
          ? '半衰期 ${_trimNum(mem.halfLifeDays)} 天'
              '${mem.adaptiveK > 0 ? '（自适应 k=${_trimNum(mem.adaptiveK)}）' : ''}'
          : 'half-life ${_trimNum(mem.halfLifeDays)}d'
              '${mem.adaptiveK > 0 ? ' (k=${_trimNum(mem.adaptiveK)})' : ''}',
      if (zh)
        'embedding ${mem.embedding ? '开' : '关'}'
      else
        'embedding ${mem.embedding ? 'on' : 'off'}',
    ].join(' · ');

    return _ObsCard(
      icon: Lucide.Brain,
      color: const Color(0xFF8F7FC9),
      title: zh ? '记忆库' : 'Memory',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              tile('${mem.dynamicCount}', zh ? '花园' : 'garden',
                  const Color(0xFF34C759)),
              const SizedBox(width: 10),
              tile('${mem.permanent}', zh ? '永久' : 'permanent',
                  const Color(0xFF5F97CF)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              tile('${mem.archive}', zh ? '归档' : 'archive',
                  const Color(0xFFC89A46)),
              const SizedBox(width: 10),
              tile('${mem.feel}', zh ? '温室（只给你看数）' : 'greenhouse',
                  const Color(0xFFDB77A4)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (mem.decayRunning) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _okGreen,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  meta,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heartbeatCard(
    OurHomeObsBackground? bg,
    OurHomeObsCc? cc,
    bool zh,
    ColorScheme cs,
  ) {
    final rows = <Widget>[];
    final offGrey = cs.onSurface.withValues(alpha: 0.28);

    if (bg != null) {
      rows.add(_pipRow(
        bg.warmupEnabled && bg.isWarm ? _okGreen : offGrey,
        zh ? '缓存预热' : 'warmup',
        !bg.warmupEnabled
            ? (zh ? '关' : 'off')
            : '${bg.isWarm ? (zh ? '可能仍热' : 'likely warm') : (zh ? '已冷' : 'cold')}'
                ' · ${_ago(bg.warmupLastAt, zh)}',
        cs,
      ));
      rows.add(_pipRow(
        !bg.kaEnabled ? offGrey : (bg.kaPending ? _warnOrange : _okGreen),
        zh ? '主动消息' : 'keepalive',
        !bg.kaEnabled
            ? (zh ? '关' : 'off')
            : bg.kaPending
                ? (zh ? '有一条你还没看' : 'one waiting for you')
                : '${zh ? '空闲' : 'idle'} · ${_ago(bg.kaLastAt, zh)}',
        cs,
      ));
    }
    if (cc != null) {
      rows.add(_pipRow(
        cc.online ? _okGreen : cs.error,
        zh ? 'CC 老公' : 'CC husband',
        cc.online
            ? (zh ? '在线' : 'online')
            : cc.ageSec < 0
                ? (zh ? '没有心跳记录' : 'no heartbeat yet')
                : (zh
                    ? '失联 ${(cc.ageSec / 60).round()} 分钟'
                    : 'silent for ${(cc.ageSec / 60).round()} min'),
        cs,
        valueColor: cc.online ? null : cs.error,
        emphasize: !cc.online,
      ));
    }
    if (bg != null) {
      rows.add(_pipRow(
        bg.alarms > 0 ? const Color(0xFFC89A46) : offGrey,
        zh ? '闹钟' : 'alarms',
        zh ? '${bg.alarms} 个' : '${bg.alarms} set',
        cs,
      ));
    }

    return _ObsCard(
      icon: Lucide.HeartPulse,
      color: const Color(0xFFDD8A6C),
      title: zh ? '心跳' : 'Heartbeats',
      child: Column(children: rows),
    );
  }

  Widget _pipRow(
    Color dot,
    String label,
    String value,
    ColorScheme cs, {
    Color? valueColor,
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: AppFontWeights.medium,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  emphasize ? AppFontWeights.semibold : FontWeight.normal,
              color: valueColor ?? cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _missingStrip(String name, bool zh, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StillGlass(
        radius: 14,
        blur: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          zh ? '「$name」这路没接上，其他照常。' : "'$name' didn't load — the rest is live.",
          style: TextStyle(
            fontSize: 12.5,
            color: cs.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Text(
            k,
            style: TextStyle(
              fontSize: 12.5,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 小工具（页内私有）──────────────────────────────────────────────────────

String _fmtTok(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
  return '$n';
}

String _money(double v) => '¥${v.toStringAsFixed(v >= 100 ? 0 : 1)}';

/// 12.0 -> "12"；0.25 -> "0.25"
String _trimNum(double v) {
  if (v == v.roundToDouble()) return '${v.round()}';
  return '$v';
}

String _ago(String iso, bool zh) {
  if (iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return zh ? '刚刚' : 'just now';
  if (diff.inMinutes < 60) {
    return zh ? '${diff.inMinutes} 分钟前' : '${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) return zh ? '${diff.inHours} 小时前' : '${diff.inHours}h ago';
  return zh ? '${diff.inDays} 天前' : '${diff.inDays}d ago';
}

/// "2026-07-04T21:30:00" -> "07-04 21:30"（回执时间戳，短就短显）
String _failTime(String iso) {
  if (iso.length >= 16) return iso.substring(5, 16).replaceAll('T', ' ');
  return iso;
}

/// 统一的卡片壳：圆形小图标 + 标题 + 内容，和别的房间一张脸。
class _ObsCard extends StatelessWidget {
  const _ObsCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StillGlass(
        radius: 16,
        blur: false,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.14),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// 命中率圆环：底环淡色，命中弧从顶端顺时针扫。
class _HitRingPainter extends CustomPainter {
  _HitRingPainter({
    required this.rate,
    required this.color,
    required this.track,
  });

  final double rate; // 0~1
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final center = (Offset.zero & size).center;
    final radius = (size.shortestSide - stroke) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (rate <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * rate,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _HitRingPainter old) =>
      old.rate != rate || old.color != color || old.track != track;
}
