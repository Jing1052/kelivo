// CC bridge terminal page (P3: terminal mirror + slash commands).
//
// Mirrors the home `cc` tmux pane via /tmux/capture (periodic snapshot), sends
// literal text / whitelisted special keys via /tmux/send, and exposes the
// /chain/* slash commands (list / new / stop / clear / restart, plus /compact
// routed through tmux/send). All but "clear" require the server to run with
// allow_remote_control=true; the provider enforces that gate. See
// docs/CC_BRIDGE_INTEGRATION.md §5/§7.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/theme/app_font_weights.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/cc_bridge_provider.dart';
import '../../../core/services/cc/cc_bridge_models.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import 'cc_bridge_page.dart';

class CcTerminalPage extends StatefulWidget {
  const CcTerminalPage({super.key, this.embedded = false});

  /// When true, render as a bottom-nav tab: no back button, and a
  /// not-configured placeholder pointing to settings instead of a bare terminal.
  final bool embedded;

  @override
  State<CcTerminalPage> createState() => _CcTerminalPageState();
}

class _CcTerminalPageState extends State<CcTerminalPage> {
  // Terminal keycaps are universal technical tokens, intentionally not
  // localized. (glyph shown, wire key name sent to /tmux/send).
  static const List<(String, String)> _specialKeys = <(String, String)>[
    ('Esc', 'Escape'),
    ('Tab', 'Tab'),
    ('↑', 'Up'),
    ('↓', 'Down'),
    ('⏎', 'Enter'),
    ('^C', 'C-c'),
    ('^L', 'C-l'),
  ];

