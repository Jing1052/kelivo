import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../../../shared/widgets/ios_checkbox.dart';
import '../../widgets/still_glass.dart';
import 'book_reader_page.dart';
import 'room_state_hint.dart';

/// The Study (书房) — the shared to-do list and the shared bookshelf. Talks to
/// `/api/home/todo` and `/api/home/books`.
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
  List<OurHomeBook> _books = const [];
  List<ReadingEntry> _reading = const [];
  bool _loading = true;
  bool _error = false;
  bool _sending = false;
  bool _uploading = false;
  int _tab = 0; // 0 = todos, 1 = bookshelf

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

  List<OurHomeTodo> get _sortedTodos {
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
    // Instant: seed from on-device cache, then refresh from the server.
    final ct = gateway.peekList('/api/home/todo', OurHomeTodo.fromJson);
    final cbk = gateway.peekList('/api/home/books', OurHomeBook.fromJson);
    final cr = gateway.peekReadingShelf();
    if ((ct.isNotEmpty || cbk.isNotEmpty || cr.isNotEmpty) && mounted) {
      setState(() {
        _todos = ct;
        _books = cbk;
        _reading = cr;
        _loading = false;
      });
    }
    // Refresh the three lists independently: one failing fetch must not veto
    // the other two (a broken shelf/books call used to freeze todos on stale
    // cache with no visible error). null = that fetch failed, keep old data.
    final results = await Future.wait<dynamic>([
      softFetch(gateway.fetchTodos(), 'study todos'),
      softFetch(gateway.fetchBooks(), 'study books'),
      softFetch(gateway.fetchReadingShelf(), 'study reading shelf'),
    ]);
    if (!mounted) return;
    final todos = results[0] as List<OurHomeTodo>?;
    final books = results[1] as List<OurHomeBook>?;
    final reading = results[2] as List<ReadingEntry>?;
    setState(() {
      if (todos != null) _todos = todos;
      if (books != null) _books = books;
      if (reading != null) _reading = reading;
      _loading = false;
      _error = todos == null && books == null && reading == null;
    });
  }

  Future<void> _toggle(OurHomeTodo todo) async {
    final gateway = _gateway;
    if (gateway == null) return;
    Haptics.soft();
    final next = todo.done ? '待办' : '已完成';
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
      await _load();
    }
  }

  Future<void> _cycleBook(OurHomeBook b) async {
    final gateway = _gateway;
    if (gateway == null) return;
    Haptics.soft();
    const order = ['want', 'reading', 'read'];
    final next = order[(order.indexOf(b.status) + 1) % order.length];
    setState(() {
      _books = _books
          .map(
            (x) => x.id == b.id
                ? OurHomeBook(
                    id: x.id,
                    status: next,
                    title: x.title,
                    author: x.author,
                    quote: x.quote,
                  )
                : x,
          )
          .toList();
    });
    try {
      await gateway.setBookStatus(b.id, next);
    } catch (e) {
      debugPrint('[Study] setBookStatus failed: $e');
      await _load();
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

  Future<void> _addBook() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final res = await showModalBottomSheet<_NewBook>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddBookSheet(zh: zh),
    );
    if (res == null) return;
    try {
      await gateway.addBook(res.title, res.author, res.quote);
      await _load();
    } catch (e) {
      debugPrint('[Study] addBook failed: $e');
    }
  }

  // ---- Reading shelf (一起读 · whole-text books) ----

  void _openReader(ReadingEntry e) {
    final gateway = _gateway;
    if (gateway == null) return;
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookReaderPage(
          gateway: gateway,
          bookId: e.id,
          title: e.title,
        ),
      ),
    );
  }

  /// Import a whole txt book. Primary path: pick a .txt file (bytes read in
  /// memory, decoded as UTF-8). The sheet also offers a paste-text fallback for
  /// when the file picker can't reach the file.
  Future<void> _importBook() async {
    final gateway = _gateway;
    if (gateway == null || _uploading) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final choice = await showModalBottomSheet<_ImportChoice>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IosCardPress(
              borderRadius: BorderRadius.zero,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              onTap: () => Navigator.of(ctx).pop(_ImportChoice.file),
              child: Row(
                children: [
                  const Icon(Lucide.Upload, size: 20),
                  const SizedBox(width: 16),
                  Text(
                    zh ? '选一个 txt 文件' : 'Pick a .txt file',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IosCardPress(
              borderRadius: BorderRadius.zero,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              onTap: () => Navigator.of(ctx).pop(_ImportChoice.paste),
              child: Row(
                children: [
                  const Icon(Lucide.FileText, size: 20),
                  const SizedBox(width: 16),
                  Text(
                    zh ? '粘贴整本正文' : 'Paste the whole text',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _ImportChoice.file) {
      await _importFromFile(gateway, zh);
    } else {
      await _importFromPaste(gateway, zh);
    }
  }

  Future<void> _importFromFile(OurHomeGateway gateway, bool zh) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      withData: true,
    );
    if (res == null || res.files.isEmpty || !mounted) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      _toast(zh ? '没读到文件内容' : "couldn't read the file");
      return;
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      // Not valid UTF-8 — keep the bytes we can, rather than failing outright.
      text = utf8.decode(bytes, allowMalformed: true);
    }
    if (text.trim().isEmpty) {
      _toast(zh ? '这个文件是空的' : 'that file is empty');
      return;
    }
    // Use the filename (without .txt) as the default title.
    var title = f.name;
    if (title.toLowerCase().endsWith('.txt')) {
      title = title.substring(0, title.length - 4);
    }
    await _doUpload(gateway, title.trim(), text, zh);
  }

  Future<void> _importFromPaste(OurHomeGateway gateway, bool zh) async {
    final res = await showModalBottomSheet<_PastedBook>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PasteBookSheet(zh: zh),
    );
    if (res == null || !mounted) return;
    await _doUpload(gateway, res.title, res.text, zh);
  }

  Future<void> _doUpload(
    OurHomeGateway gateway,
    String title,
    String text,
    bool zh,
  ) async {
    setState(() => _uploading = true);
    Haptics.soft();
    try {
      await gateway.uploadBook(title.isEmpty ? (zh ? '未命名' : 'Untitled') : title, text);
      await _load();
    } catch (e) {
      debugPrint('[Study] uploadBook failed: $e');
      _toast(zh ? '没传上去，再试一次' : "couldn't upload, try again");
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteReading(ReadingEntry e) async {
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
                zh ? '从书架撤下' : 'Remove from shelf',
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
      await gateway.deleteReadingBook(e.id);
      await _load();
    } catch (err) {
      debugPrint('[Study] deleteReadingBook failed: $err');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
          zh ? '书房' : 'The Study',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_gateway != null && _tab == 1) ...[
            IosIconButton(
              icon: Lucide.Upload,
              size: 21,
              minSize: 44,
              onTap: _uploading ? null : _importBook,
            ),
            IosIconButton(
              icon: Lucide.Plus,
              size: 22,
              minSize: 44,
              onTap: _addBook,
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (_gateway != null && !_loading && !_error) _tabs(zh, cs),
          Expanded(child: _buildBody(context, zh, cs)),
          if (_tab == 0) _buildComposer(context, zh, cs),
        ],
      ),
    ),
      ],
    );
  }

  Widget _tabs(bool zh, ColorScheme cs) {
    Widget t(int i, String label) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_tab != i) {
              Haptics.soft();
              setState(() => _tab = i);
            }
          },
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? cs.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: AppFontWeights.semibold,
                  color: on
                      ? cs.onSurface
                      : cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [t(0, zh ? '待办' : 'To-dos'), t(1, zh ? '共读书柜' : 'Shelf')],
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
    return _tab == 0 ? _todoView(zh, cs) : _bookView(zh, cs);
  }

  Widget _todoView(bool zh, ColorScheme cs) {
    if (_todos.isEmpty) {
      return RoomStateHint(
        icon: Lucide.BookOpen,
        text: zh ? '还没有待办。\n想做的事，写在下面。' : 'No to-dos yet.',
      );
    }
    final items = _sortedTodos;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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

  Widget _bookView(bool zh, ColorScheme cs) {
    if (_books.isEmpty && _reading.isEmpty) {
      return RoomStateHint(
        icon: Lucide.BookOpen,
        text: zh
            ? '书柜还空着。\n右上角导入一本整书，或加一本想一起读的。'
            : 'The shelf is empty.',
      );
    }
    // Two sections: "在读的整本书" (full-text, openable) on top, then the
    // want/reading/read metadata bookshelf below. Both scroll together.
    final hasReading = _reading.isNotEmpty;
    final hasBooks = _books.isNotEmpty;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (hasReading) ...[
            _sectionLabel(zh ? '在读的整本书' : 'Books to read together', cs),
            for (final e in _reading)
              _ReadingRow(
                entry: e,
                zh: zh,
                onTap: () => _openReader(e),
                onLongPress: () => _deleteReading(e),
              ),
          ],
          if (hasReading && hasBooks) const SizedBox(height: 14),
          if (hasBooks) ...[
            _sectionLabel(zh ? '想读的书' : 'On the shelf', cs),
            for (final b in _books)
              _BookRow(book: b, zh: zh, onTap: () => _cycleBook(b)),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: AppFontWeights.semibold,
        color: cs.onSurface.withValues(alpha: 0.45),
      ),
    ),
  );

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

