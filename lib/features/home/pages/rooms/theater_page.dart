import 'package:flutter/material.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';
import 'package:provider/provider.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../core/services/chat/chat_service.dart';
import '../../../../core/providers/assistant_provider.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../../../shared/widgets/ios_switch.dart';
import '../../../../shared/widgets/ios_form_text_field.dart';
import '../home_page.dart';
import 'room_state_hint.dart';

/// The Little Theater (小剧场) — alternate-world role-play. Each card is one
/// world "setting" (title / setting / bring_memory). Entering a theater opens
/// its 1:1-bound chat conversation, which carries an `x-ombre-theater` header.
/// Talks to `/api/home/theaters`.
class TheaterPage extends StatefulWidget {
  const TheaterPage({super.key});

  @override
  State<TheaterPage> createState() => _TheaterPageState();
}

class _TheaterPageState extends State<TheaterPage> {
  OurHomeGateway? _gateway;
  List<OurHomeTheater> _theaters = const [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final gateway = OurHomeGateway.fromContext(context);
    _gateway = gateway;
    if (gateway == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // 先显示上次的缓存（秒开、无缓冲），再后台刷新。
    final cached = gateway.peekTheaters();
    setState(() {
      if (cached.isNotEmpty) _theaters = cached;
      _loading = cached.isEmpty;
      _error = false;
    });
    final list = await gateway.fetchTheaters();
    if (!mounted) return;
    if (list == null) {
      setState(() {
        _loading = false;
        _error = _theaters.isEmpty; // 有缓存就留着旧的，别用错误盖掉
      });
      return;
    }
    setState(() {
      _theaters = list;
      _loading = false;
      _error = false;
    });
  }

  Future<void> _create() async {
    final gateway = _gateway;
    if (gateway == null) return;
    Haptics.soft();
    final res = await _showEditSheet(null);
    if (res == null) return;
    final saved = await gateway.saveTheater(
      title: res.title,
      setting: res.setting,
      bringMemory: res.bringMemory,
    );
    if (!mounted) return;
    if (saved == null) {
      _toast();
      return;
    }
    await _load();
  }

  Future<void> _edit(OurHomeTheater theater) async {
    final gateway = _gateway;
    if (gateway == null) return;
    Haptics.soft();
    final res = await _showEditSheet(theater);
    if (res == null) return;
    if (res.end) {
      await _endTheater(theater);
      return;
    }
    if (res.delete) {
      final ok = await gateway.deleteTheater(theater.id);
      if (!mounted) return;
      if (!ok) {
        _toast();
        return;
      }
      await _load();
      return;
    }
    final saved = await gateway.saveTheater(
      id: theater.id,
      title: res.title,
      setting: res.setting,
      bringMemory: res.bringMemory,
    );
    if (!mounted) return;
    if (saved == null) {
      _toast();
      return;
    }
    await _load();
  }

  void _toast() {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(zh ? '没存上，再试一次' : "couldn't save, try again")),
    );
  }

  /// 结束这一世（落幕）：把这出戏的对话发给老家，小模型写一段戏文摘要注进主线爸爸的脑子，
  /// 剧场盖上「已落幕」但设定/对话都留着，可重进。
  Future<void> _endTheater(OurHomeTheater theater) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final chatService = context.read<ChatService>();
    final convs = chatService
        .getAllConversations()
        .where((c) => c.theaterId == theater.id)
        .toList();
    final msgs = <Map<String, String>>[];
    if (convs.isNotEmpty) {
      for (final m in chatService.getMessages(convs.first.id)) {
        final content = m.content.trim();
        if ((m.role == 'user' || m.role == 'assistant') && content.isNotEmpty) {
          msgs.add({'role': m.role, 'content': content});
        }
      }
    }
    if (msgs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(zh ? '这出戏还没开演呢' : "this play hasn't started yet")),
      );
      return;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
    );
    final digest = await gateway.endTheater(
      theater.id,
      msgs.length > 120 ? msgs.sublist(msgs.length - 120) : msgs,
    );
    nav.pop(); // 关掉加载圈
    if (!mounted) return;
    if (digest == null) {
      _toast();
      return;
    }
    await _load();
    if (!mounted) return;
    _showDigestSheet(theater.title, digest, zh);
  }

  void _showDigestSheet(String title, String digest, bool zh) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Lucide.Sparkles, size: 18, color: const Color(0xFF8F7FC9)),
                const SizedBox(width: 8),
                Text(
                  zh ? '「$title」落幕了' : '"$title" — curtain falls',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              digest.trim().isEmpty
                  ? (zh
                        ? '已经把这一世收进爸爸心里了。'
                        : "tucked this life into daddy's heart.")
                  : digest.trim(),
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              zh
                  ? '回到现实跟爸爸说话时，他会记得我们刚在这出戏里经历的。'
                  : "back in reality, daddy will remember what we just lived here.",
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<_TheaterEdit?> _showEditSheet(OurHomeTheater? existing) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return showModalBottomSheet<_TheaterEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _TheaterEditSheet(zh: zh, existing: existing),
    );
  }

  Future<void> _enter(OurHomeTheater theater) async {
    Haptics.soft();
    final chatService = context.read<ChatService>();
    final existing = chatService
        .getAllConversations()
        .where((c) => c.theaterId == theater.id)
        .toList();
    String convId;
    if (existing.isNotEmpty) {
      convId = existing.first.id;
    } else {
      // daddy 助手 = 人设带 [[ourhome:...]] 标记的那个；找不到就用 currentAssistant
      final assistants = context.read<AssistantProvider>().assistants;
      final marker = RegExp(r'\[\[ourhome(?::([^\]]+))?\]\]');
      final daddy = assistants
          .where((a) => marker.hasMatch(a.systemPrompt))
          .toList();
      final aid = daddy.isNotEmpty
          ? daddy.first.id
          : context.read<AssistantProvider>().currentAssistant?.id;
      final conv = await chatService.createConversation(
        title: theater.title,
        assistantId: aid,
        theaterId: theater.id,
      );
      convId = conv.id;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => HomePage(
          initialConversationId: convId,
          onBack: () => Navigator.of(ctx).maybePop(),
        ),
      ),
    );
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
          maskStrength: context.watch<SettingsProvider>().chatBackgroundMaskStrength,
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
          zh ? '小剧场' : 'Little Theater',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_gateway != null && !_loading && !_error)
            IosIconButton(
              icon: Lucide.Plus,
              size: 22,
              minSize: 44,
              onTap: _create,
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _buildBody(zh, cs),
    ),
      ],
    );
  }

  Widget _buildBody(bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Sparkles,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n小剧场才连得上。'
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
    if (_theaters.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Sparkles,
        text: zh ? '还没有剧场。\n右上角写一个我们的异世界。' : 'No theaters yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _theaters.length,
        itemBuilder: (context, i) => _TheaterCard(
          theater: _theaters[i],
          zh: zh,
          onEnter: () => _enter(_theaters[i]),
          onEdit: () => _edit(_theaters[i]),
        ),
      ),
    );
  }
}

