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
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/cc/cc_bridge_models.dart';
import '../../../core/services/haptics.dart';
import '../../../features/chat/widgets/chat_message_widget.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/chat_backdrop.dart';
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
  bool _uploading = false;

  // Pending attachments: picked but not sent yet (images + files), so several
  // can go together with a caption — like the native chat input.
  final List<_Pending> _pending = <_Pending>[];

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

  bool get _canSend =>
      !_uploading && (_inputCtl.text.trim().isNotEmpty || _pending.isNotEmpty);

  Future<void> _send() async {
    if (!_canSend) return;
    final l10n = AppLocalizations.of(context)!;
    final text = _inputCtl.text.trim();
    final pend = List<_Pending>.of(_pending);
    final provider = context.read<CcBridgeProvider>();
    setState(() => _uploading = true);
    CcSendResult? res;
    bool hadFailure = false;
    try {
      if (pend.isEmpty) {
        res = await provider.sendText(text);
      } else {
        // One upload per attachment (the bridge takes one file per request);
        // the caption rides on the last one so daddy sees images + words.
        for (var i = 0; i < pend.length; i++) {
          final isLast = i == pend.length - 1;
          res = await provider.uploadFile(
            pend[i].bytes,
            filename: pend[i].name,
            text: (isLast && text.isNotEmpty) ? text : null,
          );
          final ok = res != null && (res.ok || res.agentUnreachable);
          if (!ok) {
            hadFailure = true;
            break;
          }
        }
      }
    } catch (_) {
      res = null;
      hadFailure = true;
    }
    if (!mounted) return;
    final accepted = res != null && (res.ok || res.agentUnreachable);
    setState(() {
      _uploading = false;
      if (accepted && !hadFailure) {
        _inputCtl.clear();
        _pending.clear();
      }
    });
    if (res != null && res.agentUnreachable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ccBridgeAgentUnreachableToast)),
      );
    } else if (hadFailure && pend.isNotEmpty) {
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
    if (source == ImageSource.gallery) {
      // Gallery: allow picking several photos at once.
      final xs = await ImagePicker().pickMultiImage(imageQuality: 90);
      if (xs.isEmpty || !mounted) return;
      for (final x in xs) {
        _addPending(await x.readAsBytes(), x.name, isImage: true);
      }
      return;
    }
    final x = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (x == null || !mounted) return;
    _addPending(await x.readAsBytes(), x.name, isImage: true);
  }

  Future<void> _pickFile() async {
    final res =
        await FilePicker.platform.pickFiles(withData: false, allowMultiple: true);
    if (res == null || !mounted) return;
    for (final f in res.files) {
      final path = f.path;
      if (path == null) continue;
      _addPending(await File(path).readAsBytes(), f.name, isImage: false);
    }
  }

  // Hold a picked file as a pending preview; several can stack up and send
  // together with the typed caption when the send button is tapped.
  void _addPending(Uint8List bytes, String name, {required bool isImage}) {
    if (!mounted) return;
    setState(() => _pending.add(_Pending(bytes, name, isImage)));
  }

  void _removePendingAt(int i) {
    setState(() {
      if (i >= 0 && i < _pending.length) _pending.removeAt(i);
    });
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
      body: Stack(
        children: [
          // CC window follows the home background (read-only here).
          Positioned.fill(
            child: ChatBackdrop(
              rawPath: context.watch<SettingsProvider>().homeBackgroundActive,
              maskStrength:
                  context.watch<SettingsProvider>().chatBackgroundMaskStrength,
            ),
          ),
          Positioned.fill(
            child: provider.isConfigured
                ? _chatBody(context, provider)
                : _notConfigured(context),
          ),
        ],
      ),
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
              // reverse:true keeps the list anchored at the newest message:
              // it opens pinned to the bottom and stays there when the keyboard
              // pushes the viewport up — matching the native chat feel.
              : ListView.builder(
                  controller: _scrollCtl,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: records.length,
                  itemBuilder: (_, i) {
                    final r = records[records.length - 1 - i];
                    return _ChatBubble(key: ValueKey(r.ts), record: r);
                  },
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
          if (_pending.isNotEmpty) _pendingPreview(context),
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

  // Horizontal tray of pending attachments (image thumbs + file chips), each
  // removable — mirrors the native chat input's multi-attachment tray.
  Widget _pendingPreview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        itemCount: _pending.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final p = _pending[i];
          return SizedBox(
            width: 56,
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: p.isImage
                      ? Image.memory(p.bytes,
                          width: 56, height: 56, fit: BoxFit.cover)
                      : Container(
                          width: 56,
                          height: 56,
                          color:
                              cs.surfaceContainerHighest.withValues(alpha: 0.6),
                          child: Icon(Lucide.FileText,
                              size: 22,
                              color: cs.onSurface.withValues(alpha: 0.7)),
                        ),
                ),
                Positioned(
                  right: -6,
                  top: -6,
                  child: GestureDetector(
                    onTap: _uploading ? null : () => _removePendingAt(i),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: cs.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Icon(Lucide.X,
                          size: 13, color: cs.onSurface.withValues(alpha: 0.8)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One picked-but-not-sent attachment.
class _Pending {
  const _Pending(this.bytes, this.name, this.isImage);
  final Uint8List bytes;
  final String name;
  final bool isImage;
}

/// A single CC record rendered via the native [ChatMessageWidget] (mapped to an
/// in-memory ChatMessage), so bubbles/markdown/reasoning/long-press match the
/// main chat exactly. Assistant turns eager-load thinking (once visible) into
/// the native reasoning card; a `|||` in an assistant reply splits it into
/// several bubbles. CC attachments render just above the bubble.
class _ChatBubble extends StatefulWidget {
  const _ChatBubble({super.key, required this.record});
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
  // CC has no copy/regenerate/tts/translate), and for assistant turns shows the
  // CC daddy's name (the dedicated CC name if set, else the current assistant's)
  // plus the current assistant's avatar (the couple avatar), so daddy never
  // shows up as the default "Assistant".
  Widget _native(ChatMessage m,
      {String? reasoningText, bool reasoningToggle = false}) {
    final isAssistant = m.role == 'assistant';
    final assistant =
        isAssistant ? context.watch<AssistantProvider>().daddyAssistant : null;
    final ccName = isAssistant
        ? context.watch<CcBridgeProvider>().ccDisplayName.trim()
        : '';
    final displayName = ccName.isNotEmpty ? ccName : assistant?.name;
    final hasIdentity = displayName != null && displayName.isNotEmpty;
    final hasReasoning = reasoningText != null && reasoningText.isNotEmpty;
    return ChatMessageWidget(
      message: m,
      showModelIcon: false,
      showTokenStats: false,
      showActions: false,
      useAssistantName: hasIdentity,
      useAssistantAvatar: hasIdentity,
      assistantName: displayName,
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

bool _looksLikeImage(String? s) {
  if (s == null) return false;
  final l = s.toLowerCase();
  return l.endsWith('.jpg') ||
      l.endsWith('.jpeg') ||
      l.endsWith('.png') ||
      l.endsWith('.gif') ||
      l.endsWith('.webp') ||
      l.endsWith('.heic') ||
      l.endsWith('.bmp');
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
    // Treat as image when the server tagged it OR the name/url has an image
    // extension (server may omit attachment_type).
    final isImage = record.attachmentType == 'image' ||
        _looksLikeImage(record.attachmentUrl) ||
        _looksLikeImage(record.attachmentFilename);

    if (isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Image.network(
              url,
              // /attachments/ is auth-gated — pass the bridge token or it 401s
              // and we fall back to showing the filename.
              headers: provider.attachmentHeaders,
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
