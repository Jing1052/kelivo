import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/cc_bridge_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../assistant/widgets/assistant_select_sheet.dart';
import '../widgets/assistant_avatar.dart';
import '../../cc/pages/cc_chat_page.dart';
import '../../cc/pages/group_chat_page.dart';
import 'home_page.dart';

/// Full-screen conversation list — the root of the Still Here "Chat" tab.
///
/// Tapping a conversation pushes [HomePage] as a full-screen chat detail
/// (covering the bottom dock, mirroring our web home where entering a chat
/// hides the chrome). The "+" button starts a fresh conversation.
class ConversationListPage extends StatelessWidget {
  const ConversationListPage({super.key});

  void _openConversation(BuildContext context, String id) {
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => HomePage(
          initialConversationId: id,
          onBack: () => Navigator.of(ctx).maybePop(),
        ),
      ),
    );
  }

  void _openCc(BuildContext context) {
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CcChatPage()),
    );
  }

  void _openGroup(BuildContext context) {
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GroupChatPage()),
    );
  }

  Future<void> _startNewConversation(BuildContext context) async {
    Haptics.soft();
    final assistantProvider = context.read<AssistantProvider>();
    final assistants = assistantProvider.assistants;

    // Pick which assistant to chat with first. With a single assistant there is
    // nothing to choose, so open directly.
    if (assistants.length > 1) {
      final selectedId = await showAssistantMoveSelector(context);
      if (selectedId == null || !context.mounted) return; // cancelled
      await assistantProvider.setCurrentAssistant(selectedId);
      if (!context.mounted) return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => HomePage(
          startNewConversation: true,
          onBack: () => Navigator.of(ctx).maybePop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final chatService = context.watch<ChatService>();
    final assistantProvider = context.watch<AssistantProvider>();

    // Resolve each conversation's own assistant. Falls back to the current
    // assistant when the conversation has no assistantId or it no longer exists.
    Assistant? assistantFor(Conversation c) {
      final id = c.assistantId;
      if (id != null) {
        final a = assistantProvider.getById(id);
        if (a != null) return a;
      }
      return assistantProvider.currentAssistant;
    }

    final all = chatService.getAllConversations();
    final pinned = all.where((c) => c.isPinned).toList();
    final others = all.where((c) => !c.isPinned).toList();
    final groups = _groupByDate(context, others);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: Text(
          l10n.stillHereTabChat,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        actions: [
          Tooltip(
            message: l10n.stillHereNewChat,
            child: IosIconButton(
              icon: Lucide.SquarePen,
              size: 22,
              minSize: 44,
              onTap: () => _startNewConversation(context),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: !chatService.initialized
          // 初始化未完成时先留白，别闪一下「暂无对话」空状态（init 完成会 notify 刷新）。
          ? const SizedBox.shrink()
          : all.isEmpty
          // 空列表也保留顶部 CC 入口：CC 是独立通道，不该随对话清零（如重装）而消失。
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Column(
                    children: [
                      _CcEntryTile(onTap: () => _openCc(context)),
                      _GroupEntryTile(onTap: () => _openGroup(context)),
                    ],
                  ),
                ),
                Expanded(
                  child: _EmptyState(
                    onNewChat: () => _startNewConversation(context),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                _CcEntryTile(onTap: () => _openCc(context)),
                _GroupEntryTile(onTap: () => _openGroup(context)),
                if (pinned.isNotEmpty) ...[
                  _SectionHeader(label: l10n.sideDrawerPinnedLabel),
                  for (final c in pinned)
                    _ConversationTile(
                      conversation: c,
                      assistant: assistantFor(c),
                      pinned: true,
                      onTap: () => _openConversation(context, c.id),
                    ),
                ],
                for (final g in groups) ...[
                  _SectionHeader(label: g.label),
                  for (final c in g.items)
                    _ConversationTile(
                      conversation: c,
                      assistant: assistantFor(c),
                      pinned: false,
                      onTap: () => _openConversation(context, c.id),
                    ),
                ],
              ],
            ),
      backgroundColor: cs.surface,
    );
  }

  List<_DateGroup> _groupByDate(
    BuildContext context,
    List<Conversation> source,
  ) {
    final map = <DateTime, List<Conversation>>{};
    for (final c in source) {
      final d = DateTime(c.updatedAt.year, c.updatedAt.month, c.updatedAt.day);
      map.putIfAbsent(d, () => []).add(c);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys)
        _DateGroup(
          label: _dateLabel(context, k),
          items: map[k]!..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
        ),
    ];
  }

  String _dateLabel(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final aDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(aDay).inDays;
    final l10n = AppLocalizations.of(context)!;
    if (diff == 0) return l10n.sideDrawerDateToday;
    if (diff == 1) return l10n.sideDrawerDateYesterday;
    final pattern = now.year == date.year
        ? l10n.sideDrawerDateShortPattern
        : l10n.sideDrawerDateFullPattern;
    return DateFormat(pattern).format(date);
  }
}

class _DateGroup {
  _DateGroup({required this.label, required this.items});
  final String label;
  final List<Conversation> items;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: AppFontWeights.semibold,
          color: cs.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.assistant,
    required this.pinned,
    required this.onTap,
  });

  final Conversation conversation;
  final Assistant? assistant;
  final bool pinned;
  final VoidCallback onTap;

  Future<void> _showActions(BuildContext context) async {
    Haptics.light();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<String>(
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
              icon: Lucide.Pencil,
              label: l10n.sideDrawerMenuRename,
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            _SheetOption(
              icon: conversation.isPinned ? Lucide.PinOff : Lucide.Pin,
              label: conversation.isPinned
                  ? l10n.sideDrawerMenuUnpin
                  : l10n.sideDrawerMenuPin,
              onTap: () => Navigator.of(ctx).pop('pin'),
            ),
            _SheetOption(
              icon: Lucide.Trash,
              label: l10n.sideDrawerMenuDelete,
              destructive: true,
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final chatService = context.read<ChatService>();
    switch (action) {
      case 'rename':
        await _rename(context, chatService);
        break;
      case 'pin':
        await chatService.togglePinConversation(conversation.id);
        break;
      case 'delete':
        await _confirmDelete(context, chatService);
        break;
    }
  }

  Future<void> _rename(BuildContext context, ChatService chatService) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: conversation.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.sideDrawerMenuRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.sideDrawerRenameHint),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.sideDrawerCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.sideDrawerOK),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final title = controller.text.trim();
      if (title.isNotEmpty) {
        await chatService.renameConversation(conversation.id, title);
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ChatService chatService,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.sideDrawerMenuDelete),
        content: Text('${l10n.sideDrawerMenuDelete} "${conversation.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.sideDrawerCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await chatService.deleteConversation(conversation.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final title = conversation.title.trim().isEmpty
        ? l10n.chatServiceDefaultConversationTitle
        : conversation.title.trim();
    final time = DateFormat('HH:mm').format(conversation.updatedAt);
    final assistantName = (assistant?.name ?? '').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        onTap: onTap,
        onLongPress: () => _showActions(context),
        child: Row(
          children: [
            AssistantAvatar(assistant: assistant, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Icon(
                            Lucide.Pin,
                            size: 13,
                            color: cs.primary.withValues(alpha: 0.8),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (assistantName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      assistantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              time,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entry tile pinned at the top of the chat list that opens the CC bridge chat
/// (the home tmux `cc` agent), distinct from gateway conversations.
class _CcEntryTile extends StatelessWidget {
  const _CcEntryTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final assistant = context.watch<AssistantProvider>().daddyAssistant;
    final ccp = context.watch<CcBridgeProvider>();
    final ccName = ccp.ccDisplayName.trim();
    // CC 最后活动时间：用最新一条记录的 ts（ISO 串），和下面普通会话行一样显示 HH:mm。
    // 记录还没拉到（没开过 CC / 未连上）时就不显示时间。
    final ccRecords = ccp.records;
    final lastTs = ccRecords.isNotEmpty
        ? DateTime.tryParse(ccRecords.last.ts)?.toLocal()
        : null;
    final timeStr = lastTs != null ? DateFormat('HH:mm').format(lastTs) : '';
    final title = ccName.isNotEmpty
        ? ccName
        : ((assistant?.name ?? '').trim().isNotEmpty
            ? assistant!.name.trim()
            : l10n.ccBridgeChatTitle);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            // Same couple/daddy avatar as the API chat entries, so CC is unified.
            AssistantAvatar(assistant: assistant, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.ccBridgeChatTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (timeStr.isNotEmpty) ...[
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              Lucide.ChevronRight,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entry tile for the multi-agent workgroup (code-review group chat), sitting
/// under the CC tile. Same server as the CC bridge, so no per-tile status —
/// the page itself resolves connection state on open.
class _GroupEntryTile extends StatelessWidget {
  const _GroupEntryTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Lucide.Users, size: 20, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.groupChatTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.groupChatEntrySubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Lucide.ChevronRight,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? Colors.red : cs.onSurface;
    return IosCardPress(
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: AppFontWeights.medium,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNewChat});
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Lucide.MessageCircle,
            size: 64,
            color: cs.onSurface.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 18),
          IosCardPress(
            baseColor: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            onTap: onNewChat,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Lucide.SquarePen, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.stillHereNewChat,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.primary,
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