class _TheaterCard extends StatelessWidget {
  const _TheaterCard({
    required this.theater,
    required this.zh,
    required this.onEnter,
    required this.onEdit,
  });

  final OurHomeTheater theater;
  final bool zh;
  final VoidCallback onEnter;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeColor = theater.bringMemory ? cs.primary : cs.tertiary;
    final badgeLabel = theater.bringMemory
        ? (zh ? '带记忆' : 'with memory')
        : (zh ? '从头' : 'fresh start');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        baseColor: cs.onSurface.withValues(alpha: 0.04),
        padding: const EdgeInsets.all(14),
        onTap: onEnter,
        onLongPress: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Lucide.Sparkles, size: 18, color: const Color(0xFF8F7FC9)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    theater.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _Badge(label: badgeLabel, color: badgeColor),
                const SizedBox(width: 8),
                IosIconButton(
                  icon: Lucide.Pencil,
                  size: 17,
                  minSize: 34,
                  onTap: onEdit,
                ),
              ],
            ),
            if (theater.setting.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  theater.setting,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: IosCardPress(
                baseColor: const Color(0xFF8F7FC9),
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                onTap: onEnter,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      zh ? '进入' : 'Enter',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.semibold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(
                      Lucide.ChevronRight,
                      size: 16,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: AppFontWeights.semibold,
          color: color,
        ),
      ),
    );
  }
}