class _TodoRow extends StatefulWidget {
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

  @override
  State<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<_TodoRow> {
  bool _expanded = false;

  String? _ownerLabel() {
    switch (widget.todo.owner) {
      case 'L':
        return widget.zh ? '爸爸' : 'Llaude';
      case 'C':
        return widget.zh ? '我' : 'me';
      case 'us':
        return widget.zh ? '我们' : 'us';
      default:
        return null;
    }
  }

  String get _title {
    final firstLine = widget.todo.text
        .split('\n')
        .firstWhere((s) => s.trim().isNotEmpty, orElse: () => widget.todo.text);
    return firstLine.trim();
  }

  @override
  Widget build(BuildContext context) {
    final todo = widget.todo;
    final cs = Theme.of(context).colorScheme;
    final owner = _ownerLabel();
    final muted = cs.onSurface.withValues(alpha: 0.45);
    final titleStyle = TextStyle(
      fontSize: 15.5,
      height: 1.35,
      color: todo.done ? muted : cs.onSurface,
      decoration:
          todo.done ? TextDecoration.lineThrough : TextDecoration.none,
      decorationColor: muted,
    );

    // Collapsed shows the body on a single line; offering "expand" is only
    // meaningful when the full text can't fit on that line — whether it spans
    // multiple lines OR is one line too long. The old check (text != firstLine)
    // missed long single-line todos: they got ellipsized with no way to open
    // (the 【取自…】 entries). Measure the full text at maxLines:1 — a newline
    // or a width overflow both trip didExceedMaxLines.
    final screenW = MediaQuery.of(context).size.width;
    // Width budget: list hpad(16×2) + card hpad(14×2) + checkbox(21) + gap(12).
    final textAvail = screenW - 32 - 28 - 21 - 12;
    final hasMore = (TextPainter(
      text: TextSpan(text: todo.text.trim(), style: titleStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: textAvail > 0 ? textAvail : screenW))
        .didExceedMaxLines;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StillGlass(
        radius: 14,
        blur: false,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () {
          if (hasMore) {
            Haptics.soft();
            setState(() => _expanded = !_expanded);
          }
        },
        onLongPress: () => widget.onDelete(todo),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: IosCheckbox(
                value: todo.done,
                onChanged: (_) => widget.onToggle(todo),
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Collapsed shows the title (one line); expanded shows the
                  // full multi-line body.
                  Text(
                    _expanded ? todo.text.trim() : _title,
                    maxLines: _expanded ? null : 1,
                    overflow:
                        _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
                    style: titleStyle,
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
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 1),
                child: Icon(
                  _expanded ? Lucide.ChevronUp : Lucide.ChevronDown,
                  size: 16,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.book, required this.zh, required this.onTap});

  final OurHomeBook book;
  final bool zh;
  final VoidCallback onTap;

  ({String label, Color Function(ColorScheme) color}) _statusStyle() {
    switch (book.status) {
      case 'reading':
        return (label: zh ? '在读' : 'reading', color: (cs) => cs.primary);
      case 'read':
        return (label: zh ? '读完' : 'read', color: (cs) => cs.tertiary);
      default:
        return (
          label: zh ? '想读' : 'want',
          color: (cs) => cs.onSurface.withValues(alpha: 0.5),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = _statusStyle();
    final c = st.color(cs);
    final readDone = book.status == 'read';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StillGlass(
        radius: 14,
        blur: false,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Lucide.BookOpen,
              size: 20,
              color: cs.tertiary.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    book.title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurface.withValues(alpha: readDone ? 0.6 : 1),
                    ),
                  ),
                  if (book.author.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        book.author,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  if (book.quote.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '"${book.quote}"',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                st.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: AppFontWeights.semibold,
                  color: c,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row on the "在读的整本书" shelf — a full-text book that opens in the reader.
/// Shows the title, a progress bar + percent, and how many 🌙 daddy left.
class _ReadingRow extends StatelessWidget {
  const _ReadingRow({
    required this.entry,
    required this.zh,
    required this.onTap,
    required this.onLongPress,
  });

  final ReadingEntry entry;
  final bool zh;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (entry.progress.clamp(0.0, 1.0) * 100).round();
    final started = entry.progress > 0.0001;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StillGlass(
        radius: 14,
        blur: false,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Lucide.BookOpen, size: 20, color: cs.primary.withValues(alpha: 0.9)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: entry.progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        started
                            ? (zh ? '已读 $pct%' : '$pct% read')
                            : (zh ? '还没开始' : 'not started'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      if (entry.notes > 0) ...[
                        const SizedBox(width: 10),
                        const Text('🌙', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 3),
                        Text(
                          zh ? '${entry.notes} 处' : '${entry.notes}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Lucide.ChevronRight,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.3),
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

class _NewBook {
  const _NewBook(this.title, this.author, this.quote);
  final String title;
  final String author;
  final String quote;
}

enum _ImportChoice { file, paste }

class _PastedBook {
  const _PastedBook(this.title, this.text);
  final String title;
  final String text;
}

/// Fallback import: paste the whole book text + a title. Used when the file
/// picker can't reach the file (or there's no .txt to hand).
class _PasteBookSheet extends StatefulWidget {
  const _PasteBookSheet({required this.zh});
  final bool zh;

  @override
  State<_PasteBookSheet> createState() => _PasteBookSheetState();
}

class _PasteBookSheetState extends State<_PasteBookSheet> {
  final _title = TextEditingController();
  final _text = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: cs.onSurface.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            style: const TextStyle(fontSize: 15.5),
            decoration: deco(zh ? '书名…' : 'title…'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            maxLines: 8,
            minLines: 5,
            style: const TextStyle(fontSize: 14),
            decoration: deco(zh ? '把整本正文粘贴到这里…' : 'paste the whole text here…'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: IosCardPress(
              baseColor: cs.primary,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 14),
              onTap: () {
                final t = _text.text.trim();
                if (t.isEmpty) return;
                Navigator.of(
                  context,
                ).pop(_PastedBook(_title.text.trim(), _text.text));
              },
              child: Center(
                child: Text(
                  zh ? '导入' : 'Import',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBookSheet extends StatefulWidget {
  const _AddBookSheet({required this.zh});
  final bool zh;

  @override
  State<_AddBookSheet> createState() => _AddBookSheetState();
}

class _AddBookSheetState extends State<_AddBookSheet> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _quote = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _quote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: cs.onSurface.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            style: const TextStyle(fontSize: 15.5),
            decoration: deco(zh ? '书名…' : 'title…'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _author,
            style: const TextStyle(fontSize: 14.5),
            decoration: deco(zh ? '作者（可空）…' : 'author (optional)…'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quote,
            maxLines: 3,
            minLines: 2,
            style: const TextStyle(fontSize: 14.5),
            decoration: deco(zh ? '想标的一句话（可空）…' : 'a line to keep (optional)…'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: IosCardPress(
              baseColor: cs.primary,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 14),
              onTap: () {
                final t = _title.text.trim();
                if (t.isEmpty) return;
                Navigator.of(
                  context,
                ).pop(_NewBook(t, _author.text.trim(), _quote.text.trim()));
              },
              child: Center(
                child: Text(
                  zh ? '上架' : 'Add to shelf',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
