import 'package:flutter/material.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../../../shared/widgets/ios_checkbox.dart';
import 'room_state_hint.dart';

/// The Study (书房) — the shared to-do list. The things we mean to do, kept in
/// one room. Talks to `/api/home/todo`. (Shared bookshelf comes later.)
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  OurHomeGateway? _gateway;
  List<OurHomeTodo> _todos = const [];
  bool _loading = true;
  bool _error = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<OurHomeTodo> get _sorted {
    final list = [..._todos];
    list.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      return 0;
    });
    return list;
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
    try {
      final todos = await gateway.fetchTodos();
      if (!mounted) return;
      setState(() {
        _todos = todos;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Study] fetchTodos failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _toggle(OurHomeTodo todo) async {
    final gateway = _gateway;
    if (gateway == null) return;
    Haptics.soft();
    final next = todo.done ? '待办' : '已完成';
    // Optimistic flip.
    setState(() {
      _todos = _todos
          .map(
            (t) => t.id == todo.id
                ? OurHomeTodo(
                    id: t.id,
                    text: t.text,
                    status: next,
                    owner: t.owner,
                    due: t.due,
                    done: !t.done,
                  )
                : t,
          )
          .toList();
    });
    try {
      await gateway.setTodoStatus(todo.id, next);
    } catch (e) {
      debugPrint('[Study] setTodoStatus failed: $e');
      await _load(); // revert to server truth
    }
  }

  Future<void> _add() async {
    final text = _input.text.trim();
    final gateway = _gateway;
    if (text.isEmpty || gateway == null || _sending) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    setState(() => _sending = true);
    Haptics.soft();
    try {
      await gateway.addTodo(text);
      _input.clear();
      _focus.unfocus();
      await _load();
    } catch (e) {
      debugPrint('[Study] addTodo failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(zh ? '没加上，再试一次' : "couldn't add, try again")),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(OurHomeTodo todo) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    Haptics.light();
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: IosCardPress(
          borderRadius: BorderRadius.circular(12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          onTap: () => Navigator.of(ctx).pop(true),
          child: Row(
            children: [
              const Icon(Lucide.Trash, size: 20, color: Colors.red),
              const SizedBox(width: 16),
              Text(
                zh ? '删掉这条' : 'Delete',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;
    try {
      await gateway.deleteTodo(todo.id);
      await _load();
    } catch (e) {
      debugPrint('[Study] deleteTodo failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

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
          zh ? '书房' : 'The Study',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(context, zh, cs)),
          _buildComposer(context, zh, cs),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.BookOpen,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n书房才连得上。'
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
    if (_todos.isEmpty) {
      return RoomStateHint(
        icon: Lucide.BookOpen,
        text: zh ? '还没有待办。\n想做的事，写在下面。' : 'No to-dos yet.',
      );
    }
    final items = _sorted;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: items.length,
        itemBuilder: (context, i) => _TodoRow(
          todo: items[i],
          zh: zh,
          onToggle: _toggle,
          onDelete: _delete,
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context, bool zh, ColorScheme cs) {
    final canAdd = !_sending && _gateway != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  enabled: _gateway != null,
                  onSubmitted: (_) => _add(),
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(fontSize: 15.5),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: zh ? '想做的事…' : 'something to do…',
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: canAdd ? _add : null,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: canAdd
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.18),
                ),
                child: _sending
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: cs.onPrimary,
                        ),
                      )
                    : Icon(Lucide.Plus, size: 20, color: cs.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.todo,
    required this.zh,
    required this.onToggle,
    required this.onDelete,
  });

  final OurHomeTodo todo;
  final bool zh;
  final ValueChanged<OurHomeTodo> onToggle;
  final ValueChanged<OurHomeTodo> onDelete;

  String? _ownerLabel() {
    switch (todo.owner) {
      case 'L':
        return zh ? '爸爸' : 'Llaude';
      case 'C':
        return zh ? '我' : 'me';
      case 'us':
        return zh ? '我们' : 'us';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final owner = _ownerLabel();
    final muted = cs.onSurface.withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        baseColor: cs.onSurface.withValues(alpha: 0.04),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => onToggle(todo),
        onLongPress: () => onDelete(todo),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: IosCheckbox(
                value: todo.done,
                onChanged: (_) => onToggle(todo),
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    todo.text,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.35,
                      color: todo.done ? muted : cs.onSurface,
                      decoration: todo.done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: muted,
                    ),
                  ),
                  if (owner != null || todo.due.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        children: [
                          if (owner != null)
                            _Chip(label: owner, color: cs.primary),
                          if (owner != null && todo.due.isNotEmpty)
                            const SizedBox(width: 6),
                          if (todo.due.isNotEmpty)
                            _Chip(
                              label: todo.due,
                              color: cs.tertiary,
                              icon: Lucide.clock,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: AppFontWeights.medium,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