  final TextEditingController _inputCtl = TextEditingController();
  final ScrollController _termScroll = ScrollController();
  String _content = '';
  bool _refreshing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final ms = context
        .read<CcBridgeProvider>()
        .config
        .pollIntervalMs
        .clamp(1500, 30000)
        .toInt();
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _inputCtl.dispose();
    _termScroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    // lines=1200：默认 120 行只够一屏多点，往上翻立刻到头（小猫 2026-07-02 报的）。
    // 家里 tmux history-limit 默认 2000，抓 1200 行安全；纯文本快照，流量可忽略。
    final cap = await context
        .read<CcBridgeProvider>()
        .captureTerminal(lines: 1200);
    if (!mounted) {
      _refreshing = false;
      return;
    }
    _refreshing = false;
    if (cap != null) {
      // 只在用户本来就贴着底部时才自动滚到底——用户往上翻历史时别把他拽回去 (Bug4)。
      // 容差 40px：差一点点也算"在底部"，但明显往上翻了就停掉 autoscroll。
      final atBottom = !_termScroll.hasClients ||
          (_termScroll.position.maxScrollExtent - _termScroll.position.pixels) <=
              40;
      setState(() => _content = cap.content);
      if (atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_termScroll.hasClients) {
            _termScroll.jumpTo(_termScroll.position.maxScrollExtent);
          }
        });
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_termScroll.hasClients) {
        _termScroll.jumpTo(_termScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _runAction(Future<bool> Function() action) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await action();
    if (!mounted) return;
    if (!ok) {
      _toast(l10n.ccBridgeTerminalActionFailed);
      return;
    }
    // Pull a fresh frame after the action lands.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _refresh();
    // 用户主动发了东西 → 强制回到底部看结果（即便他刚才往上翻过；timer 刷新不会这样拽他）。
    _jumpToBottom();
  }

  Future<void> _sendInput() async {
    final text = _inputCtl.text;
    if (text.trim().isEmpty) return;
    final provider = context.read<CcBridgeProvider>();
    _inputCtl.clear();
    await _runAction(() => provider.sendKeys(keys: text, enter: true));
  }

  Future<void> _showSessions() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<CcBridgeProvider>();
    final sessions = await provider.listSessions();
    if (!mounted) return;
    if (sessions == null || sessions.sessions.isEmpty) {
      _toast(l10n.ccBridgeChainNoSessions);
      return;
    }
    final sid = await showDialog<String>(
      context: context,
      builder: (ctx) => _SessionPickerDialog(sessions: sessions),
    );
    if (sid == null || !mounted) return;
    await _runAction(() => provider.switchSession(sid));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<CcBridgeProvider>();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.embedded
            ? null
            : Tooltip(
                message: l10n.settingsPageBackButton,
                child: IosIconButton(
                  icon: Lucide.ArrowLeft,
                  color: cs.onSurface,
                  size: 22,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.ccBridgeTerminalTitle),
            Text(
              provider.config.session,
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.regular,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: l10n.ccBridgeTerminalRefresh,
            child: IosIconButton(
              icon: Lucide.RefreshCw,
              color: cs.onSurface,
              size: 20,
              onTap: _refresh,
            ),
          ),
        ],
      ),
      body: provider.isConfigured
          ? Column(
              children: [
                Expanded(child: _terminalView(context)),
                _commandBar(context, provider),
                _keysRow(context, provider),
                _inputBar(context, provider),
              ],
            )
          : _notConfigured(context),
    );
  }

  Widget _notConfigured(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Lucide.Terminal,
              size: 40,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.ccBridgeNotConfiguredTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.ccBridgeNotConfiguredHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            IosTileButton(
              label: l10n.ccBridgeOpenSettingsButton,
              icon: Lucide.Cable,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CcBridgePage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _terminalView(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: _content.trim().isEmpty
          ? Center(
              child: Text(
                l10n.ccBridgeTerminalEmptyHint,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          : SingleChildScrollView(
              controller: _termScroll,
              child: SelectableText(
                _content,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
    );
  }

  Widget _commandBar(BuildContext context, CcBridgeProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    final rc = provider.remoteControlEnabled;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          IosTileButton(
            label: l10n.ccBridgeChainList,
            icon: Lucide.ListTree,
            enabled: rc,
            onTap: _showSessions,
          ),
          IosTileButton(
            label: l10n.ccBridgeChainNew,
            icon: Lucide.Plus,
            enabled: rc,
            onTap: () => _runAction(provider.newSession),
          ),
          IosTileButton(
            label: l10n.ccBridgeChainStop,
            icon: Lucide.Square,
            enabled: rc,
            onTap: () => _runAction(provider.abortSession),
          ),
          IosTileButton(
            label: l10n.ccBridgeChainClear,
            icon: Lucide.Eraser,
            onTap: () => _runAction(provider.clearSession),
          ),
          IosTileButton(
            label: l10n.ccBridgeChainRestart,
            icon: Lucide.RotateCcw,
            enabled: rc,
            onTap: () => _runAction(provider.restartSession),
          ),
          IosTileButton(
            label: l10n.ccBridgeChainCompact,
            icon: Lucide.Terminal,
            enabled: rc,
            onTap: () => _runAction(
              () => provider.sendKeys(keys: '/compact', enter: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keysRow(BuildContext context, CcBridgeProvider provider) {
    final rc = provider.remoteControlEnabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (glyph, name) in _specialKeys)
            _KeyCap(
              label: glyph,
              enabled: rc,
              onTap: () => _runAction(() => provider.sendKeys(key: name)),
            ),
        ],
      ),
    );
  }

  Widget _inputBar(BuildContext context, CcBridgeProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final rc = provider.remoteControlEnabled;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _inputCtl,
                  enabled: rc,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendInput(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: l10n.ccBridgeTerminalInputHint,
                    hintStyle: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IosCardPress(
              onTap: rc ? _sendInput : () {},
              borderRadius: BorderRadius.circular(22),
              baseColor: rc ? cs.primary : cs.surfaceContainerHighest,
              padding: const EdgeInsets.all(10),
              child: Icon(
                Lucide.CornerDownLeft,
                size: 20,
                color: rc ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small monospace keycap button for sending a single special key.
class _KeyCap extends StatelessWidget {
  const _KeyCap({
    required this.label,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      onTap: enabled ? onTap : () {},
      borderRadius: BorderRadius.circular(10),
      baseColor: cs.surfaceContainerHighest.withValues(alpha: enabled ? 0.5 : 0.25),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: cs.onSurface.withValues(alpha: enabled ? 0.85 : 0.35),
        ),
      ),
    );
  }
}

/// Dialog listing tmux/claude sessions; returns the chosen sid via pop.
class _SessionPickerDialog extends StatelessWidget {
  const _SessionPickerDialog({required this.sessions});

  final CcChainSessions sessions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.ccBridgeChainSwitchTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in sessions.sessions)
            ListTile(
              dense: true,
              title: Text(
                s.sid,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              trailing: s.active
                  ? Text(
                      l10n.ccBridgeChainActiveLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.primary,
                      ),
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(s.sid),
            ),
        ],
      ),
    );
  }
}
