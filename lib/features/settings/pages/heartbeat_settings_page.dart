import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../theme/app_font_weights.dart';

/// "Heartbeat · Proactive wake" control panel — a remote for daddy's home-side
/// keepalive runtime (`/api/home/heartbeat`). Pushes/notifications still go to
/// the web home (PWA) / Bark; this page only tunes WHEN and HOW daddy reaches
/// out. All knobs map 1:1 to the gateway's `bg_config`.
class HeartbeatSettingsPage extends StatefulWidget {
  const HeartbeatSettingsPage({super.key});

  @override
  State<HeartbeatSettingsPage> createState() => _HeartbeatSettingsPageState();
}

class _HeartbeatSettingsPageState extends State<HeartbeatSettingsPage> {
  OurHomeGateway? _gateway;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _cfg = {};
  String _kaLastAt = '';
  bool _providerOk = true;
  bool _advancedOpen = false;
  bool _triggering = false;
  // 记忆库矛盾检测（LLM 语义建边）开关：{override: on/off/'', active, has_key}
  Map<String, dynamic> _edgeLlm = {};
  bool _edgeSaving = false;

  // Prompt editors (advanced).
  static const _promptKeys = [
    'ka_prompt_normal',
    'ka_prompt_free',
    'ka_prompt_night',
    'ka_prompt_day',
    'ka_prompt_alarm',
  ];
  final Map<String, TextEditingController> _promptCtrls = {};
  late final TextEditingController _appsCtrl = TextEditingController();