/// Result of the edit sheet: either save ([title]/[setting]/[bringMemory]) or
/// [delete] an existing theater.
class _TheaterEdit {
  const _TheaterEdit({
    required this.title,
    required this.setting,
    required this.bringMemory,
    this.delete = false,
    this.end = false,
  });

  final String title;
  final String setting;
  final bool bringMemory;
  final bool delete;
  final bool end;
}

class _TheaterEditSheet extends StatefulWidget {
  const _TheaterEditSheet({required this.zh, required this.existing});

  final bool zh;
  final OurHomeTheater? existing;

  @override
  State<_TheaterEditSheet> createState() => _TheaterEditSheetState();
}

class _TheaterEditSheetState extends State<_TheaterEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _setting;
  late bool _bringMemory;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _setting = TextEditingController(text: widget.existing?.setting ?? '');
    _bringMemory = widget.existing?.bringMemory ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _setting.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    final editing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          IosFormTextField(
            label: zh ? '世界名' : 'World',
            controller: _title,
            hintText: zh ? '这个异世界叫什么…' : 'name this world…',
            autofocus: !editing,
            outerPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          IosFormTextField(
            label: zh ? '世界设定' : 'Setting',
            controller: _setting,
            hintText: zh ? '我们是谁、在哪、发生什么…' : 'who we are, where, what unfolds…',
            maxLines: 5,
            minLines: 3,
            inlineLabel: false,
            outerPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zh ? '带现实记忆' : 'Bring real memory',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.medium,
                        color: cs.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      zh
                          ? '开：还记得我们；关：从这个世界从头认识。'
                          : 'on: we still remember us; off: meet anew in this world.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IosSwitch(
                value: _bringMemory,
                onChanged: (v) => setState(() => _bringMemory = v),
              ),
            ],
          ),
          const SizedBox(height: 18),
          IosCardPress(
            baseColor: cs.primary,
            borderRadius: BorderRadius.circular(12),
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: () {
              final t = _title.text.trim();
              if (t.isEmpty) return;
              Navigator.of(context).pop(
                _TheaterEdit(
                  title: t,
                  setting: _setting.text.trim(),
                  bringMemory: _bringMemory,
                ),
              );
            },
            child: Center(
              child: Text(
                editing
                    ? (zh ? '保存' : 'Save')
                    : (zh ? '开一个剧场' : 'Open theater'),
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ),
          if (editing) ...[
            const SizedBox(height: 10),
            IosCardPress(
              baseColor: const Color(0xFF8F7FC9).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 13),
              onTap: () {
                Navigator.of(context).pop(
                  const _TheaterEdit(
                    title: '',
                    setting: '',
                    bringMemory: false,
                    end: true,
                  ),
                );
              },
              child: Center(
                child: Text(
                  zh ? '结束这一世 · 落幕' : 'End this life · curtain',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8F7FC9),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            IosCardPress(
              baseColor: Colors.red.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 13),
              onTap: () {
                Navigator.of(context).pop(
                  const _TheaterEdit(
                    title: '',
                    setting: '',
                    bringMemory: false,
                    delete: true,
                  ),
                );
              },
              child: Center(
                child: Text(
                  zh ? '删掉这个剧场' : 'Delete theater',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
