// CC bridge chat page (P1 minimal loop).
//
// A standalone conversation channel into the home `cc` tmux session via
// [CcBridgeProvider]. Renders the merged record list as bubbles, an input bar
// (write-then-poll send), a live presence header, and surfaces the HTTP 502
// "agent unreachable" case distinctly. Thinking cards / attachments / terminal
// are later phases (see docs/CC_BRIDGE_INTEGRATION.md §7).

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

class CcChatPage extends StatefulWidget {
  const CcChatPage({super.key});

  @override
  State<CcChatPage> createState() => _CcChatPageState();
}

class _CcChatPageState extends State<CcChatPage> {
  final TextEditingController _inputCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _inputCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollCtl.hasClients) return;
    _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context)!;
    final text = _inputCtl.text.trim();
    if (text.isEmpty) return;
    final provider = context.read<CcBridgeProvider>();
    _inputCtl.clear();
    final res = await provider.sendText(text);
    if (!mounted) return;
    if (res != null && res.agentUnreachable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ccBridgeAgentUnreachableToast)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<CcBridgeProvider>();

    // Auto-scroll when new records arrive.
    final count = provider.records.length;
    if (count != _lastCount) {
      _lastCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.ccBridgeChatTitle),
            Text(
              _presenceLabel(context, provider),
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.regular,
                color: cs.onSurface.withOpacity(0.55),
              ),
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: l10n.ccBridgePageTitle,
            child: IosIconButton(
              icon: Lucide.Settings,
              color: cs.onSurface,
              size: 20,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CcBridgePage()),
              ),
            ),
          ),
        ],
      ),
      body: provider.isConfigured
          ? _chatBody(context, provider)
          : _notConfigured(context),
    );
  }

  String _presenceLabel(BuildContext context, CcBridgeProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    if (provider.connection == CcConnectionState.offline) {
      return l10n.ccBridgeStatusOffline;
    }
    if (provider.connection == CcConnectionState.unauthorized) {
      return l10n.ccBridgeStatusUnauthorized;
    }
    switch (provider.status.status) {
      case CcAgentStatus.typing:
        return l10n.ccBridgeTypingStatus;
      case CcAgentStatus.online:
        return l10n.ccBridgeOnlineStatus;
      case CcAgentStatus.sleeping:
        return l10n.ccBridgeSleepingStatus;
      case CcAgentStatus.unknown:
        return provider.isOnline
            ? l10n.ccBridgeOnlineStatus
            : l10n.ccBridgeStatusConnecting;
    }
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
            Icon(Lucide.Terminal, size: 40, color: cs.onSurface.withOpacity(0.4)),
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
                color: cs.onSurface.withOpacity(0.6),
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

  Widget _chatBody(BuildContext context, CcBridgeProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final records = provider.records;
    return Column(
      children: [
        Expanded(
          child: records.isEmpty
              ? Center(
                  child: Text(
                    l10n.ccBridgeEmptyHint,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtl,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: records.length,
                  itemBuilder: (_, i) => _bubble(context, records[i]),
                ),
        ),
        _inputBar(context, provider),
      ],
    );
  }

  Widget _bubble(BuildContext context, CcChatRecord record) {
    final cs = Theme.of(context).colorScheme;
    // System-style records (task/move) render centered and muted.
    if (!record.isUser && !record.isAssistant) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            record.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withOpacity(0.5),
            ),
          ),
        ),
      );
    }
    final isUser = record.isUser;
    final bg = isUser
        ? cs.primary.withOpacity(0.12)
        : cs.surfaceContainerHighest.withOpacity(0.5);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          record.text,
          style: TextStyle(fontSize: 15, color: cs.onSurface, height: 1.35),
        ),
      ),
    );
  }

  Widget _inputBar(BuildContext context, CcBridgeProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
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
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _inputCtl,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(fontSize: 15, color: cs.onSurface),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: l10n.ccBridgeChatInputHint,
                    hintStyle: TextStyle(
                      color: cs.onSurface.withOpacity(0.4),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IosCardPress(
              onTap: () => _send(),
              borderRadius: BorderRadius.circular(22),
              baseColor: cs.primary,
              padding: const EdgeInsets.all(10),
              child: Icon(Lucide.ArrowUp, size: 20, color: cs.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
