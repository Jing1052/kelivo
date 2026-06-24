// CC bridge settings page.
//
// Configures the connection to the CcCompanion `apns-server` that fronts the
// home tmux `cc` session (see docs/CC_BRIDGE_INTEGRATION.md). All connection
// state lives in [CcBridgeProvider]; this page only edits/persists config and
// surfaces live status. The shared secret is a user-supplied local value and is
// never bundled in the repo.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/theme/app_font_weights.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/cc_bridge_provider.dart';
import '../../../core/services/cc/cc_bridge_models.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import 'cc_chat_page.dart';
import 'cc_terminal_page.dart';

class CcBridgePage extends StatefulWidget {
  const CcBridgePage({super.key});

  @override
  State<CcBridgePage> createState() => _CcBridgePageState();
}

class _CcBridgePageState extends State<CcBridgePage> {
  late final TextEditingController _endpointsCtl;
  late final TextEditingController _secretCtl;
  late final TextEditingController _sessionCtl;
  late final TextEditingController _pollCtl;
  late final TextEditingController _nameCtl;
  bool _enabled = false;
  bool _remoteControl = false;

  // Context window mode (session-watcher low/high). Null = not yet known /
  // endpoint unavailable; controls stay disabled until a value loads.
  String? _watcherMode; // 'low' | 'high' | null
  bool _watcherLoading = false;
  bool _watcherBusy = false; // a set request is in flight