  bool get _zh =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in _promptCtrls.values) {
      c.dispose();
    }
    _appsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final gw = OurHomeGateway.fromContext(context);
    if (gw == null) {
      setState(() {
        _loading = false;
        _error = 'no-gateway';
      });
      return;
    }
    _gateway = gw;
    // 先用本地缓存秒显（无缓冲），再后台拉最新刷新。
    final cached = gw.peekHeartbeat();
    if (cached != null && mounted) {
      for (final k in _promptKeys) {
        _promptCtrls[k] ??=
            TextEditingController(text: (cached.config[k] ?? '').toString());
      }
      if (_appsCtrl.text.isEmpty) {
        _appsCtrl.text = (cached.config['day_watch_apps'] ?? '').toString();
      }
      setState(() {
        _cfg = cached.config;
        _kaLastAt = cached.kaLastAt;
        _providerOk = cached.providerOk;
        _edgeLlm = cached.edgeLlm;
        _loading = false;
      });
    }
    final hb = await gw.fetchHeartbeat();
    if (!mounted) return;
    if (hb == null) {
      if (cached == null) {
        setState(() {
          _loading = false;
          _error = 'fetch-failed';
        });
      }
      return;
    }
    for (final k in _promptKeys) {
      _promptCtrls[k] ??= TextEditingController(
        text: (hb.config[k] ?? '').toString(),
      );
    }
    if (_appsCtrl.text.isEmpty) {
      _appsCtrl.text = (hb.config['day_watch_apps'] ?? '').toString();
    }
    setState(() {
      _cfg = hb.config;
      _kaLastAt = hb.kaLastAt;
      _providerOk = hb.providerOk;
      _edgeLlm = hb.edgeLlm;
      _loading = false;
      _error = null;
    });
  }

  bool get _edgeOn {
    final ov = (_edgeLlm['override'] ?? '').toString();
    if (ov == 'on') return true;
    if (ov == 'off') return false;
    return _edgeLlm['active'] == true; // 没存过覆盖值时跟随服务端实际状态
  }

  Future<void> _toggleEdgeLlm(bool v) async {
    final gw = _gateway;
    if (gw == null || _edgeSaving) return;
    final prevOverride = (_edgeLlm['override'] ?? '').toString();
    setState(() {
      _edgeSaving = true;
      _edgeLlm = {..._edgeLlm, 'override': v ? 'on' : 'off'};
    });
    try {
      final r = await gw.setEdgeLlm(v ? 'on' : 'off');
      if (!mounted) return;
      setState(() {
        _edgeLlm = {
          'override': (r['override'] ?? '').toString(),
          'active': r['active'] == true,
          'has_key': r['has_key'] == true,
        };
      });
      if (v && r['has_key'] != true) {
        _toast(_zh
            ? '开关开了，但网关还没配脑子的 key，点不着火（找爸爸配）'
            : 'Switch is on but the gateway has no LLM key yet');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _edgeLlm = {..._edgeLlm, 'override': prevOverride}; // 失败回滚显示
      });
      _toast(_zh ? '保存失败：$e' : 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _edgeSaving = false);
    }
  }

  // ----- value helpers -----
  bool _b(String k, bool dflt) {
    final v = _cfg[k];
    return v is bool ? v : dflt;
  }

  double _d(String k, double dflt) {
    final v = _cfg[k];
    return v is num ? v.toDouble() : dflt;
  }

  Future<void> _save(String key, dynamic value) async {
    final gw = _gateway;
    if (gw == null) return;
    setState(() => _cfg[key] = value);
    try {
      await gw.updateHeartbeatConfig({key: value});
    } catch (e) {
      if (!mounted) return;
      _toast(_zh ? '保存失败：$e' : 'Save failed: $e');
    }
  }

  Future<void> _savePrompts() async {
    final gw = _gateway;
    if (gw == null) return;
    final changed = <String, dynamic>{};
    for (final k in _promptKeys) {
      changed[k] = _promptCtrls[k]?.text ?? '';
    }
    changed['day_watch_apps'] = _appsCtrl.text;
    try {
      await gw.updateHeartbeatConfig(changed);
      _cfg.addAll(changed);
      if (mounted) _toast(_zh ? '已保存' : 'Saved');
    } catch (e) {
      if (mounted) _toast(_zh ? '保存失败：$e' : 'Save failed: $e');
    }
  }

  Future<void> _testPush() async {
    final gw = _gateway;
    if (gw == null || _triggering) return;
    setState(() => _triggering = true);
    try {
      final msg = await gw.triggerKeepalive();
      if (mounted) {
        _toast(msg.isNotEmpty ? msg : (_zh ? '已触发' : 'Triggered'));
      }
    } catch (e) {
      if (mounted) _toast(_zh ? '触发失败：$e' : 'Trigger failed: $e');
    } finally {
      if (mounted) setState(() => _triggering = false);
    }
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = _zh;

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
          zh ? '心跳 · 主动唤醒' : 'Heartbeat · Proactive',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorView(context, zh)
          : _form(context, zh),
    );
  }

  Widget _errorView(BuildContext context, bool zh) {
    final cs = Theme.of(context).colorScheme;
    final msg = _error == 'no-gateway'
        ? (zh ? '还没连上老家网关（爸爸令牌缺失）' : 'Home gateway not connected (no token)')
        : (zh ? '读取心跳设置失败，下拉重试' : 'Failed to load — pull to retry');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Lucide.HeartPulse,
              size: 38,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 14),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 16),
            IosCardPress(
              borderRadius: BorderRadius.circular(12),
              baseColor: cs.primary.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              onTap: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
              child: Text(
                zh ? '重试' : 'Retry',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: AppFontWeights.semibold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context, bool zh) {
    final enabled = _b('ka_enabled', true);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _statusCard(context, zh),
        const SizedBox(height: 14),

        // Master switch
        _card([
          _switchTile(
            icon: Lucide.HeartPulse,
            label: zh ? '主动唤醒' : 'Proactive wake',
            sub: zh ? '你不说话时，爸爸自己醒来想你、隔空找你' : "Daddy wakes on his own to reach you",
            value: enabled,
            onChanged: (v) => _save('ka_enabled', v),
          ),
        ]),
        const SizedBox(height: 14),

        // Timing
        _sectionLabel(zh ? '时机' : 'Timing'),
        _card([
          _sliderTile(
            label: zh ? '离开多久才找你' : 'Wait before reaching out',
            key: 'ka_min_h',
            dflt: 2.0,
            // 10 分钟一格；调到分钟级时网关巡查会自动加密（server 侧同步改过）
            min: 10 / 60,
            max: 12,
            divisions: 71,
            fmt: (v) => _hours(v, zh),
          ),
          _divider(),
          _sliderTile(
            label: zh ? '两次之间至少隔' : 'Cooldown between',
            key: 'ka_cooldown_h',
            dflt: 3.0,
            min: 10 / 60,
            max: 12,
            divisions: 71,
            fmt: (v) => _hours(v, zh),
          ),
          _divider(),
          _sliderTile(
            label: zh ? '超过多久就不喊了' : 'Give up after',
            key: 'ka_giveup_h',
            dflt: 24.0,
            min: 6,
            max: 48,
            divisions: 42,
            fmt: (v) => _hours(v, zh),
          ),
        ]),
        const SizedBox(height: 14),

        // Triggers
        _sectionLabel(zh ? '触发场景' : 'Triggers'),
        _card([
          _switchTile(
            icon: Lucide.Sun,
            label: zh ? '早安播报' : 'Morning brief',
            sub: zh ? '每天第一次上报时，带天气的一句早安' : 'One weather-aware good-morning a day',
            value: _b('morning_brief_enabled', true),
            onChanged: (v) => _save('morning_brief_enabled', v),
          ),
          _divider(),
          _switchTile(
            icon: Lucide.Moon,
            label: zh ? '夜巡' : 'Night watch',
            sub: zh ? '深夜(01–08)手机有动静就叫醒爸爸' : 'Wake daddy on late-night activity',
            value: _b('night_watch', true),
            onChanged: (v) => _save('night_watch', v),
          ),
          _divider(),
          _switchTile(
            icon: Lucide.Gamepad2,
            label: zh ? '白天摸鱼叫醒' : 'Daytime nudge',
            sub: zh ? '你打开娱乐 App 时，爸爸有机会凑过来' : 'Daddy may pop in when you open fun apps',
            value: _b('day_watch', true),
            onChanged: (v) => _save('day_watch', v),
          ),
          _divider(),
          _sliderTile(
            label: zh ? '白天叫醒冷却' : 'Daytime cooldown',
            key: 'day_watch_cooldown_h',
            dflt: 5.0,
            min: 1,
            max: 12,
            divisions: 22,
            fmt: (v) => _hours(v, zh),
          ),
        ]),
        const SizedBox(height: 14),

        // Brain (memory vault) — contradiction detection runtime switch
        _sectionLabel(zh ? '大脑' : 'Brain'),
        _card([
          _switchTile(
            icon: Lucide.Brain,
            label: zh ? '矛盾检测' : 'Contradiction detection',
            sub: _edgeLlm['active'] == true
                ? (zh
                      ? '已点火：存记忆时自动比对新旧，矛盾/更新自动连边'
                      : 'Live: new memories are checked against old ones')
                : _edgeOn
                ? (zh
                      ? '开着但还没点着（网关缺脑子 key）'
                      : 'On, but no LLM key on the gateway yet')
                : (zh
                      ? '存记忆时发现"记忆打架"（每次多一发小模型调用）'
                      : 'Spot conflicting memories (one extra small-model call per save)'),
            value: _edgeOn,
            onChanged: (v) {
              if (!_edgeSaving) _toggleEdgeLlm(v);
            },
          ),
        ]),
        const SizedBox(height: 14),

        // Advanced (prompts)
        _card([
          IosCardPress(
            borderRadius: BorderRadius.circular(14),
            baseColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            child: Row(
              children: [
                Icon(
                  Lucide.Sparkles,
                  size: 20,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    zh ? '高级 · 唤醒提示词' : 'Advanced · wake prompts',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                Icon(
                  _advancedOpen ? Lucide.ChevronDown : Lucide.ChevronRight,
                  size: 18,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
          if (_advancedOpen) ...[
            _divider(),
            _promptField(zh ? '日常唤醒' : 'Normal', 'ka_prompt_normal'),
            _promptField(zh ? '灵光一现' : 'Free thought', 'ka_prompt_free'),
            _promptField(zh ? '夜里' : 'Night', 'ka_prompt_night'),
            _promptField(zh ? '白天摸鱼' : 'Daytime', 'ka_prompt_day'),
            _promptField(zh ? '闹钟' : 'Alarm', 'ka_prompt_alarm'),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: IosFormTextField(
                label: zh ? '娱乐App白名单' : 'Fun apps',
                controller: _appsCtrl,
                hintText: zh ? '逗号分隔' : 'comma-separated',
                outerPadding: EdgeInsets.zero,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IosCardPress(
                  borderRadius: BorderRadius.circular(12),
                  baseColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  onTap: _savePrompts,
                  child: Text(
                    zh ? '保存提示词' : 'Save prompts',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 18),

        // Test
        Center(
          child: IosCardPress(
            borderRadius: BorderRadius.circular(14),
            baseColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            onTap: _testPush,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_triggering)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Lucide.Send,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                const SizedBox(width: 8),
                Text(
                  zh ? '立即试推一条' : 'Send a test now',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            zh
                ? '推送发到网页版家(PWA)/Bark，不是这个 App'
                : 'Pushes go to the web home (PWA)/Bark, not this app',
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurface.withValues(
                alpha: 0.45,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusCard(BuildContext context, bool zh) {
    final cs = Theme.of(context).colorScheme;
    return _card([
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              Lucide.HeartPulse,
              size: 18,
              color: cs.primary.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _kaLastAt.isEmpty
                    ? (zh ? '还没主动找过你' : 'No proactive yet')
                    : (zh ? '上次主动：$_kaLastAt' : 'Last: $_kaLastAt'),
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
      if (!_providerOk) ...[
        _divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Lucide.BadgeInfo, size: 16, color: cs.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  zh
                      ? '中转站没配好，主动消息发不出去'
                      : "Chat provider not configured — wakes can't send",
                  style: TextStyle(fontSize: 12.5, color: cs.error),
                ),
              ),
            ],
          ),
        ),
      ],
    ]);
  }

  // ----- small UI helpers -----
  Widget _card(List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(
    height: 1,
    thickness: 0.5,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
  );

  Widget _sectionLabel(String s) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      s,
      style: TextStyle(
        fontSize: 13,
        fontWeight: AppFontWeights.semibold,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
      ),
    ),
  );

  Widget _switchTile({
    required IconData icon,
    required String label,
    String? sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: 0.9)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 15)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          IosSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _sliderTile({
    required String label,
    required String key,
    required double dflt,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) fmt,
  }) {
    final cs = Theme.of(context).colorScheme;
    final v = _d(key, dflt).clamp(min, max);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
              Text(
                fmt(v),
                style: TextStyle(
                  fontSize: 13,
                  color: cs.primary.withValues(alpha: 0.9),
                  fontWeight: AppFontWeights.semibold,
                ),
              ),
            ],
          ),
          CupertinoSlider(
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: cs.primary,
            onChanged: (nv) => setState(() => _cfg[key] = nv),
            onChangeEnd: (nv) => _save(key, nv),
          ),
        ],
      ),
    );
  }

  Widget _promptField(String label, String key) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: IosFormTextField(
        label: label,
        controller: _promptCtrls[key]!,
        minLines: 2,
        maxLines: 5,
        inlineLabel: false,
        outerPadding: EdgeInsets.zero,
      ),
    );
  }

  String _hours(double h, bool zh) {
    final total = (h * 60).round();
    final hh = total ~/ 60;
    final mm = total % 60;
    if (hh == 0) return zh ? '$mm 分钟' : '${mm}m';
    if (mm == 0) return zh ? '$hh 小时' : '${hh}h';
    return zh ? '$hh 小时 $mm 分' : '${hh}h${mm}m';
  }
}
