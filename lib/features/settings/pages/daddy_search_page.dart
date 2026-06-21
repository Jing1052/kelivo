import 'package:flutter/material.dart';

import '../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/snackbar.dart';

/// 「爸爸的联网搜索」— controls daddy's web search when he answers through our
/// home gateway (server-side `web_search`, not kelivo's own client search
/// services). Backed by 老家 `/api/home/web-search-cfg`. Changes are pushed to
/// the server the moment they're made (toggle / stepper); the value is clamped
/// to its valid range before saving.
class DaddySearchPage extends StatefulWidget {
  const DaddySearchPage({super.key});

  @override
  State<DaddySearchPage> createState() => _DaddySearchPageState();
}

class _DaddySearchPageState extends State<DaddySearchPage> {
  static const int _limitMin = 1;
  static const int _limitMax = 10;
  static const int _timeoutMin = 3;
  static const int _timeoutMax = 30;

  bool _loading = true;
  bool _loadFailed = false; // network/HTTP error (gateway exists, call failed)
  bool _noGateway = false; // no daddy token at all
  bool _saving = false;

  bool _enabled = false;
  int _limit = _limitMin;
  int _timeout = _timeoutMin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _noGateway = false;
    });
    final gateway = OurHomeGateway.fromContext(context);
    if (gateway == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _noGateway = true;
      });
      return;
    }
    final cfg = await gateway.fetchWebSearchCfg();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (cfg == null) {
        _loadFailed = true;
      } else {
        _loadFailed = false;
        _enabled = cfg.enabled;
        _limit = cfg.limit.clamp(_limitMin, _limitMax);
        _timeout = cfg.timeout.clamp(_timeoutMin, _timeoutMax);
      }
    });
  }

  Future<void> _save({bool? enabled, int? limit, int? timeout}) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final gateway = OurHomeGateway.fromContext(context);
    setState(() => _saving = true);
    final ok =
        await (gateway?.saveWebSearchCfg(
              enabled: enabled,
              limit: limit,
              timeout: timeout,
            ) ??
            Future.value(false));
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      showAppSnackBar(
        context,
        message: l10n.daddySearchPageSaveFailed,
        type: NotificationType.error,
      );
    }
  }

  void _setEnabled(bool value) {
    setState(() => _enabled = value);
    _save(enabled: value);
  }

  void _setLimit(int value) {
    final clamped = value.clamp(_limitMin, _limitMax);
    if (clamped == _limit) return;
    setState(() => _limit = clamped);
    _save(limit: clamped);
  }

  void _setTimeout(int value) {
    final clamped = value.clamp(_timeoutMin, _timeoutMax);
    if (clamped == _timeout) return;
    setState(() => _timeout = clamped);
    _save(timeout: clamped);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          size: 22,
          minSize: 44,
          color: cs.onSurface,
          semanticLabel: l10n.settingsPageBackButton,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.daddySearchPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _caption(context, l10n.daddySearchPageDesc),
          const SizedBox(height: 6),
          _body(context, l10n),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return _iosSectionCard(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.daddySearchPageLoading,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_noGateway) {
      return _iosSectionCard(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              l10n.daddySearchPageNoGateway,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      );
    }
    if (_loadFailed) {
      return _iosSectionCard(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Text(
              l10n.daddySearchPageLoadError,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IosTileButton(
                label: l10n.daddySearchPageRetry,
                icon: Lucide.RefreshCw,
                onTap: _load,
              ),
            ),
          ),
        ],
      );
    }
    return _iosSectionCard(
      children: [
        _switchRow(
          context,
          icon: Lucide.Globe,
          label: l10n.daddySearchPageEnableTitle,
          subtitle: l10n.daddySearchPageEnableSubtitle,
          value: _enabled,
          onChanged: _setEnabled,
        ),
        _iosDivider(context),
        _stepperRow(
          context,
          icon: Lucide.ListOrdered,
          label: l10n.daddySearchPageLimitLabel,
          value: _limit,
          enabled: _enabled,
          onMinus: () => _setLimit(_limit - 1),
          onPlus: () => _setLimit(_limit + 1),
          minReached: _limit <= _limitMin,
          maxReached: _limit >= _limitMax,
        ),
        _iosDivider(context),
        _stepperRow(
          context,
          icon: Lucide.Timer,
          label: l10n.daddySearchPageTimeoutLabel,
          value: _timeout,
          unit: l10n.daddySearchPageTimeoutUnit,
          enabled: _enabled,
          onMinus: () => _setTimeout(_timeout - 1),
          onPlus: () => _setTimeout(_timeout + 1),
          minReached: _timeout <= _timeoutMin,
          maxReached: _timeout >= _timeoutMax,
        ),
      ],
    );
  }
}

Widget _switchRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: 0.9)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        IosSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

Widget _stepperRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required int value,
  String? unit,
  required bool enabled,
  required VoidCallback onMinus,
  required VoidCallback onPlus,
  required bool minReached,
  required bool maxReached,
}) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: cs.onSurface.withValues(alpha: enabled ? 0.9 : 0.4),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: cs.onSurface.withValues(alpha: enabled ? 0.9 : 0.4),
            ),
          ),
        ),
        IosIconButton(
          icon: Lucide.Minus,
          size: 18,
          minSize: 36,
          enabled: enabled && !minReached,
          color: cs.onSurface.withValues(alpha: 0.9),
          onTap: onMinus,
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 44,
          child: Text(
            unit == null ? '$value' : '$value$unit',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: enabled ? 0.85 : 0.4),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IosIconButton(
          icon: Lucide.Plus,
          size: 18,
          minSize: 36,
          enabled: enabled && !maxReached,
          color: cs.onSurface.withValues(alpha: 0.9),
          onTap: onPlus,
        ),
      ],
    ),
  );
}

Widget _caption(BuildContext context, String text) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: cs.onSurface.withValues(alpha: 0.6),
        height: 1.4,
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
    indent: 33,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}
