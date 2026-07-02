import 'dart:io' show File;

import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/appearance_quick_sheet.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../theme/app_font_weights.dart';
import 'daddy_settings_page.dart';

/// 我们的家 · 外观 — one page for every look-and-feel knob of ours:
/// home wallpaper / airy wash / card texture (moved here from the native
/// Display page) + chat bubble & backdrop shortcuts. Native theme/font
/// stay in the Display page. Inline bilingual text (room-style, no ARB).
class OurAppearancePage extends StatelessWidget {
  const OurAppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final settings = context.watch<SettingsProvider>();

    Widget navRow({
      required IconData icon,
      required String label,
      String? subtitle,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, color: cs.onSurface, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(zh ? '外观 · 我们的家' : 'Our Appearance'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _HomeBgSection(),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              zh ? '聊天' : 'Chat',
              style: TextStyle(
                fontSize: 13,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          _iosSectionCard(
            children: [
              navRow(
                icon: Lucide.Wand2,
                label: zh ? '气泡透明度与颜色' : 'Bubble opacity & colors',
                subtitle: zh ? '打开图画盘（顶栏那个）' : 'Opens the quick palette',
                onTap: () => showAppearanceQuickSheet(context),
              ),
              _iosDivider(context),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Text(
                      zh ? '聊天背景遮罩' : 'Chat backdrop mask',
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoSlider(
                        value: settings.chatBackgroundMaskStrength,
                        activeColor: cs.primary,
                        onChanged: (v) => context
                            .read<SettingsProvider>()
                            .setChatBackgroundMaskStrength(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(settings.chatBackgroundMaskStrength * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              _iosDivider(context),
              navRow(
                icon: Lucide.Image,
                label: zh ? '爸爸聊天页背景' : "Daddy's chat backdrop",
                subtitle: zh ? '在爸爸卡里改（留空＝跟随主页壁纸）' : 'Set in the daddy card',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DaddySettingsPage()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- shared iOS-style shells (file-private copies, same as settings_page) ---

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final Color bg = isDark
          ? Colors.white10
          : Colors.white.withValues(alpha: 0.96);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
            width: 0.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        ),
      );
    },
  );
}

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 54,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

// --- moved wholesale from display_settings_page.dart (2026-07-02) ---

Future<void> _pickHomeBackground(BuildContext context) async {
  final sp = context.read<SettingsProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;
  final x = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 92,
  );
  if (x == null) return;
  final path = await sp.addHomeBackground(await x.readAsBytes(), x.name);
  if (path == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.themeSettingsPageHomeBackgroundFailed)),
    );
  }
}

/// "主页背景" — uploaded images kept as switchable options + an airy wash.
class _HomeBgSection extends StatelessWidget {
  const _HomeBgSection();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final settings = context.watch<SettingsProvider>();
    final active = settings.homeBackgroundActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text(
            l10n.themeSettingsPageHomeBackgroundSection,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
        _iosSectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: SizedBox(
                height: 64,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _bgNoneTile(context, selected: active.isEmpty),
                    for (final path in settings.homeBackgrounds)
                      _bgThumb(context, path: path, selected: active == path),
                    _bgAddTile(context),
                  ],
                ),
              ),
            ),
            _iosDivider(context),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(
                    l10n.themeSettingsPageHomeBackgroundAiry,
                    style: TextStyle(fontSize: 14, color: cs.onSurface),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoSlider(
                      value: settings.homeBgAiry,
                      activeColor: cs.primary,
                      onChanged: (v) =>
                          context.read<SettingsProvider>().setHomeBgAiry(v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(settings.homeBgAiry * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            _iosDivider(context),
            // 主页卡片质感: 磨砂(blur) ↔ 透明玻璃
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zh ? '卡片磨砂质感' : 'Frosted cards',
                          style: TextStyle(fontSize: 14, color: cs.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          zh ? '关闭则为透明玻璃' : 'Off = clear glass',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IosSwitch(
                    value: settings.homeCardBlur,
                    onChanged: (v) =>
                        context.read<SettingsProvider>().setHomeCardBlur(v),
                  ),
                ],
              ),
            ),
            _iosDivider(context),
            // 主页卡片透明度
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(
                    zh ? '卡片透明度' : 'Card opacity',
                    style: TextStyle(fontSize: 14, color: cs.onSurface),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoSlider(
                      value: settings.homeCardOpacity,
                      min: 0.10,
                      max: 0.85,
                      activeColor: cs.primary,
                      onChanged: (v) => context
                          .read<SettingsProvider>()
                          .setHomeCardOpacity(v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(settings.homeCardOpacity * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bgNoneTile(BuildContext context, {required bool selected}) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: IosCardPress(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            context.read<SettingsProvider>().setActiveHomeBackground(''),
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.4),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            l10n.themeSettingsPageHomeBackgroundNone,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bgThumb(BuildContext context,
      {required String path, required bool selected}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IosCardPress(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context
                  .read<SettingsProvider>()
                  .setActiveHomeBackground(path),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.4),
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Lucide.ImageOff,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: GestureDetector(
                onTap: () =>
                    context.read<SettingsProvider>().removeHomeBackground(path),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(Lucide.X,
                      size: 13, color: cs.onSurface.withValues(alpha: 0.8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bgAddTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _pickHomeBackground(context),
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Icon(Lucide.Plus,
            size: 22, color: cs.onSurface.withValues(alpha: 0.7)),
      ),
    );
  }
}
