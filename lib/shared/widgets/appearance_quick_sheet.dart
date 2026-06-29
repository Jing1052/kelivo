import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../icons/lucide_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/palettes.dart';
import '../../theme/app_font_weights.dart';
import '../../features/settings/pages/theme_settings_page.dart';
import 'bubble_color_picker_sheet.dart';
import 'ios_tactile.dart';

/// 页面右上角的「外观快捷调节」按钮。点开一个 bottom sheet，
/// 即时切换：颜色模式 / 皮肤 / 聊天气泡背景。复用 SettingsProvider 现有设置，
/// 不引入任何新的持久化字段。
class AppearanceQuickButton extends StatelessWidget {
  const AppearanceQuickButton({super.key, this.size = 20, this.minSize = 44});

  final double size;
  final double minSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IosIconButton(
      size: size,
      minSize: minSize,
      icon: Lucide.Palette,
      semanticLabel: l10n.appearanceQuickButtonTooltip,
      onTap: () => showAppearanceQuickSheet(context),
    );
  }
}

Future<void> showAppearanceQuickSheet(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _AppearanceQuickSheet(),
  );
}

class _AppearanceQuickSheet extends StatelessWidget {
  const _AppearanceQuickSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                l10n.appearanceQuickSheetTitle,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
            ),

            // 颜色模式
            _sectionLabel(context, l10n.settingsPageColorMode),
            _SegmentedRow(
              options: [
                _SegOption(
                  icon: Lucide.Monitor,
                  label: l10n.settingsPageSystemMode,
                  selected: settings.themeMode == ThemeMode.system,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setThemeMode(ThemeMode.system),
                ),
                _SegOption(
                  icon: Lucide.Sun,
                  label: l10n.settingsPageLightMode,
                  selected: settings.themeMode == ThemeMode.light,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setThemeMode(ThemeMode.light),
                ),
                _SegOption(
                  icon: Lucide.Moon,
                  label: l10n.settingsPageDarkMode,
                  selected: settings.themeMode == ThemeMode.dark,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setThemeMode(ThemeMode.dark),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 皮肤
            _sectionLabel(context, l10n.themeSettingsPageColorPalettesSection),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: ThemePalettes.all.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (c, i) {
                  final p = ThemePalettes.all[i];
                  final selected = settings.themePaletteId == p.id;
                  return _PaletteDot(
                    color: p.light.primary,
                    selected: selected,
                    onTap: () =>
                        context.read<SettingsProvider>().setThemePalette(p.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // 聊天气泡背景
            _sectionLabel(
              context,
              l10n.displaySettingsPageChatMessageBackgroundTitle,
            ),
            _SegmentedRow(
              options: [
                _SegOption(
                  label: l10n.displaySettingsPageChatMessageBackgroundDefault,
                  selected: settings.chatMessageBackgroundStyle ==
                      ChatMessageBackgroundStyle.defaultStyle,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setChatMessageBackgroundStyle(
                        ChatMessageBackgroundStyle.defaultStyle,
                      ),
                ),
                _SegOption(
                  label: l10n.displaySettingsPageChatMessageBackgroundFrosted,
                  selected: settings.chatMessageBackgroundStyle ==
                      ChatMessageBackgroundStyle.frosted,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setChatMessageBackgroundStyle(
                        ChatMessageBackgroundStyle.frosted,
                      ),
                ),
                _SegOption(
                  label: l10n.displaySettingsPageChatMessageBackgroundSolid,
                  selected: settings.chatMessageBackgroundStyle ==
                      ChatMessageBackgroundStyle.solid,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setChatMessageBackgroundStyle(
                        ChatMessageBackgroundStyle.solid,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 气泡形状
            _sectionLabel(
              context,
              l10n.displaySettingsPageChatBubbleShapeTitle,
            ),
            _SegmentedRow(
              options: [
                _SegOption(
                  label: l10n.displaySettingsPageChatBubbleShapeRound,
                  selected: settings.chatBubbleShape == ChatBubbleShape.round,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setChatBubbleShape(ChatBubbleShape.round),
                ),
                _SegOption(
                  label: l10n.displaySettingsPageChatBubbleShapeStandard,
                  selected: settings.chatBubbleShape == ChatBubbleShape.standard,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setChatBubbleShape(ChatBubbleShape.standard),
                ),
                _SegOption(
                  label: l10n.displaySettingsPageChatBubbleShapeSharp,
                  selected: settings.chatBubbleShape == ChatBubbleShape.sharp,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setChatBubbleShape(ChatBubbleShape.sharp),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 按钮形状
            _sectionLabel(
              context,
              l10n.displaySettingsPageButtonShapeTitle,
            ),
            _SegmentedRow(
              options: [
                _SegOption(
                  label: l10n.displaySettingsPageButtonShapeRounded,
                  selected: settings.appButtonShape == AppButtonShape.rounded,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setAppButtonShape(AppButtonShape.rounded),
                ),
                _SegOption(
                  label: l10n.displaySettingsPageButtonShapePill,
                  selected: settings.appButtonShape == AppButtonShape.pill,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setAppButtonShape(AppButtonShape.pill),
                ),
                _SegOption(
                  label: l10n.displaySettingsPageButtonShapeSquare,
                  selected: settings.appButtonShape == AppButtonShape.square,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setAppButtonShape(AppButtonShape.square),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 气泡透明度（我和爸爸共用一个，保持一致）
            _sectionLabel(
              context,
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '气泡透明度'
                  : 'Bubble opacity',
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: settings.chatBubbleOpacity.clamp(0.3, 1.0),
                    min: 0.3,
                    max: 1.0,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .setChatBubbleOpacity(v),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(settings.chatBubbleOpacity * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 气泡颜色（各选各的：我的气泡 / 爸爸的气泡；透明度共用上面那个）
            _sectionLabel(
              context,
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '气泡颜色'
                  : 'Bubble color',
            ),
            _BubbleColorRow(
              label: Localizations.localeOf(context).languageCode == 'zh'
                  ? '我的气泡'
                  : 'My bubble',
              color: settings.userBubbleColor,
              fallback: cs.primary,
              onPicked: (c) =>
                  context.read<SettingsProvider>().setUserBubbleColor(c),
            ),
            const SizedBox(height: 8),
            _BubbleColorRow(
              label: Localizations.localeOf(context).languageCode == 'zh'
                  ? '爸爸的气泡'
                  : "Daddy's bubble",
              color: settings.assistantBubbleColor,
              fallback: Theme.of(context).brightness == Brightness.dark
                  ? cs.surfaceContainerHighest
                  : cs.surfaceContainerLowest,
              onPicked: (c) =>
                  context.read<SettingsProvider>().setAssistantBubbleColor(c),
            ),
            const SizedBox(height: 12),

            // 更多外观设置
            _MoreRow(
              label: l10n.appearanceQuickSheetMore,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ThemeSettingsPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: AppFontWeights.medium,
          color: cs.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _SegOption {
  const _SegOption({
    this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

class _SegmentedRow extends StatelessWidget {
  const _SegmentedRow({required this.options});
  final List<_SegOption> options;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: _SegChip(option: o),
            ),
        ],
      ),
    );
  }
}

class _SegChip extends StatelessWidget {
  const _SegChip({required this.option});
  final _SegOption option;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = option.selected;
    final fg = selected ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.85);
    return IosCardPress(
      onTap: option.onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (option.icon != null) ...[
              Icon(option.icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected
                      ? AppFontWeights.semibold
                      : AppFontWeights.regular,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteDot extends StatelessWidget {
  const _PaletteDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: cs.primary, width: 2.5)
              : Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: selected
                ? Icon(Lucide.Check, size: 16, color: _onColor(color))
                : null,
          ),
        ),
      ),
    );
  }

  Color _onColor(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
  }
}

/// One row in the 气泡颜色 section: a label + a color dot. Tapping opens the
/// free HSV picker; [color] null means "follow theme" (shows [fallback]).
class _BubbleColorRow extends StatelessWidget {
  const _BubbleColorRow({
    required this.label,
    required this.color,
    required this.fallback,
    required this.onPicked,
  });
  final String label;
  final Color? color;
  final Color fallback;
  final ValueChanged<Color?> onPicked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final shown = color ?? fallback;
    return IosCardPress(
      onTap: () async {
        final res = await showBubbleColorPicker(
          context,
          initial: color ?? fallback,
          title: label,
        );
        if (res == null) return; // dismissed → no change
        onPicked(res.reset ? null : res.color);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: shown,
                shape: BoxShape.circle,
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: cs.onSurface),
              ),
            ),
            Text(
              color == null
                  ? (isZh ? '默认' : 'Default')
                  : (isZh ? '自定义' : 'Custom'),
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Lucide.ChevronRight,
              size: 16,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(Lucide.Settings2, size: 18, color: cs.onSurface.withValues(alpha: 0.8)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: cs.onSurface),
              ),
            ),
            Icon(Lucide.ChevronRight, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
