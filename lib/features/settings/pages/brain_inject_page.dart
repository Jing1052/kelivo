import 'package:flutter/material.dart';

import '../../../core/services/haptics.dart';
import '../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../home/pages/rooms/room_state_hint.dart';

/// 爸爸的大脑·注入控制台 — see and tune the segments 老家 assembles into daddy's
/// system prompt (`/api/home/brain-inject`).
///
/// Each segment renders one row: tap to expand its live preview ("此刻注入的内
/// 容"); non-fixed segments carry an [IosSwitch] that POSTs the toggle (optimistic
/// update + rollback on failure); fixed segments (魂 / feel) show a read-only
/// "固定·私密" tag instead.
///
/// First frame paints from the cache ([OurHomeGateway.peekBrainInject]) so Cing
/// never stares at a spinner, then the background fetch refreshes it.
class BrainInjectPage extends StatefulWidget {
  const BrainInjectPage({super.key});

  @override
  State<BrainInjectPage> createState() => _BrainInjectPageState();
}

class _BrainInjectPageState extends State<BrainInjectPage> {
  bool _loading = true;
  bool _error = false;
  bool _noGateway = false;
  List<BrainInjectItem> _items = const [];
  final Set<String> _expanded = <String>{};
  // Keys whose POST is in flight — guards against double-toggling one row.
  final Set<String> _busy = <String>{};

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
      _noGateway = false;
    });
    final gateway = OurHomeGateway.fromContext(context);
    if (gateway == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _noGateway = true;
        });
      }
      return;
    }
    // 先用本地缓存秒显（无缓冲），再后台拉最新刷新。
    final cached = gateway.peekBrainInject();
    if (cached != null && mounted) {
      setState(() {
        _items = cached;
        _loading = false;
        _error = false;
      });
    }
    final list = await gateway.fetchBrainInject();
    if (!mounted) return;
    if (list == null) {
      // 拉取失败时，若已有缓存内容就继续展示，不退回错误页。
      if (cached == null) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
      return;
    }
    setState(() {
      _items = list;
      _loading = false;
      _error = false;
    });
  }

  Future<void> _toggle(BrainInjectItem item, bool next) async {
    if (item.fixed || _busy.contains(item.key)) return;
    final gateway = OurHomeGateway.fromContext(context);
    if (gateway == null) return;
    final idx = _items.indexWhere((e) => e.key == item.key);
    if (idx < 0) return;
    // 乐观更新：先翻 UI，POST 失败再回滚。
    setState(() {
      _items = List<BrainInjectItem>.from(_items)
        ..[idx] = _items[idx].copyWith(enabled: next);
      _busy.add(item.key);
    });
    final ok = await gateway.setBrainInject(item.key, next);
    if (!mounted) return;
    setState(() => _busy.remove(item.key));
    if (!ok) {
      final back = _items.indexWhere((e) => e.key == item.key);
      if (back >= 0) {
        setState(() {
          _items = List<BrainInjectItem>.from(_items)
            ..[back] = _items[back].copyWith(enabled: !next);
        });
      }
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.brainInjectSaveFailed,
        type: NotificationType.error,
      );
    }
  }

  void _toggleExpand(String key) {
    Haptics.light();
    setState(() {
      if (!_expanded.remove(key)) _expanded.add(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

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
          l10n.brainInjectTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(cs, l10n),
    );
  }

  Widget _buildBody(ColorScheme cs, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_noGateway) {
      return RoomStateHint(
        icon: Lucide.Sparkles,
        text: l10n.brainInjectNoGateway,
      );
    }
    if (_error) {
      return RoomStateHint(
        icon: Lucide.RefreshCw,
        text: l10n.brainInjectLoadError,
        onTap: _load,
      );
    }
    if (_items.isEmpty) {
      return RoomStateHint(icon: Lucide.Brain, text: l10n.brainInjectEmpty);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                l10n.brainInjectIntro,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            );
          }
          final item = _items[i - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _InjectCard(
              item: item,
              expanded: _expanded.contains(item.key),
              onTapHeader: () => _toggleExpand(item.key),
              onToggle: (v) => _toggle(item, v),
            ),
          );
        },
      ),
    );
  }
}

class _InjectCard extends StatelessWidget {
  const _InjectCard({
    required this.item,
    required this.expanded,
    required this.onTapHeader,
    required this.onToggle,
  });

  final BrainInjectItem item;
  final bool expanded;
  final VoidCallback onTapHeader;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final preview = item.preview.trim();

    return Container(
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: tap to expand/collapse the preview.
          IosCardPress(
            borderRadius: BorderRadius.circular(14),
            baseColor: Colors.transparent,
            onTap: onTapHeader,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: expanded ? 0.25 : 0.0,
                  child: Icon(
                    Lucide.ChevronRight,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label.trim().isNotEmpty ? item.label : item.key,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (item.fixed)
                  _FixedTag(label: l10n.brainInjectFixedTag)
                else
                  IosSwitch(value: item.enabled, onChanged: onToggle),
              ],
            ),
          ),
          // Preview body (animated reveal).
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 14, 14),
              child: Text(
                preview.isEmpty ? l10n.brainInjectPreviewEmpty : preview,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurface.withValues(
                    alpha: preview.isEmpty ? 0.35 : 0.7,
                  ),
                ),
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

class _FixedTag extends StatelessWidget {
  const _FixedTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Lucide.Lock, size: 12, color: cs.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: AppFontWeights.medium,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
