// CC bridge chat page.
//
// A standalone conversation channel into the home `cc` tmux session via
// [CcBridgeProvider]. Reuses the native [ChatMessageWidget] (fed in-memory
// ChatMessage objects mapped from CcChatRecord) so bubbles, markdown, the
// reasoning card, long-press/selection and animations are identical to the main
// chat — with action buttons hidden (null callbacks). Daddy can split one reply
// into several bubbles with `|||` (matches the home _tg_send_multi convention).
// The input bar attaches images/files (raw-bytes upload to /chat/upload).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import 'package:Kelivo/theme/app_font_weights.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/cc_bridge_provider.dart';
import '../../../core/services/cc/cc_bridge_models.dart';
import '../../../core/services/haptics.dart';
import '../../../features/chat/widgets/chat_message_widget.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import 'cc_bridge_page.dart';
import 'cc_terminal_page.dart';

class CcChatPage extends StatefulWidget {
  const CcChatPage({super.key});

  @override
  State<CcChatPage> createState() => _CcChatPageState();
}

class _CcChatPageState extends State<CcChatPage> {
  final TextEditingController _inputCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();
  int _lastCount = 0;
  bool _uploading = false;

  // Pending attachment: picked but not sent yet, so a caption can be typed and
  // the file + text go out together (one message), like the API window.
  Uint8List? _pendingBytes;
  String? _pendingName;
  bool _pendingIsImage = false;

  @override
  void initState() {
    super.initState();
    // Refresh the send/preview UI as the caption is typed (toggles send button).
    _inputCtl.addListener(_onInputChanged);
  }

  void _onInputChanged() => setState(() {});

