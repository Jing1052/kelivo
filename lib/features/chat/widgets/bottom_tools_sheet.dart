import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../home/widgets/world_book_sheet.dart';
import '../../settings/widgets/style_sheet.dart';
import '../../world_book/pages/world_book_page.dart';
import '../../model/widgets/ocr_prompt_sheet.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

class BottomToolsSheet extends StatelessWidget {
  const BottomToolsSheet({
    super.key,
    this.onCamera,
    this.onPhotos,
    this.onUpload,
    this.onClear,
    this.clearLabel,
    this.assistantId,
    this.onSelectModel,
    this.onOpenMcp,
    this.showMcpOption = false,
  });

  final VoidCallback? onCamera;
  final VoidCallback? onPhotos;
  final VoidCallback? onUpload;
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;
  final VoidCallback? onSelectModel;
  final VoidCallback? onOpenMcp;
  final bool showMcpOption;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = Theme.of(context).colorScheme.surface;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    Widget roundedAction({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
    }) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final cardColor = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
      return Expanded(
        child: SizedBox(
          height: 72,
          child: IosCardPress(
            baseColor: cardColor,
            borderRadius: BorderRadius.circular(14),
            pressedScale: 0.98,
            duration: const Duration(milliseconds: 260),
            onTap: () {
              Haptics.light();
              onTap?.call();
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        roundedAction(
                          icon: Lucide.Camera,
                          label: l10n.bottomToolsSheetCamera,
                          onTap: onCamera,
                        ),
                        const SizedBox(width: 12),
                        roundedAction(
                          icon: Lucide.Image,
                          label: l10n.bottomToolsSheetPhotos,
                          onTap: onPhotos,
                        ),
                        const SizedBox(width: 12),
                        roundedAction(
                          icon: Lucide.Paperclip,
                          label: l10n.bottomToolsSheetUpload,
                          onTap: onUpload,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _LearningAndClearSection(
                      clearLabel: clearLabel,
                      onClear: onClear,
                      assistantId: assistantId,
                      onSelectModel: onSelectModel,
                      onOpenMcp: onOpenMcp,
                      showMcpOption: showMcpOption,
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

class _LearningAndClearSection extends StatefulWidget {
  const _LearningAndClearSection({
    this.onClear,
    this.clearLabel,
    this.assistantId,
    this.onSelectModel,
    this.onOpenMcp,
    this.showMcpOption = false,
  });
  final VoidCallback? onClear;
  final String? clearLabel;
  final String? assistantId;
  final VoidCallback? onSelectModel;
  final VoidCallback? onOpenMcp;
  final bool showMcpOption;

  @override
  State<_LearningAndClearSection> createState() =>
      _LearningAndClearSectionState();
}

class _LearningAndClearSectionState extends State<_LearningAndClearSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<WorldBookProvider>().initialize();
    });
  }

  Widget _row({
    required IconData icon,
    required String label,
    bool selected = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    final onColor = selected ? cs.primary : cs.onSurface;
    final radius = BorderRadius.circular(14);
    return SizedBox(
      height: 48,
      child: IosCardPress(
        borderRadius: radius,
        baseColor: Theme.of(context).colorScheme.surface,
        duration: const Duration(milliseconds: 260),
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: onColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.medium,
                  color: onColor,
                ),
              ),
            ),
            trailing ??
                (selected
                    ? Icon(Lucide.Check, size: 18, color: cs.primary)
                    : const SizedBox(width: 18)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final worldBookProvider = context.watch<WorldBookProvider>();
    final cs = Theme.of(context).colorScheme;
    final hasOcrModel =
        settings.ocrModelProvider != null && settings.ocrModelId != null;
    final hasWorldBooks = worldBookProvider.books.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(
          icon: Lucide.Boxes,
          label: l10n.bottomToolsSheetSelectModel,
          onTap: () {
            Haptics.light();
            // 先关掉本面板，再开模型选择——反过来会把刚开的选择器立刻 pop 掉（点不开）。
            Navigator.of(context).maybePop();
            Future.microtask(() => widget.onSelectModel?.call());
          },
          trailing: Icon(
            Lucide.ChevronRight,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
        if (widget.showMcpOption) ...[
          const SizedBox(height: 8),
          _row(
            icon: Lucide.Hammer,
            label: l10n.bottomToolsSheetMcpTools,
            onTap: () {
              Haptics.light();
              // 同上：先关本面板再开 MCP，否则会把刚开的弹层立刻 pop 掉。
              Navigator.of(context).maybePop();
              Future.microtask(() => widget.onOpenMcp?.call());
            },
            trailing: Icon(
              Lucide.ChevronRight,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _row(
          icon: Lucide.Wand2,
          label: l10n.daddySettingsStyleTitle,
          selected: false,
          onTap: () async {
            Haptics.light();
            await showStyleSheet(context);
          },
          trailing: Icon(
            Lucide.ChevronRight,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
        if (hasWorldBooks) ...[
          const SizedBox(height: 8),
          _row(
            icon: Lucide.BookOpen,
            label: l10n.worldBookTitle,
            selected: false,
            onTap: () async {
              Haptics.light();
              await showWorldBookSheet(
                context,
                assistantId: widget.assistantId,
              );
            },
            onLongPress: () {
              Haptics.light();
              final rootNav = Navigator.of(context, rootNavigator: true);
              Navigator.of(context).maybePop();
              Future.microtask(() {
                rootNav.push(
                  MaterialPageRoute(builder: (_) => const WorldBookPage()),
                );
              });
            },
            trailing: Icon(
              Lucide.ChevronRight,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
        if (hasOcrModel) ...[
          const SizedBox(height: 8),
          _row(
            icon: Lucide.Eye,
            label: l10n.bottomToolsSheetOcr,
            selected: settings.ocrEnabled,
            onTap: () async {
              Haptics.light();
              final sp = context.read<SettingsProvider>();
              await sp.setOcrEnabled(!sp.ocrEnabled);
              if (!context.mounted) return;
              Navigator.of(context).maybePop();
            },
            onLongPress: () => showOcrPromptSheet(context),
          ),
        ],
        const SizedBox(height: 8),
        _row(
          icon: Lucide.workflow,
          label: l10n.contextManagement,
          onTap: () {
            Haptics.light();
            widget.onClear?.call();
          },
          trailing: Icon(
            Lucide.ChevronRight,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