  @override
  void initState() {
    super.initState();
    final cfg = context.read<CcBridgeProvider>().config;
    _endpointsCtl = TextEditingController(text: cfg.endpoints.join('\n'));
    _secretCtl = TextEditingController(text: cfg.sharedSecret);
    _sessionCtl = TextEditingController(text: cfg.session);
    _pollCtl = TextEditingController(text: '${cfg.pollIntervalMs}');
    _nameCtl = TextEditingController(text: cfg.displayName);
    _enabled = cfg.enabled;
    _remoteControl = cfg.remoteControlEnabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWatcherMode());
  }

  bool get _isZh =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

  Future<void> _loadWatcherMode() async {
    if (!mounted) return;
    setState(() => _watcherLoading = true);
    final mode = await context.read<CcBridgeProvider>().fetchWatcherMode();
    if (!mounted) return;
    setState(() {
      _watcherMode = mode;
      _watcherLoading = false;
    });
  }

  Future<void> _setWatcherMode(bool high) async {
    final target = high ? 'high' : 'low';
    if (_watcherBusy || _watcherMode == target) return;
    final previous = _watcherMode;
    setState(() {
      _watcherMode = target;
      _watcherBusy = true;
    });
    final ok = await context.read<CcBridgeProvider>().setWatcherMode(target);
    if (!mounted) return;
    setState(() {
      _watcherBusy = false;
      if (!ok) _watcherMode = previous; // rollback on failure
    });
    final msg = ok
        ? (_isZh
            ? (high ? '已切到大窗口档' : '已切到日常档')
            : (high ? 'Switched to large window' : 'Switched to everyday'))
        : (_isZh ? '切换失败，已回滚' : 'Switch failed, rolled back');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _endpointsCtl.dispose();
    _secretCtl.dispose();
    _sessionCtl.dispose();
    _pollCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  CcBridgeConfig _buildConfig() {
    final eps = _endpointsCtl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final session = _sessionCtl.text.trim();
    final poll = int.tryParse(_pollCtl.text.trim()) ?? 2500;
    return CcBridgeConfig(
      endpoints: eps,
      sharedSecret: _secretCtl.text.trim(),
      session: session.isEmpty ? 'cc' : session,
      pollIntervalMs: poll.clamp(1000, 30000).toInt(),
      remoteControlEnabled: _remoteControl,
      enabled: _enabled,
      displayName: _nameCtl.text.trim(),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    await context.read<CcBridgeProvider>().saveConfig(_buildConfig());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.ccBridgeSavedToast)),
    );
  }

  Future<void> _reconnect() async {
    // Persist current edits first so the reconnect uses them.
    await context.read<CcBridgeProvider>().saveConfig(_buildConfig());
    if (!mounted) return;
    await context.read<CcBridgeProvider>().reconnect();
  }

  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CcChatPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<CcBridgeProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.ccBridgePageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _statusCard(context, provider),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            children: [
              _switchRow(
                label: l10n.ccBridgeEnableLabel,
                description: l10n.ccBridgeEnableDescription,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: IosFormTextField(
                  label: l10n.ccBridgeEndpointsLabel,
                  controller: _endpointsCtl,
                  hintText: l10n.ccBridgeEndpointsHint,
                  minLines: 2,
                  maxLines: 4,
                  keyboardType: TextInputType.url,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: IosFormTextField(
                  label: l10n.ccBridgeSecretLabel,
                  controller: _secretCtl,
                  hintText: l10n.ccBridgeSecretHint,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: IosFormTextField(
                  label: l10n.ccBridgeSessionLabel,
                  controller: _sessionCtl,
                  hintText: 'cc',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: IosFormTextField(
                  label: l10n.ccBridgeDisplayNameLabel,
                  controller: _nameCtl,
                  hintText: l10n.ccBridgeDisplayNameHint,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: IosFormTextField(
                  label: l10n.ccBridgePollIntervalLabel,
                  controller: _pollCtl,
                  hintText: l10n.ccBridgePollIntervalHint,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            children: [
              _switchRow(
                label: l10n.ccBridgeRemoteControlLabel,
                description: l10n.ccBridgeRemoteControlDescription,
                value: _remoteControl,
                onChanged: (v) => setState(() => _remoteControl = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            children: [_watcherModeRow(context)],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: IosTileButton(
                  label: l10n.ccBridgeSaveButton,
                  icon: Lucide.Cable,
                  onTap: () => _save(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: IosTileButton(
                  label: l10n.ccBridgeReconnectButton,
                  icon: Lucide.RefreshCw,
                  onTap: () => _reconnect(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          IosTileButton(
            label: l10n.ccBridgeOpenChatButton,
            icon: Lucide.Terminal,
            onTap: _openChat,
          ),
          if (_remoteControl) ...[
            const SizedBox(height: 10),
            IosTileButton(
              label: l10n.ccBridgeTerminalOpenButton,
              icon: Lucide.ListTree,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CcTerminalPage()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, CcBridgeProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final (dotColor, label) = _statusDisplay(context, provider.connection);
    return _sectionCard(
      context,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface,
                      ),
                    ),
                    if ((provider.activeBaseUrl ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        provider.activeBaseUrl!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  (Color, String) _statusDisplay(
    BuildContext context,
    CcConnectionState state,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    switch (state) {
      case CcConnectionState.online:
        return (const Color(0xFF34C759), l10n.ccBridgeStatusOnline);
      case CcConnectionState.connecting:
        return (const Color(0xFFFF9500), l10n.ccBridgeStatusConnecting);
      case CcConnectionState.offline:
        return (const Color(0xFFFF3B30), l10n.ccBridgeStatusOffline);
      case CcConnectionState.unauthorized:
        return (const Color(0xFFFF3B30), l10n.ccBridgeStatusUnauthorized);
      case CcConnectionState.idle:
        return (cs.onSurface.withValues(alpha: 0.3), l10n.ccBridgeStatusIdle);
    }
  }

  // Context window mode control. Off = low (everyday / frequent rotation),
  // On = high (fill the 1M window before rotating). Disabled until a mode is
  // known (endpoint unavailable / pending home deployment) — degrades silently.
  Widget _watcherModeRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = _isZh;
    final available = _watcherMode != null;
    final isHigh = _watcherMode == 'high';

    final label = zh ? 'CC 上下文档位' : 'Context window';
    final subtitle = zh
        ? '大窗口=吃满大上下文(1M)再轮换；日常=勤轮换省上下文。家里 watcher ≤30s 生效。'
        : 'Large = fill the big context (1M) before rotating; everyday = '
            'rotate often to save context. Home watcher applies in ≤30s.';
    final String stateLine;
    if (_watcherLoading) {
      stateLine = zh ? '读取中…' : 'Loading…';
    } else if (!available) {
      stateLine = zh ? '未连上 / 家里待部署' : 'Not connected / pending';
    } else {
      stateLine = isHigh
          ? (zh ? '当前：大窗口(high)' : 'Current: large (high)')
          : (zh ? '当前：日常(low)' : 'Current: everyday (low)');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface.withValues(
                          alpha: available ? 1.0 : 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stateLine,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IosSwitch(
                value: isHigh,
                onChanged: (available && !_watcherBusy)
                    ? (v) => _setWatcherMode(v)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IosSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
