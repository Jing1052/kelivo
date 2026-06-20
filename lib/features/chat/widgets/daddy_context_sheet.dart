import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';

/// Bottom sheet for daddy: inline editor for 保留条数 / 触发阈值.
///
/// Reads/writes the SAME `SettingsProvider` fields as the 爸爸 settings page
/// (`daddyKeepCount` / `daddyTriggerCount`), so the two surfaces stay in sync
/// automatically — no extra plumbing. The sheet seeds its controllers from the
/// current settings each time it opens.
///
/// Write-back mirrors `DaddySettingsPage._persist`: on each field change (and on
/// dispose) the int is parsed and pushed through `setDaddyKeepCount` /
/// `setDaddyTriggerCount`, whose clamps (keep 10..400, trigger keep+5..500) are
/// the single source of truth. After writing we re-seed the controller text from
/// the clamped value so the user sees the applied number. Empty/invalid input is
/// ignored.
class DaddyContextSheet extends StatefulWidget {
  const DaddyContextSheet({super.key});

  @override
  State<DaddyContextSheet> createState() => _DaddyContextSheetState();
}

class _DaddyContextSheetState extends State<DaddyContextSheet> {
  final TextEditingController _keepCtrl = TextEditingController();
  final TextEditingController _triggerCtrl = TextEditingController();
  late final SettingsProvider _settings;

  @override
  void initState() {
    super.initState();
    // 捕获引用，dispose 时不再 context.read（那时 element 已 deactivate，不安全）。
    _settings = context.read<SettingsProvider>();
    _keepCtrl.text = _settings.daddyKeepCount.toString();
    _triggerCtrl.text = _settings.daddyTriggerCount.toString();
  }

  @override
  void dispose() {
    // 关闭时提交一次（和爸爸设置页同款：不每键提交、不中途回填——否则输到一半就被
    // clamp 回填、根本打不进去）。setter 自带 clamp（keep 10..400，trigger keep+5..500）；
    // 下次打开 initState 再按 clamp 后的值回显。
    final keep = int.tryParse(_keepCtrl.text.trim());
    if (keep != null && keep != _settings.daddyKeepCount) {
      _settings.setDaddyKeepCount(keep);
    }
    final trigger = int.tryParse(_triggerCtrl.text.trim());
    if (trigger != null && trigger != _settings.daddyTriggerCount) {
      _settings.setDaddyTriggerCount(trigger);
    }
    _keepCtrl.dispose();
    _triggerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final bg = cs.surface;

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
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
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              l10n.daddyContextSheetTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              l10n.daddyContextSheetDesc,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
          _iosSectionCard(
            context,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: IosFormTextField(
                  label: l10n.daddySettingsKeepCountLabel,
                  controller: _keepCtrl,
                  keyboardType: TextInputType.number,
                  fieldWidth: 80,
                  outerPadding: EdgeInsets.zero,
                ),
              ),
              _caption(context, l10n.daddySettingsKeepCountDesc),
              _iosDivider(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: IosFormTextField(
                  label: l10n.daddySettingsTriggerCountLabel,
                  controller: _triggerCtrl,
                  keyboardType: TextInputType.number,
                  fieldWidth: 80,
                  outerPadding: EdgeInsets.zero,
                ),
              ),
              _caption(context, l10n.daddySettingsTriggerCountDesc),
            ],
          ),
          _caption(context, l10n.daddySettingsLongChatDesc),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
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

Widget _iosSectionCard(BuildContext context, {required List<Widget> children}) {
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
