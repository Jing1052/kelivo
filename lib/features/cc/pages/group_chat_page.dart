// Workgroup (group chat) page — the multi-agent code-review panel.
//
// One screen where the user and several home agents (CC daddy, Codex, …)
// share an append-only message stream with @mention routing: user assigns
// review work, agents report back, agents cross-dispatch each other. Rides the
// CC bridge connection ([CcBridgeProvider]'s active endpoint + shared secret)
// and talks to the same apns-server's `/group/*` endpoints, so there is
// nothing new to configure. Polling runs only while this page is open; the
// poll's `viewer` param doubles as the user's presence heartbeat.
//
// The roster (members, avatars, tmux mapping) lives server-side in
// `agents_config.json` at home — the app renders whatever the server says.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import 'package:Kelivo/theme/app_font_weights.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/cc_bridge_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/cc/cc_bridge_client.dart';
import '../../../core/services/cc/group_chat_client.dart';
import '../../../core/services/cc/group_chat_models.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/chat_backdrop.dart';
import '../../../shared/widgets/markdown_with_highlight.dart';
import 'cc_bridge_page.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key});

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

enum _GroupPhase { connecting, ready, notConfigured, unsupported, error }

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _inputCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();

  GroupChatClient? _client;
  Timer? _pollTimer;
  _GroupPhase _phase = _GroupPhase.connecting;
  String? _errorText;

  List<GroupMember> _members = const <GroupMember>[];
  Map<String, GroupAgentState> _agentStates = const {};
  String _senderId = 'amian';
  final List<GroupRecord> _records = <GroupRecord>[];
  final Set<String> _seenIds = <String>{};
  String? _cursor;
  bool _sending = false;

  // Pending attachments (picked but not sent), mirroring the CC chat input.
  final List<_Pending> _pending = <_Pending>[];

  @override
  void initState() {
    super.initState();
    _inputCtl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _client?.dispose();
    _inputCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  GroupMember? _memberById(String id) {
    for (final m in _members) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _connect() async {
    final ccp = context.read<CcBridgeProvider>();
    if (!ccp.isConfigured) {
      setState(() => _phase = _GroupPhase.notConfigured);
      return;
    }
    setState(() {
      _phase = _GroupPhase.connecting;
      _errorText = null;
    });
    // Ride the CC bridge's endpoint discovery: connect it first if needed.
    if (ccp.activeBaseUrl == null) {
      await ccp.connect();
    }
    final base = ccp.activeBaseUrl;
    if (!mounted) return;
    if (base == null) {
      setState(() {
        _phase = _GroupPhase.error;
        _errorText = null; // plain offline, no detail needed
      });
      return;
    }
    _client?.dispose();
    final client = GroupChatClient(
      baseUrl: base,
      sharedSecret: ccp.config.sharedSecret,
    );
    _client = client;
    try {
      final roster = await client.roster();
      final history = await client.history(limit: 200);
      if (!mounted) return;
      setState(() {
        _members = roster.members;
        _agentStates = roster.agentStates;
        _senderId = roster.humanSenderId;
        _records.clear();
        _seenIds.clear();
        _merge(history);
        _cursor = _records.isNotEmpty ? _records.last.ts : null;
        _phase = _GroupPhase.ready;
      });
      _startPolling();
    } on CcBridgeException catch (e) {
      if (!mounted) return;
      setState(() {
        // 404 = home apns-server predates the /group/* endpoints.
        _phase = e.statusCode == 404
            ? _GroupPhase.unsupported
            : _GroupPhase.error;
        _errorText = e.statusCode == 404 ? null : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _GroupPhase.error;
        _errorText = e.toString();
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final ms = context
        .read<CcBridgeProvider>()
        .config
        .pollIntervalMs
        .clamp(1000, 30000)
        .toInt();
    _pollTimer = Timer.periodic(Duration(milliseconds: ms), (_) => _poll());
  }

  Future<void> _poll() async {
    final c = _client;
    if (c == null || _phase != _GroupPhase.ready) return;
    try {
      final res = await c.poll(since: _cursor, viewer: _senderId);
      if (!mounted) return;
      setState(() {
        _merge(res.records);
        if ((res.lastTs ?? '').isNotEmpty) _cursor = res.lastTs;
        _agentStates = res.agentStates;
      });
    } catch (_) {
      // transient poll failure: keep the timer for auto-recovery
    }
  }

  void _merge(List<GroupRecord> incoming) {
    var added = false;
    for (final r in incoming) {
      if (_seenIds.add(r.id)) {
        _records.add(r);
        added = true;
      }
    }
    if (added) _records.sort((a, b) => a.ts.compareTo(b.ts));
  }

  bool get _canSend =>
      !_sending && (_inputCtl.text.trim().isNotEmpty || _pending.isNotEmpty);

  Future<void> _send() async {
    final c = _client;
    if (c == null || !_canSend) return;
    final l10n = AppLocalizations.of(context)!;
    final text = _inputCtl.text.trim();
    final pend = List<_Pending>.of(_pending);
    setState(() => _sending = true);
    var ok = true;
    try {
      if (pend.isEmpty) {
        final res = await c.send(
          text,
          senderId: _senderId,
          clientMsgId: UniqueKey().toString(),
        );
        ok = res.ok || res.deduped;
        if (res.record != null) _merge(<GroupRecord>[res.record!]);
      } else {
        // One upload per attachment; caption rides on the last one.
        for (var i = 0; i < pend.length; i++) {
          final isLast = i == pend.length - 1;
          final res = await c.upload(
            pend[i].bytes,
            filename: pend[i].name,
            senderId: _senderId,
            text: (isLast && text.isNotEmpty) ? text : null,
          );
          if (res.record != null) _merge(<GroupRecord>[res.record!]);
          if (!res.ok) {
            ok = false;
            break;
          }
        }
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        _inputCtl.clear();
        _pending.clear();
      }
    });
    if (ok) {
      unawaited(_poll());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.groupChatSendFailed)),
      );
    }
  }

  // ---- @mention picker ----

  Future<void> _showMentionSheet() async {
    Haptics.light();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final candidates =
        _members.where((m) => m.isAgent && m.canReply).toList(growable: false);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.groupChatMentionSheetTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
            for (final m in candidates)
              IosCardPress(
                borderRadius: BorderRadius.circular(12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                onTap: () => Navigator.of(ctx).pop(m.id),
                child: Row(
                  children: [
                    _MemberAvatar(member: m, size: 30),
                    const SizedBox(width: 12),
                    Text(
                      m.displayName,
                      style: const TextStyle(fontSize: 15.5),
                    ),
                    if ((m.model ?? '').isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        m.model!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            IosCardPress(
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              onTap: () => Navigator.of(ctx).pop('all'),
              child: Row(
                children: [
                  Icon(Lucide.Users, size: 20, color: cs.onSurface),
                  const SizedBox(width: 12),
                  Text(
                    l10n.groupChatMentionAll,
                    style: const TextStyle(fontSize: 15.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _insertMention(picked);
  }

  void _insertMention(String id) {
    final t = _inputCtl.text;
    final sel = _inputCtl.selection;
    final at = (sel.isValid ? sel.start : t.length).clamp(0, t.length).toInt();
    // Pad with a space when inserting right after a non-space character, so
    // the server's `@id` token regex still matches.
    final needsSpace = at > 0 && t[at - 1].trim().isNotEmpty;
    final inserted = '${needsSpace ? ' ' : ''}@$id ';
    _inputCtl.value = TextEditingValue(
      text: t.substring(0, at) + inserted + t.substring(at),
      selection: TextSelection.collapsed(offset: at + inserted.length),
    );
  }

  // ---- attachments ----

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
            _SheetOption(
              icon: Lucide.Image,
              label: l10n.ccBridgeAttachPhoto,
              onTap: () => Navigator.of(ctx).pop('photo'),
            ),
            _SheetOption(
              icon: Lucide.Camera,
              label: l10n.ccBridgeAttachCamera,
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            _SheetOption(
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
        final xs = await ImagePicker().pickMultiImage(imageQuality: 90);
        if (!mounted) return;
        for (final x in xs) {
          _pending.add(_Pending(await x.readAsBytes(), x.name, true));
        }
        if (mounted) setState(() {});
        break;
      case 'camera':
        final x =
            await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
        if (x == null || !mounted) return;
        final bytes = await x.readAsBytes();
        if (!mounted) return;
        setState(() => _pending.add(_Pending(bytes, x.name, true)));
        break;
      case 'file':
        final res = await FilePicker.platform
            .pickFiles(withData: false, allowMultiple: true);
        if (res == null || !mounted) return;
        for (final f in res.files) {
          final path = f.path;
          if (path == null) continue;
          _pending.add(_Pending(await File(path).readAsBytes(), f.name, false));
        }
        if (mounted) setState(() {});
        break;
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final onlineAgents =
        _agentStates.values.where((s) => s.online).length;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
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
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.groupChatTitle),
            if (_phase == _GroupPhase.ready)
              Text(
                l10n.groupChatOnlineCount(onlineAgents),
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
          Positioned.fill(
            child: ChatBackdrop(
              rawPath: context.watch<SettingsProvider>().homeBackgroundActive,
              maskStrength:
                  context.watch<SettingsProvider>().chatBackgroundMaskStrength,
            ),
          ),
          Positioned.fill(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (_phase) {
      case _GroupPhase.connecting:
        return const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      case _GroupPhase.notConfigured:
        return _hintPane(
          context,
          icon: Lucide.Cable,
          title: l10n.ccBridgeNotConfiguredTitle,
          hint: l10n.ccBridgeNotConfiguredHint,
          buttonLabel: l10n.ccBridgeOpenSettingsButton,
          onButton: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CcBridgePage()),
          ),
        );
      case _GroupPhase.unsupported:
        return _hintPane(
          context,
          icon: Lucide.ServerOff,
          title: l10n.groupChatUnsupportedTitle,
          hint: l10n.groupChatUnsupportedHint,
        );
      case _GroupPhase.error:
        return _hintPane(
          context,
          icon: Lucide.WifiOff,
          title: l10n.ccBridgeStatusOffline,
          hint: _errorText ?? '',
          buttonLabel: l10n.groupChatRetryButton,
          onButton: _connect,
        );
      case _GroupPhase.ready:
        return Column(
          children: [
            _memberStrip(context),
            Expanded(
              child: _records.isEmpty
                  ? Center(
                      child: Text(
                        l10n.groupChatEmptyHint,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtl,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: _records.length,
                      itemBuilder: (_, i) {
                        final r = _records[_records.length - 1 - i];
                        return _MessageRow(
                          key: ValueKey(r.id),
                          record: r,
                          member: _memberById(r.senderId),
                          isMine: r.senderId == _senderId,
                          client: _client!,
                        );
                      },
                    ),
            ),
            _inputBar(context),
          ],
        );
    }
  }

  Widget _hintPane(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String hint,
    String? buttonLabel,
    VoidCallback? onButton,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface,
              ),
            ),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            if (buttonLabel != null && onButton != null) ...[
              const SizedBox(height: 20),
              IosTileButton(
                label: buttonLabel,
                icon: Lucide.RefreshCw,
                onTap: onButton,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Horizontal roster strip: avatar + name + online dot; typing pulses the
  /// status text under the name.
  Widget _memberStrip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final agents = _members.where((m) => m.isAgent).toList(growable: false);
    if (agents.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        itemCount: agents.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final m = agents[i];
          final st = _agentStates[m.id];
          final online = st?.online ?? false;
          final typing = st?.isTyping ?? false;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _MemberAvatar(member: m, size: 34, dimmed: !online),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: online
                            ? const Color(0xFF22C55E)
                            : cs.onSurface.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                typing ? l10n.groupChatTyping : m.displayName,
                style: TextStyle(
                  fontSize: 10.5,
                  color: typing
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: online ? 0.75 : 0.4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
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
                    onTap: _sending ? null : _showAttachSheet,
                  ),
                ),
                Tooltip(
                  message: l10n.groupChatMentionSheetTitle,
                  child: IosIconButton(
                    icon: Lucide.AtSign,
                    color: cs.onSurface.withValues(alpha: 0.75),
                    size: 22,
                    minSize: 42,
                    onTap: _sending ? null : _showMentionSheet,
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
                        hintText: l10n.groupChatInputHint,
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
                  child: _sending
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
                    onTap: _sending
                        ? null
                        : () => setState(() => _pending.removeAt(i)),
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

/// Avatar bubble for a roster member: initials over the member's color.
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.member,
    required this.size,
    this.dimmed = false,
  });

  final GroupMember member;
  final double size;
  final bool dimmed;

  static const Map<String, Color> _palette = {
    'orange': Color(0xFFF97316),
    'blue': Color(0xFF3B82F6),
    'green': Color(0xFF22C55E),
    'purple': Color(0xFFA855F7),
    'slate': Color(0xFF64748B),
    'neutral': Color(0xFF9CA3AF),
  };

  @override
  Widget build(BuildContext context) {
    final base = _palette[member.color] ?? _palette['neutral']!;
    final color = dimmed ? base.withValues(alpha: 0.45) : base;
    final label = member.avatar.isNotEmpty
        ? member.avatar
        : (member.displayName.isNotEmpty ? member.displayName[0] : '?');
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dimmed ? 0.16 : 0.22),
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: AppFontWeights.semibold,
          color: color,
        ),
      ),
    );
  }
}

/// One group message: others left-aligned with avatar + name + model badge,
/// the user's own right-aligned. Body renders markdown with code highlight —
/// review reports are markdown-heavy. Non-chat records (task/ship/…) carry a
/// small type chip next to the sender name.
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    super.key,
    required this.record,
    required this.member,
    required this.isMine,
    required this.client,
  });

  final GroupRecord record;
  final GroupMember? member;
  final bool isMine;
  final GroupChatClient client;

  String _typeLabel(AppLocalizations l10n) {
    switch (record.messageType) {
      case 'task':
        return l10n.groupChatTypeTask;
      case 'ship':
        return l10n.groupChatTypeShip;
      case 'block':
        return l10n.groupChatTypeBlock;
      case 'progress':
        return l10n.groupChatTypeProgress;
      case 'decision':
        return l10n.groupChatTypeDecision;
      default:
        return record.messageType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final maxW = MediaQuery.of(context).size.width * 0.80;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMine
            ? cs.primary.withValues(alpha: 0.14)
            : cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (record.hasAttachment) _AttachmentView(record: record, client: client),
          if (record.text.isNotEmpty)
            MarkdownWithCodeHighlight(
              text: record.text,
              baseStyle: TextStyle(fontSize: 14.5, color: cs.onSurface),
            ),
        ],
      ),
    );

    if (isMine) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(alignment: Alignment.centerRight, child: bubble),
      );
    }

    final name = member?.displayName ?? record.senderId;
    final model = member?.model ?? record.senderModel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (member != null)
            _MemberAvatar(member: member!, size: 30)
          else
            _MemberAvatar(
              member: GroupMember(
                id: record.senderId,
                displayName: name,
                kind: 'agent',
              ),
              size: 30,
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: AppFontWeights.medium,
                          color: cs.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    if ((model ?? '').isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        model!,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                    if (!record.isChat) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _typeLabel(l10n),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: AppFontWeights.medium,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                bubble,
              ],
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

class _AttachmentView extends StatelessWidget {
  const _AttachmentView({required this.record, required this.client});

  final GroupRecord record;
  final GroupChatClient client;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final url = client.attachmentUrl(record.attachmentUrl!);
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
              // /attachments/ is auth-gated — pass the token or it 401s.
              headers: client.attachmentHeaders,
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
          Icon(Lucide.FileText,
              size: 16, color: cs.onSurface.withValues(alpha: 0.7)),
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

/// One row in the attachment bottom sheet.
class _SheetOption extends StatelessWidget {
  const _SheetOption({
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
