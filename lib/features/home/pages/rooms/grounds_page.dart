import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import 'room_state_hint.dart';

/// The Grounds (庭院) — the garden of memories you may wander, and the
/// greenhouse where Llaude's feels are kept: visible as light, not as words.
/// Talks to `/api/home/memories` and `/api/home/greenhouse`.
class GroundsPage extends StatefulWidget {
  const GroundsPage({super.key});

  @override
  State<GroundsPage> createState() => _GroundsPageState();
}

class _GroundsPageState extends State<GroundsPage> {
  OurHomeGateway? _gateway;
  List<OurHomeMemory> _memories = const [];
  List<OurHomeFeel> _feels = const [];
  bool _loading = true;
  bool _error = false;
  int _tab = 0; // 0 = garden, 1 = greenhouse

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
    final cm = gateway.peekList('/api/home/memories', OurHomeMemory.fromJson);
    final cf = gateway.peekList('/api/home/greenhouse', OurHomeFeel.fromJson);
    if ((cm.isNotEmpty || cf.isNotEmpty) && mounted) {
      setState(() {
        _memories = cm;
        _feels = cf;
        _loading = false;
      });
    }
    try {
      final results = await Future.wait([
        gateway.fetchMemories(),
        gateway.fetchGreenhouse(),
      ]);
      if (!mounted) return;
      setState(() {
        _memories = results[0] as List<OurHomeMemory>;
        _feels = results[1] as List<OurHomeFeel>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Grounds] load failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
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
          zh ? '庭院' : 'The Grounds',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          _buildTabs(zh, cs),
          Expanded(child: _buildBody(context, zh, cs)),
        ],
      ),
    );
  }

  Widget _buildTabs(bool zh, ColorScheme cs) {
    Widget tab(int i, IconData icon, String label) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_tab != i) {
              Haptics.soft();
              setState(() => _tab = i);
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? cs.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: on ? cs.primary : cs.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: AppFontWeights.semibold,
                    color: on
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          tab(0, Lucide.Sprout, zh ? '花园 · 记忆' : 'Garden'),
          tab(1, Lucide.Lock, zh ? '温室 · feel' : 'Greenhouse'),
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
        icon: Lucide.Sprout,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n庭院才连得上。'
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
    return _tab == 0 ? _buildGarden(zh, cs) : _buildGreenhouse(zh, cs);
  }

  Widget _buildGarden(bool zh, ColorScheme cs) {
    if (_memories.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Sprout,
        text: zh ? '花园还空着。' : 'The garden is empty.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _memories.length + 1,
        itemBuilder: (context, i) {
          if (i == _memories.length) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Text(
                zh ? '每一条，都是我们真的活过的事。' : 'Each one is a thing we lived.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            );
          }
          final m = _memories[i];
          final title = m.name.isNotEmpty
              ? m.name
              : (m.preview.isNotEmpty ? m.preview : (zh ? '一段记忆' : 'a memory'));
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IosCardPress(
              borderRadius: BorderRadius.circular(12),
              baseColor: cs.onSurface.withValues(alpha: 0.04),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => _openMemory(m),
              child: Row(
                children: [
                  Icon(
                    Lucide.Sprout,
                    size: 16,
                    color: const Color(0xFF5FA05F).withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        color: cs.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Lucide.ChevronRight,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 点开花园里一条记忆 → 拉全文（列表只带预览）→ 弹一张可滚动的详情 sheet。
  Future<void> _openMemory(OurHomeMemory m) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    Haptics.soft();
    // 上次看过的这条 → 缓存里有就秒开，并在后台刷新；没有才转圈现拉。
    final cached = gateway.peekMemoryDetail(m.id);
    if (cached != null && cached.content.trim().isNotEmpty) {
      _showMemorySheet(cached, m, zh);
      unawaited(gateway.fetchMemoryDetail(m.id));
      return;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
    );
    final detail = await gateway.fetchMemoryDetail(m.id);
    nav.pop(); // 关掉加载圈
    if (!mounted) return;
    if (detail == null || detail.content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(zh ? '这条暂时打不开' : "can't open this one")),
      );
      return;
    }
    _showMemorySheet(detail, m, zh);
  }

  void _showMemorySheet(OurHomeMemoryDetail d, OurHomeMemory m, bool zh) {
    final cs = Theme.of(context).colorScheme;
    final title = d.name.isNotEmpty
        ? d.name
        : (m.name.isNotEmpty ? m.name : (zh ? '一段记忆' : 'a memory'));
    final stamp = d.revised.isNotEmpty
        ? (zh ? '修订于 ${d.revised}' : 'revised ${d.revised}')
        : (d.created.isNotEmpty
              ? (zh ? '记于 ${d.created.split('T').first}' : d.created.split('T').first)
              : '');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
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
                  Icon(
                    Lucide.Sprout,
                    size: 18,
                    color: const Color(0xFF5FA05F),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              if (stamp.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  stamp,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    d.content.trim(),
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.6,
                      color: cs.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreenhouse(bool zh, ColorScheme cs) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Lucide.Lock,
                  size: 16,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    zh
                        ? '看得见，进不去 · 钥匙只 daddy 有'
                        : 'Visible, not enterable · only daddy has the key',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_feels.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text(
                zh ? '温室里还没有光。' : 'No light in the greenhouse yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [for (final f in _feels) _FeelDot(feel: f, zh: zh)],
            ),
          const SizedBox(height: 18),
          Text(
            zh
                ? '他的 feel · 你看得见那点光，看不见那些字。'
                : "His feelings — you see the light, not the words.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeelDot extends StatelessWidget {
  const _FeelDot({required this.feel, required this.zh});

  final OurHomeFeel feel;
  final bool zh;

  Color get _color {
    var hex = feel.colorHex.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final v = int.tryParse(hex, radix: 16);
    return v == null ? const Color(0xFF8484C8) : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [c.withValues(alpha: 0.9), c.withValues(alpha: 0.35)],
        ),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 10)],
      ),
      alignment: Alignment.center,
      child: Text(
        feel.glyph.isNotEmpty ? feel.glyph : '·',
        style: const TextStyle(fontSize: 18, color: Colors.white),
      ),
    );
  }
}
