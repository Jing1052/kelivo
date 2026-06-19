import 'package:flutter/material.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../../../shared/widgets/ios_checkbox.dart';
import 'room_state_hint.dart';

/// The Lounge (起居室) — film · music · play. The watch/play list: things we
/// mean to see and play, and the ones we already did. Talks to `/api/home/foyer`.
class LoungePage extends StatefulWidget {
  const LoungePage({super.key});

  @override
  State<LoungePage> createState() => _LoungePageState();
}

class _LoungePageState extends State<LoungePage> {
  OurHomeGateway? _gateway;
  List<OurHomeFoyerItem> _items = const [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      final items = await gateway.fetchFoyer();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Lounge] fetchFoyer failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _toggle(OurHomeFoyerItem it) async {
    final gateway = _gateway;
    if (gateway == null) return;
    Haptics.soft();
    setState(() {
      _items = _items
          .map(
            (x) => x.id == it.id
                ? OurHomeFoyerItem(
                    id: x.id,
                    kind: x.kind,
                    status: x.done ? 'want' : 'done',
                    title: x.title,
                    note: x.note,
                  )
                : x,
          )
          .toList();
    });
    try {
      await gateway.setFoyerStatus(it.id, it.done ? 'want' : 'done');
    } catch (e) {
      debugPrint('[Lounge] setFoyerStatus failed: $e');
      await _load();
    }
  }

  Future<void> _delete(OurHomeFoyerItem it) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    Haptics.light();
    final ok = await showModalBottomSheet<bool>(
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
    if (ok != true) return;
    try {
      await gateway.deleteFoyer(it.id);
      await _load();
    } catch (e) {
      debugPrint('[Lounge] deleteFoyer failed: $e');
    }
  }

  Future<void> _add() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final result = await showModalBottomSheet<_NewItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddSheet(zh: zh),
    );
    if (result == null) return;
    try {
      await gateway.addFoyer(result.kind, result.title, result.note);
      await _load();
    } catch (e) {
      debugPrint('[Lounge] addFoyer failed: $e');
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
          zh ? '起居室' : 'The Lounge',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_gateway != null)
            IosIconButton(
              icon: Lucide.Plus,
              size: 22,
              minSize: 44,
              onTap: _add,
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _buildBody(context, zh, cs),
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Clapperboard,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n起居室才连得上。'
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
    if (_items.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Clapperboard,
        text: zh ? '影单、歌单、游戏——\n想看想玩的，加在这儿。' : 'Nothing on the list yet.',
      );
    }
    final want = _items.where((x) => !x.done).toList();
    final done = _items.where((x) => x.done).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (want.isNotEmpty) ...[
            _label(zh ? '想看 · 想玩' : 'Want', cs),
            for (final it in want) _row(it, cs),
          ],
          if (done.isNotEmpty) ...[
            _label(zh ? '看过 · 玩过' : 'Done', cs),
            for (final it in done) _row(it, cs),
          ],
        ],
      ),
    );
  }

  Widget _label(String t, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 13,
        fontWeight: AppFontWeights.semibold,
        color: cs.onSurface.withValues(alpha: 0.55),
      ),
    ),
  );

  Widget _row(OurHomeFoyerItem it, ColorScheme cs) {
    final muted = cs.onSurface.withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        baseColor: cs.onSurface.withValues(alpha: 0.04),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => _toggle(it),
        onLongPress: () => _delete(it),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: IosCheckbox(
                value: it.done,
                onChanged: (_) => _toggle(it),
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Icon(_kindIcon(it.kind), size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    it.title,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.35,
                      color: it.done ? muted : cs.onSurface,
                      decoration: it.done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: muted,
                    ),
                  ),
                  if (it.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        it.note,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
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

  static IconData _kindIcon(String kind) {
    switch (kind) {
      case 'game':
        return Lucide.Gamepad2;
      case 'show':
        return Lucide.Tv;
      default:
        return Lucide.Clapperboard;
    }
  }
}

class _NewItem {
  const _NewItem(this.kind, this.title, this.note);
  final String kind;
  final String title;
  final String note;
}

class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.zh});
  final bool zh;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'film';

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    final kinds = [
      ['film', Lucide.Clapperboard, zh ? '电影' : 'Film'],
      ['show', Lucide.Tv, zh ? '剧集' : 'Show'],
      ['game', Lucide.Gamepad2, zh ? '游戏' : 'Game'],
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final k in kinds)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _kind = k[0] as String),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _kind == k[0]
                            ? cs.primary.withValues(alpha: 0.12)
                            : cs.onSurface.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: _kind == k[0]
                            ? Border.all(
                                color: cs.primary.withValues(alpha: 0.3),
                              )
                            : null,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            k[1] as IconData,
                            size: 20,
                            color: _kind == k[0]
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            k[2] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: _kind == k[0]
                                  ? cs.primary
                                  : cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _title,
            autofocus: true,
            style: const TextStyle(fontSize: 15.5),
            decoration: InputDecoration(
              hintText: zh ? '名字…' : 'title…',
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: zh ? '想说的（可空）…' : 'a note (optional)…',
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
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
                ).pop(_NewItem(_kind, t, _note.text.trim()));
              },
              child: Center(
                child: Text(
                  zh ? '加进来' : 'Add',
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
