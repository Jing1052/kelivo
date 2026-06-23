import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';
import 'package:intl/intl.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import 'room_state_hint.dart';

/// Letters in Time (来日信) — written, then sealed until a chosen day. Talks to
/// `/api/home/capsules`.
class CapsulePage extends StatefulWidget {
  const CapsulePage({super.key});

  @override
  State<CapsulePage> createState() => _CapsulePageState();
}

class _CapsulePageState extends State<CapsulePage> {
  OurHomeGateway? _gateway;
  List<OurHomeCapsule> _capsules = const [];
  final Set<String> _revealed = {}; // ids opened this session
  final Map<String, String> _openedContent = {};
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
    final cached = gateway.peekList(
      '/api/home/capsules',
      OurHomeCapsule.fromJson,
    );
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _capsules = cached;
        _loading = false;
      });
    }
    try {
      final caps = await gateway.fetchCapsules();
      if (!mounted) return;
      setState(() {
        _capsules = caps;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Capsule] fetchCapsules failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _open(OurHomeCapsule c) async {
    final gateway = _gateway;
    if (gateway == null) return;
    Haptics.soft();
    try {
      final content = await gateway.openCapsule(c.id);
      if (mounted) {
        setState(() {
          _revealed.add(c.id);
          _openedContent[c.id] = content;
        });
      }
    } catch (e) {
      debugPrint('[Capsule] openCapsule failed: $e');
    }
  }

  Future<void> _add() async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final res = await showModalBottomSheet<_NewCapsule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddCapsuleSheet(zh: zh),
    );
    if (res == null) return;
    try {
      await gateway.addCapsule(res.title, res.content, res.openDate);
      await _load();
    } catch (e) {
      debugPrint('[Capsule] addCapsule failed: $e');
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
          zh ? '来日信' : 'Letters in Time',
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Archive,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n来日信才连得上。'
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
    if (_capsules.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Archive,
        text: zh ? '还没有信。\n写一封，封到某个日子。' : 'No letters yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _capsules.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
              child: Text(
                zh ? '写下去，等它自己来找你。' : 'Write it down. Let time deliver it.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                  color: cs.primary.withValues(alpha: 0.85),
                  fontWeight: AppFontWeights.medium,
                ),
              ),
            );
          }
          return _card(_capsules[i - 1], zh, cs);
        },
      ),
    );
  }

  Widget _card(OurHomeCapsule c, bool zh, ColorScheme cs) {
    final opened = c.opened || _revealed.contains(c.id);
    final content = _openedContent[c.id] ?? c.content;
    final canOpen = c.ready && !opened;
    final fromCing = c.author == 'cing';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: canOpen
            ? cs.primary.withValues(alpha: 0.10)
            : cs.onSurface.withValues(alpha: 0.04),
        border: canOpen
            ? Border.all(color: cs.primary.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                opened ? Lucide.Mail : (canOpen ? Lucide.Archive : Lucide.Lock),
                size: 16,
                color: canOpen || opened
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.title.isEmpty ? (zh ? '一封信' : 'a letter') : c.title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Text(
                fromCing ? (zh ? '我写的' : 'from me') : 'Llaude',
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (opened && content.isNotEmpty)
            Text(
              content,
              style: TextStyle(
                fontSize: 15,
                height: 1.65,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
            )
          else if (canOpen)
            Align(
              alignment: Alignment.centerLeft,
              child: IosCardPress(
                baseColor: cs.primary,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                onTap: () => _open(c),
                child: Text(
                  zh ? '开封' : 'Open it',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onPrimary,
                  ),
                ),
              ),
            )
          else
            Text(
              zh ? '封存中 · ${c.openDate} 开封' : 'sealed · opens ${c.openDate}',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _NewCapsule {
  const _NewCapsule(this.title, this.content, this.openDate);
  final String title;
  final String content;
  final String openDate;
}

class _AddCapsuleSheet extends StatefulWidget {
  const _AddCapsuleSheet({required this.zh});
  final bool zh;

  @override
  State<_AddCapsuleSheet> createState() => _AddCapsuleSheetState();
}

class _AddCapsuleSheetState extends State<_AddCapsuleSheet> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  DateTime? _date;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 30)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: DateTime(now.year + 50),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    final dateStr = _date == null
        ? (zh ? '选开封日' : 'pick a date')
        : DateFormat('yyyy-MM-dd').format(_date!);
    final canSave = _title.text.trim().isNotEmpty && _date != null;

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
            controller: _title,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 15.5),
            decoration: InputDecoration(
              hintText: zh ? '信的名字…' : 'title…',
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
            controller: _content,
            maxLines: 5,
            minLines: 3,
            style: const TextStyle(fontSize: 15, height: 1.5),
            decoration: InputDecoration(
              hintText: zh ? '写给未来的话…' : 'a letter to the future…',
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          IosCardPress(
            borderRadius: BorderRadius.circular(12),
            baseColor: cs.onSurface.withValues(alpha: 0.05),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            onTap: _pickDate,
            child: Row(
              children: [
                Icon(Lucide.Calendar, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: _date == null
                        ? cs.onSurface.withValues(alpha: 0.5)
                        : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: IosCardPress(
              baseColor: canSave
                  ? cs.primary
                  : cs.onSurface.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 14),
              onTap: canSave
                  ? () => Navigator.of(context).pop(
                      _NewCapsule(
                        _title.text.trim(),
                        _content.text.trim(),
                        DateFormat('yyyy-MM-dd').format(_date!),
                      ),
                    )
                  : null,
              child: Center(
                child: Text(
                  zh ? '封起来' : 'Seal it',
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