  @override
  void dispose() {
    _inputCtl.removeListener(_onInputChanged);
    _inputCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollCtl.hasClients) return;
    _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
  }

  // Pin to the newest message: jump now, then once more after async content
  // (network images / lazily-loaded reasoning cards) has expanded the height.
  void _pinBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _scrollToBottom();
      });
    });
  }

  bool get _canSend =>
      !_uploading && (_inputCtl.text.trim().isNotEmpty || _pendingBytes != null);

  Future<void> _send() async {
    if (!_canSend) return;
    final l10n = AppLocalizations.of(context)!;
    final text = _inputCtl.text.trim();
    final bytes = _pendingBytes;
    final provider = context.read<CcBridgeProvider>();
    setState(() => _uploading = true);
    CcSendResult? res;
    try {
      if (bytes != null) {
        res = await provider.uploadFile(
          bytes,
          filename: _pendingName ?? 'file',
          text: text.isEmpty ? null : text,
        );
      } else {
        res = await provider.sendText(text);
      }
    } catch (_) {
      res = null;
    }
    if (!mounted) return;
    final accepted = res != null && (res.ok || res.agentUnreachable);
    setState(() {
      _uploading = false;
      if (accepted) {
        _inputCtl.clear();
        _pendingBytes = null;
        _pendingName = null;
        _pendingIsImage = false;
      }
    });
    if (res != null && res.agentUnreachable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ccBridgeAgentUnreachableToast)),
      );
    } else if (!accepted && bytes != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ccBridgeUploadFailed)),
      );
    }
  }

  Future<void> _showAttachSheet() async {
    Haptics.light();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AttachOption(
              icon: Lucide.Image,
              label: l10n.ccBridgeAttachPhoto,
              onTap: () => Navigator.of(ctx).pop('photo'),
            ),
            _AttachOption(
              icon: Lucide.Camera,
              label: l10n.ccBridgeAttachCamera,
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            _AttachOption(
              icon: Lucide.FileText,
              label: l10n.ccBridgeAttachFile,
              onTap: () => Navigator.of(ctx).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'photo':
        await _pickImage(ImageSource.gallery);
        break;
      case 'camera':
        await _pickImage(ImageSource.camera);
        break;
      case 'file':
        await _pickFile();
        break;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (x == null || !mounted) return;
    _stageAttachment(await x.readAsBytes(), x.name, isImage: true);
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(withData: false);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    _stageAttachment(
      await File(path).readAsBytes(),
      res!.files.single.name,
      isImage: false,
    );
  }

  // Hold the picked file as a pending preview; it sends together with the
  // typed caption when the send button is tapped.
  void _stageAttachment(Uint8List bytes, String name, {required bool isImage}) {
    if (!mounted) return;
    setState(() {
      _pendingBytes = bytes;
      _pendingName = name;
      _pendingIsImage = isImage;
    });
  }

  void _clearPending() {
    setState(() {
      _pendingBytes = null;
      _pendingName = null;
      _pendingIsImage = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<CcBridgeProvider>();

    // Pin to the newest message on open and whenever new records arrive.
    final count = provider.records.length;
    if (count != _lastCount) {
      _lastCount = count;
      _pinBottom();
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
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        actions: [
          if (provider.config.remoteControlEnabled)
            Tooltip(
              message: l10n.ccBridgeTerminalOpenButton,
              child: IosIconButton(
                icon: Lucide.ListTree,
                color: cs.onSurface,
                size: 20,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CcTerminalPage()),
                ),
              ),
            ),
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
            Icon(Lucide.Terminal, size: 40, color: cs.onSurface.withValues(alpha: 0.4)),
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
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtl,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: records.length,
                  itemBuilder: (_, i) => _ChatBubble(record: records[i]),
                ),
        ),
        _inputBar(context, provider),
      ],
    );
  }

  Widget _inputBar(BuildContext context, CcBridgeProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingBytes != null) _pendingPreview(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Tooltip(
                  message: l10n.ccBridgeAttachLabel,
                  child: IosIconButton(
                    icon: Lucide.Plus,
                    color: cs.onSurface.withValues(alpha: 0.75),
                    size: 22,
                    minSize: 42,
                    onTap: _uploading ? null : _showAttachSheet,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IosCardPress(
                  onTap: _canSend ? () => _send() : () {},
                  borderRadius: BorderRadius.circular(22),
                  baseColor:
                      _canSend ? cs.primary : cs.primary.withValues(alpha: 0.4),
                  padding: const EdgeInsets.all(10),
                  child: _uploading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : Icon(Lucide.ArrowUp, size: 20, color: cs.onPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingPreview(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _pendingIsImage && _pendingBytes != null
                ? Image.memory(
                    _pendingBytes!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 44,
                    height: 44,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                    child: Icon(
                      Lucide.FileText,
                      size: 20,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _pendingName ?? l10n.ccBridgeAttachmentLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          IosIconButton(
            icon: Lucide.X,
            size: 18,
            minSize: 36,
            color: cs.onSurface.withValues(alpha: 0.7),
            onTap: _uploading ? null : _clearPending,
          ),
        ],
      ),
    );
  }
}

/// A single CC record rendered via the native [ChatMessageWidget] (mapped to an
/// in-memory ChatMessage), so bubbles/markdown/reasoning/long-press match the
/// main chat exactly. Assistant turns eager-load thinking (once visible) into
/// the native reasoning card; a `|||` in an assistant reply splits it into
/// several bubbles. CC attachments render just above the bubble.
class _ChatBubble extends StatefulWidget {
  const _ChatBubble({required this.record});
  final CcChatRecord record;

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  static final RegExp _splitRe = RegExp(r'\s*\|\|\|\s*');
  bool _reasoningExpanded = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    if (r.isAssistant && (r.turnId ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<CcBridgeProvider>().ensureThinking(r.turnId!);
      });
    }
  }

  ChatMessage _msg(String role, String content, {String? reasoning}) {
    return ChatMessage(
      role: role,
      content: content,
      conversationId: 'cc-bridge',
      timestamp:
          DateTime.tryParse(widget.record.ts)?.toLocal() ?? DateTime.now(),
      reasoningText:
          (reasoning != null && reasoning.isNotEmpty) ? reasoning : null,
    );
  }

  // CC reuses the native bubble but: hides the action toolbar (showActions:false,
  // CC has no copy/regenerate/tts/translate), and for assistant turns borrows the
  // current assistant's name + avatar so daddy shows up identically to the main
  // chat (same name, same couple avatar) instead of the default "Assistant".
  Widget _native(ChatMessage m,
      {String? reasoningText, bool reasoningToggle = false}) {
    final isAssistant = m.role == 'assistant';
    final assistant =
        isAssistant ? context.watch<AssistantProvider>().currentAssistant : null;
    final hasReasoning = reasoningText != null && reasoningText.isNotEmpty;
    return ChatMessageWidget(
      message: m,
      showModelIcon: false,
      showTokenStats: false,
      showActions: false,
      useAssistantName: assistant != null,
      useAssistantAvatar: assistant != null,
      assistantName: assistant?.name,
      assistantAvatar: assistant?.avatar,
      reasoningText: reasoningText,
      reasoningExpanded: _reasoningExpanded,
      // Mark the reasoning as finished so the card is collapsible (without a
      // finishedAt it stays in the non-collapsible "loading" state).
      reasoningFinishedAt: hasReasoning
          ? (DateTime.tryParse(widget.record.ts)?.toLocal() ?? DateTime.now())
          : null,
      onToggleReasoning: reasoningToggle
          ? () => setState(() => _reasoningExpanded = !_reasoningExpanded)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.record;

    // System-style records (task/move) render centered and muted.
    if (!r.isUser && !r.isAssistant) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            r.text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
          ),
        ),
      );
    }

    final provider = context.watch<CcBridgeProvider>();
    final hasTurn = r.isAssistant && (r.turnId ?? '').isNotEmpty;
    final reasoning = hasTurn
        ? provider
            .thinkingFor(r.turnId!)
            .map((e) => e.thinking)
            .where((e) => e.isNotEmpty)
            .join('\n\n')
        : '';

    final children = <Widget>[];
    // CC attachments aren't part of ChatMessage; render them above the bubble.
    if (r.hasAttachment) {
      children.add(Align(
        alignment: r.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          child: _Attachment(record: r),
        ),
      ));
    }

    if (r.isUser) {
      if (r.text.isNotEmpty) children.add(_native(_msg('user', r.text)));
    } else if (r.text.isNotEmpty) {
      // Assistant: split on ||| into separate bubbles (max 8); reasoning on first.
      final segs = r.text
          .split(_splitRe)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final parts = segs.isEmpty ? <String>[r.text] : segs.take(8).toList();
      for (var i = 0; i < parts.length; i++) {
        final first = i == 0;
        children.add(_native(
          _msg('assistant', parts[i], reasoning: first ? reasoning : null),
          reasoningText: first && reasoning.isNotEmpty ? reasoning : null,
          reasoningToggle: first && hasTurn,
        ));
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// One row in the attachment bottom sheet (photo / camera / file).
class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurface),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: AppFontWeights.medium,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment({required this.record});
  final CcChatRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<CcBridgeProvider>();
    final url = provider.attachmentUrl(record.attachmentUrl!);
    final isImage = record.attachmentType == 'image';

    if (isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 120,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
              errorBuilder: (ctx, _, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Lucide.ImageOff,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    record.attachmentFilename ?? l10n.ccBridgeAttachmentLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Lucide.FileText, size: 16, color: cs.onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              record.attachmentFilename ?? l10n.ccBridgeAttachmentLabel,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
