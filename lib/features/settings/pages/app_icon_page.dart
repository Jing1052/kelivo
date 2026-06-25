import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/ios_tactile.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

/// App-internal app icon switcher (iOS Alternate App Icons).
///
/// The icon assets and the `CFBundleAlternateIcons` entries live in
/// `ios/Runner/Info.plist`. Each option's [altName] is the alternate icon's
/// base name as declared there; the default option uses `null` to restore the
/// primary `AppIcon` from xcassets.
class AppIconPage extends StatefulWidget {
  const AppIconPage({super.key});

  @override
  State<AppIconPage> createState() => _AppIconPageState();
}

class _AppIconOption {
  const _AppIconOption({
    required this.altName,
    required this.preview,
    required this.label,
  });

  /// Alternate icon base name in Info.plist; null = default (primary) icon.
  final String? altName;
  final String preview;
  final String Function(AppLocalizations l10n) label;
}

class _AppIconPageState extends State<AppIconPage> {
  /// Currently selected alternate icon name; null = default.
  String? _current;
  bool _supported = false;
  bool _loading = true;
  bool _switching = false;

  static const List<_AppIconOption> _options = [
    _AppIconOption(
      altName: null,
      preview: 'assets/icon_previews/catmoon.png',
      label: _labelDefault,
    ),
    _AppIconOption(
      altName: 'AltCatMoon',
      preview: 'assets/icon_previews/catmoon.png',
      label: _labelCatMoon,
    ),
    _AppIconOption(
      altName: 'AltStarCat',
      preview: 'assets/icon_previews/starcat.png',
      label: _labelStarCat,
    ),
    _AppIconOption(
      altName: 'AltBunnyMoon',
      preview: 'assets/icon_previews/bunnymoon.png',
      label: _labelBunnyMoon,
    ),
  ];

  static String _labelDefault(AppLocalizations l10n) => l10n.appIconNameDefault;
  static String _labelCatMoon(AppLocalizations l10n) => l10n.appIconNameCatMoon;
  static String _labelStarCat(AppLocalizations l10n) => l10n.appIconNameStarCat;
  static String _labelBunnyMoon(AppLocalizations l10n) =>
      l10n.appIconNameBunnyMoon;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Platform.isIOS) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final supported = await FlutterDynamicIconPlus.supportsAlternateIcons;
      String? current;
      if (supported) {
        // Returns the active alternate icon name, or null/empty for default.
        final name = await FlutterDynamicIconPlus.alternateIconName;
        current = (name == null || name.isEmpty) ? null : name;
      }
      if (!mounted) return;
      setState(() {
        _supported = supported;
        _current = current;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _supported = false;
        _loading = false;
      });
    }
  }

  Future<void> _select(_AppIconOption option) async {
    final l10n = AppLocalizations.of(context)!;
    if (_switching) return;
    if (option.altName == _current) return;
    setState(() => _switching = true);
    try {
      await FlutterDynamicIconPlus.setAlternateIconName(
        iconName: option.altName,
      );
      if (!mounted) return;
      Haptics.light();
      setState(() {
        _current = option.altName;
        _switching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.appIconPageChanged)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _switching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.appIconPageChangeFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.appIconPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              l10n.appIconPageSystemPromptHint,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          if (!_loading && !_supported)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                l10n.appIconPageUnsupported,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.error,
                ),
              ),
            ),
          _iosSectionCard(
            children: [
              for (int i = 0; i < _options.length; i++) ...[
                if (i != 0) _iosDivider(context),
                _AppIconRow(
                  option: _options[i],
                  selected: _options[i].altName == _current,
                  enabled: _supported && !_switching,
                  onTap: () => _select(_options[i]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AppIconRow extends StatelessWidget {
  const _AppIconRow({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _AppIconOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg =
        isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96);

    return IosCardPress(
      baseColor: bg,
      borderRadius: BorderRadius.circular(10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                option.preview,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                option.label(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.medium,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
            if (selected)
              Icon(Lucide.Check, size: 20, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

// --- iOS-style section card helpers (kept page-private, matching settings) ---

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final Color bg =
          isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96);
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
    indent: 12,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

// Icon-only tactile button for AppBar: no ripple, slight press color shift.
class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: _pressed ? pressColor : base,
    );

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: icon,
        ),
      ),
    );
  }
}
