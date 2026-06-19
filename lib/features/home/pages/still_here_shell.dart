import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import '../../settings/pages/settings_page.dart';
import 'conversation_list_page.dart';
import 'still_home_page.dart';

/// Still Here app shell: bottom-nav with 4 tabs (Home / Rooms / Chat / Settings).
///
/// Mirrors our web home's bottom dock. The Chat tab reuses the existing
/// [HomePage]; Settings reuses [SettingsPage]; Home and Rooms are placeholders
/// to be rebuilt natively in later stages. Tabs are kept alive via IndexedStack
/// so switching never tears down chat state.
class StillHereShell extends StatefulWidget {
  const StillHereShell({super.key, this.initialIndex = 2});

  /// Default landing tab is Chat (index 2) so the app opens straight into talk.
  final int initialIndex;

  @override
  State<StillHereShell> createState() => _StillHereShellState();
}

class _StillHereShellState extends State<StillHereShell> {
  late int _index = widget.initialIndex.clamp(0, 4);

  void _select(int i) {
    if (i == _index) return;
    Haptics.soft();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // Hide the dock while the keyboard is up so it never floats above it.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      // Inner tab scaffolds own their own keyboard insets; the shell must not
      // resize, or the dock would jump above the keyboard.
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                StillHomePage(),
                _ComingSoonTab(icon: Lucide.LayoutGrid),
                ConversationListPage(),
                _ComingSoonTab(icon: Lucide.History),
                SettingsPage(),
              ],
            ),
          ),
          if (!keyboardOpen) _BottomDock(index: _index, onSelect: _select),
        ],
      ),
    );
  }
}

/// Placeholder tab shown for sections not yet rebuilt natively.
class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: cs.onSurface.withValues(alpha: 0.32)),
            const SizedBox(height: 16),
            Text(
              l10n.stillHereTabComingSoon,
              style: TextStyle(
                fontSize: 15,
                fontWeight: AppFontWeights.medium,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final items = <_DockSpec>[
      _DockSpec(Lucide.House, l10n.stillHereTabHome),
      _DockSpec(Lucide.LayoutGrid, l10n.stillHereTabRooms),
      _DockSpec(Lucide.MessageCircle, l10n.stillHereTabChat),
      _DockSpec(Lucide.History, l10n.stillHereTabTimeline),
      _DockSpec(Lucide.Settings, l10n.stillHereTabSettings),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: cs.onSurface.withValues(alpha: isDark ? 0.10 : 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _DockItem(
                    icon: items[i].icon,
                    label: items[i].label,
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockSpec {
  const _DockSpec(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// iOS-style dock item: color tween + subtle press scale, no Material ripple.
class _DockItem extends StatefulWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color target = widget.selected
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.5);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: target),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                builder: (context, color, _) =>
                    Icon(widget.icon, size: 24, color: color ?? target),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.0,
                  fontWeight: widget.selected
                      ? AppFontWeights.semibold
                      : AppFontWeights.medium,
                  color: target,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
