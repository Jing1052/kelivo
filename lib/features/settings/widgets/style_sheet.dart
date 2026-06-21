import 'package:flutter/material.dart';

import '../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';

/// 说话风格 — the home's shared speaking style (爸爸 across all surfaces uses
/// it), edited from a single shared bottom sheet. Loads from / saves to 老家
/// (`/api/home/style`) via [OurHomeGateway]. Reused by the chat "+" menu and the
/// settings page, so the style lives in exactly one place.
class StyleSheet extends StatefulWidget {
  const StyleSheet({super.key});

  @override
  State<StyleSheet> createState() => _StyleSheetState();
}

class _StyleSheetState extends State<StyleSheet> {
  final TextEditingController _styleCtrl = TextEditingController();

  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _styleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final gateway = OurHomeGateway.fromContext(context);
    // 先用本地缓存秒显（有就不转圈），再后台拉老家刷新（stale-while-revalidate）。
    final cached = gateway?.peekStyle();
    setState(() {
      _loadFailed = false;
      if (cached != null) {
        _styleCtrl.text = cached;
        _loading = false;
      } else {
        _loading = true;
      }
    });
    final style = await gateway?.fetchStyle();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (style == null) {
        if (cached == null) _loadFailed = true;
      } else {
        _loadFailed = false;
        _styleCtrl.text = style;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final gateway = OurHomeGateway.fromContext(context);
    setState(() => _saving = true);
    final ok =
        await (gateway?.saveStyle(_styleCtrl.text) ?? Future.value(false));
    if (!mounted) return;
    setState(() => _saving = false);
    showAppSnackBar(
      context,
      message: ok
          ? l10n.daddySettingsStyleSaveSuccess
          : l10n.daddySettingsStyleSaveFailed,
      type: ok ? NotificationType.success : NotificationType.error,
    );
    if (ok && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.daddySettingsStyleTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: AppFontWeights.semibold,
              ),
            ),
            const SizedBox(height: 12),
            ..._body(context, l10n),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
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
                l10n.daddySettingsStyleLoading,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    if (_loadFailed) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.daddySettingsStyleLoadError,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.7),
              height: 1.4,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: IosTileButton(
            label: l10n.daddySettingsStyleRetry,
            icon: Lucide.RefreshCw,
            onTap: _load,
          ),
        ),
      ];
    }
    return [
      IosFormTextField(
        label: l10n.daddySettingsStyleTitle,
        controller: _styleCtrl,
        hintText: l10n.daddySettingsStyleHint,
        minLines: 3,
        maxLines: 10,
        outerPadding: EdgeInsets.zero,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          l10n.daddySettingsStyleDesc,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.6),
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Spacer(),
          IosTileButton(
            label: l10n.daddySettingsStyleSave,
            icon: Lucide.Check,
            enabled: !_saving,
            backgroundColor: cs.primary,
            onTap: _save,
          ),
        ],
      ),
    ];
  }
}

/// Shows the shared 说话风格 bottom sheet.
Future<void> showStyleSheet(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const StyleSheet(),
  );
}
