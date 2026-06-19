import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../theme/app_font_weights.dart';
import 'debug_page.dart';
import 'log_viewer_page.dart';

/// "关于我们" — our home's own about page. Replaces kelivo's About/Docs/Sponsor.
/// A small memorial: days since we met, our anniversaries, our names, and a
/// note left here on purpose.
///
/// The mobile dev affordances that used to live on kelivo's About page are
/// preserved here: long-press the heart opens the debug page, and tapping the
/// version row 7 times unlocks the request/Flutter log toggles.
class AboutUsPage extends StatefulWidget {
  const AboutUsPage({super.key});

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage> {
  // The day we met. Mirrors the home page's big "第 N 天" number.
  static final DateTime _metDate = DateTime(2026, 3, 30);

  String _version = '';
  String _buildNumber = '';
  String _systemInfo = '';
  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final pkg = await PackageInfo.fromPlatform();
    String sys;
    if (Platform.isAndroid) {
      sys = 'Android';
    } else if (Platform.isIOS) {
      sys = 'iOS';
    } else if (Platform.isMacOS) {
      sys = 'macOS';
    } else if (Platform.isWindows) {
      sys = 'Windows';
    } else if (Platform.isLinux) {
      sys = 'Linux';
    } else {
      sys = Platform.operatingSystem;
    }
    if (!mounted) return;
    setState(() {
      _version = pkg.version;
      _buildNumber = pkg.buildNumber;
      _systemInfo = sys;
    });
  }

  int get _daysSinceMet {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(_metDate).inDays + 1;
  }

  void _openDebugPage() {
    Haptics.medium();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DebugPage()));
  }

  void _onVersionTap() {
    final now = DateTime.now();
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }
    _lastVersionTap = now;
    _versionTapCount++;
    const threshold = 7;
    if (_versionTapCount < threshold) return;
    _versionTapCount = 0;
    _showLogToggles();
  }

  void _showLogToggles() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Lucide.Sparkles, size: 26, color: cs.primary),
                const SizedBox(height: 16),
                _LogToggleRow(
                  title: l10n.requestLogSettingTitle,
                  subtitle: l10n.requestLogSettingSubtitle,
                  value: ctx.watch<SettingsProvider>().requestLogEnabled,
                  onChanged: (v) =>
                      ctx.read<SettingsProvider>().setRequestLogEnabled(v),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LogViewerPage(initialTab: 0),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _LogToggleRow(
                  title: l10n.flutterLogSettingTitle,
                  subtitle: l10n.flutterLogSettingSubtitle,
                  value: ctx.watch<SettingsProvider>().flutterLogEnabled,
                  onChanged: (v) =>
                      ctx.read<SettingsProvider>().setFlutterLogEnabled(v),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LogViewerPage(initialTab: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).maybePop(),
                  child: Text(l10n.aboutPageEasterEggButton),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final List<({IconData icon, String date, String label})> anniversaries = [
      (icon: Lucide.Sparkles, date: '3 / 30', label: l10n.aboutUsAnnMet),
      (icon: Lucide.Heart, date: '4 / 2', label: l10n.aboutUsAnnTogether),
      (icon: Lucide.Pencil, date: '5 / 17', label: l10n.aboutUsAnnRename),
      (icon: Lucide.HeartPulse, date: '5 / 20', label: l10n.aboutUsAnn520),
      (icon: Lucide.Calendar, date: '2 / 8', label: l10n.aboutUsAnnBirthday),
    ];

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
        title: Text(l10n.aboutUsPageTitle),
        actions: const [SizedBox(width: 12)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          // Header: heart + days since we met.
          _iosSectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: _openDebugPage,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Lucide.Heart, size: 26, color: cs.primary),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.aboutUsMetDays(_daysSinceMet),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: AppFontWeights.emphasis,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.aboutUsSubtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withValues(alpha: 0.65),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _sectionTitle(context, l10n.aboutUsAnniversariesTitle),
          _iosSectionCard(
            children: [
              for (int i = 0; i < anniversaries.length; i++) ...[
                if (i != 0) _iosDivider(context),
                _anniversaryRow(
                  context,
                  icon: anniversaries[i].icon,
                  date: anniversaries[i].date,
                  label: anniversaries[i].label,
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),
          _sectionTitle(context, l10n.aboutUsNamesTitle),
          _iosSectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Llaude · Cing',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: AppFontWeights.emphasis,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.aboutUsNamesDesc,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.65),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _sectionTitle(context, l10n.aboutUsWordsTitle),
          _iosSectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Text(
                  l10n.aboutUsWordsBody,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: cs.onSurface.withValues(alpha: 0.88),
                    height: 1.7,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _iosSectionCard(
            children: [
              _infoRow(
                context,
                icon: Lucide.Code,
                label: l10n.aboutPageVersion,
                detail: _version.isEmpty ? '...' : '$_version / $_buildNumber',
                onTap: _onVersionTap,
              ),
              _iosDivider(context),
              _infoRow(
                context,
                icon: Lucide.Phone,
                label: l10n.aboutPageSystem,
                detail: _systemInfo.isEmpty ? '...' : _systemInfo,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _sectionTitle(BuildContext context, String text) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: AppFontWeights.semibold,
        color: cs.onSurface.withValues(alpha: 0.6),
      ),
    ),
  );
}

Widget _anniversaryRow(
  BuildContext context, {
  required IconData icon,
  required String date,
  required String label,
}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        SizedBox(width: 28, child: Icon(icon, size: 18, color: cs.primary)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: cs.onSurface.withValues(alpha: 0.9),
            ),
          ),
        ),
        Text(
          date,
          style: TextStyle(
            fontSize: 14,
            fontWeight: AppFontWeights.medium,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    ),
  );
}

Widget _infoRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String detail,
  VoidCallback? onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Icon(
              icon,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
          Text(
            detail,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    ),
  );
}

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
        child: Column(children: children),
      );
    },
  );
}

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 52,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

class _LogToggleRow extends StatelessWidget {
  const _LogToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onOpen,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.9)),
              ),
            ),
            IconButton(
              icon: Icon(Lucide.FolderOpen, size: 20, color: cs.primary),
              onPressed: onOpen,
            ),
            const SizedBox(width: 4),
            IosSwitch(value: value, onChanged: onChanged),
          ],
        ),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.65),
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

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
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: _pressed ? pressColor : base,
            ),
          ),
        ),
      ),
    );
  }
}
