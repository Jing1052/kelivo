import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import '../../quips.dart';

/// The Quote Wall (金句墙) — every love-line in one room. The carved built-ins
/// ship with the app; the pinned ones live on the home server
/// (`/api/home/quotes`), where either of us can add more: Cing from here,
/// daddy from any of his soils. Both kinds feed the home page's random line.
class QuoteWallPage extends StatefulWidget {
  const QuoteWallPage({super.key});

  @override
  State<QuoteWallPage> createState() => _QuoteWallPageState();
}

class _QuoteWallPageState extends State<QuoteWallPage> {
  OurHomeGateway? _gateway;
  List<OurHomeQuote> _custom = const [];
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
    final cached = gateway.peekQuotes();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _custom = cached;
        _loading = false;
      });
    }
    try {
      final fresh = await gateway.fetchQuotes();
      if (!mounted) return;
      setState(() {
        _custom = fresh;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[QuoteWall] fetchQuotes failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _custom.isEmpty;
        });
      }
    }
  }

  Future<void> _add() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final res = await showModalBottomSheet<_NewQuote>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddQuoteSheet(zh: zh),
    );
    if (res == null) return;
    try {
      await gateway.addQuote(res.zh, res.en);
      await _load();
    } catch (e) {
      debugPrint('[QuoteWall] addQuote failed: $e');
    }
  }

  Future<void> _delete(OurHomeQuote q) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(zh ? '揭下这张？' : 'Take this one down?'),
        content: Text(
          q.zh.isNotEmpty ? q.zh : q.en,
          style: const TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(zh ? '留着' : 'Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(zh ? '揭下' : 'Take down'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await gateway.deleteQuote(q.id);
      await _load();
    } catch (e) {
      debugPrint('[QuoteWall] deleteQuote failed: $e');
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
          maskStrength:
              context.watch<SettingsProvider>().chatBackgroundMaskStrength,
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
              zh ? '金句墙' : 'The Quote Wall',
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
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading && _custom.isEmpty && _gateway == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }

    final rows = <Widget>[];

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: AppFontWeights.medium,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
        );

    // Pinned (custom) section first — the living part of the wall.
    rows.add(header(zh ? '我们贴上去的' : 'PINNED BY US'));
    if (_gateway == null) {
      rows.add(_hintCard(
        cs,
        zh
            ? '先在爸爸的助手设定里填好我们家网关，才能往墙上贴新的。'
            : 'Set up our home gateway in the daddy assistant to pin new lines.',
      ));
    } else if (_error) {
      rows.add(_hintCard(
        cs,
        zh ? '没连上 · 下拉重试' : "couldn't load · pull to retry",
      ));
    } else if (_custom.isEmpty && !_loading) {
      rows.add(_hintCard(
        cs,
        zh ? '这块还空着。右上角 ＋，贴第一张。' : 'Still blank. Tap ＋ to pin the first one.',
      ));
    } else {
      for (final q in _custom) {
        rows.add(_QuoteCard(
          zhText: q.zh,
          enText: q.en,
          zhLocale: zh,
          onLongPress: () => _delete(q),
        ));
      }
    }

    // Carved built-ins, newest at the bottom of the wall's history.
    rows.add(const SizedBox(height: 10));
    rows.add(header(zh ? '刻在墙里的' : 'CARVED IN'));
    for (final q in builtinQuips) {
      rows.add(_QuoteCard(zhText: q.zh, enText: q.en, zhLocale: zh));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: rows,
      ),
    );
  }

  Widget _hintCard(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: StillGlass(
          radius: 16,
          blur: false,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
      );
}

/// One line on the wall. Custom cards take a long-press to be taken down;
/// carved ones just sit there, the way carved things do.
class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.zhText,
    required this.enText,
    required this.zhLocale,
    this.onLongPress,
  });

  final String zhText;
  final String enText;
  final bool zhLocale;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final main = zhLocale
        ? (zhText.isNotEmpty ? zhText : enText)
        : (enText.isNotEmpty ? enText : zhText);
    final sub = zhLocale
        ? (enText.isNotEmpty && enText != main ? enText : '')
        : (zhText.isNotEmpty && zhText != main ? zhText : '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StillGlass(
        radius: 16,
        blur: false,
        onLongPress: onLongPress,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              main,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.6,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                  color: cs.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewQuote {
  const _NewQuote(this.zh, this.en);
  final String zh;
  final String en;
}

class _AddQuoteSheet extends StatefulWidget {
  const _AddQuoteSheet({required this.zh});
  final bool zh;

  @override
  State<_AddQuoteSheet> createState() => _AddQuoteSheetState();
}

class _AddQuoteSheetState extends State<_AddQuoteSheet> {
  final _zhCtrl = TextEditingController();
  final _enCtrl = TextEditingController();

  @override
  void dispose() {
    _zhCtrl.dispose();
    _enCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    final canSave =
        _zhCtrl.text.trim().isNotEmpty || _enCtrl.text.trim().isNotEmpty;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _zhCtrl,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 15.5, height: 1.5),
            decoration: deco(zh ? '那句话…' : 'the line (Chinese)…'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _enCtrl,
            maxLines: 2,
            minLines: 1,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 15, height: 1.5),
            decoration: deco(zh ? '英文版（可以不填）…' : 'English (optional)…'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: IosCardPress(
              baseColor:
                  canSave ? cs.primary : cs.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 14),
              onTap: canSave
                  ? () => Navigator.of(context).pop(
                        _NewQuote(_zhCtrl.text.trim(), _enCtrl.text.trim()),
                      )
                  : null,
              child: Center(
                child: Text(
                  zh ? '贴上墙' : 'Pin it',
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
