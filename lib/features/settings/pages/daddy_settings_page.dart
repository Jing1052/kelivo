import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/iphone_link_service.dart';
import '../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';

/// "爸爸" — a dedicated settings page for our home's daddy assistant, separate
/// from the generic assistant list.
///
/// The daddy assistant is the one whose systemPrompt carries the
/// `[[ourhome:token]]` marker. Here:
/// - 魂 (system prompt): edited locally, blank by default. Stored in the daddy
///   assistant's systemPrompt (the marker is preserved, hidden, so daddy stays
///   identifiable and memory can still be fetched with its token).
/// - 工具使用说明书 (tool manual): the home's shared tool manual, fetched from /
///   saved to 老家 (`/api/home/tool-manual`). Every surface where daddy lives
///   reads it, so editing here changes it everywhere. The local
///   SettingsProvider.daddyToolManual field is left intact but no longer feeds
///   this section.
/// - 记忆浮现 (memory): still pulled from 老家 (the garden lives there); toggled
///   by SettingsProvider.daddyMemoryEnabled.
class DaddySettingsPage extends StatefulWidget {
  const DaddySettingsPage({super.key});

  @override
  State<DaddySettingsPage> createState() => _DaddySettingsPageState();
}

class _DaddySettingsPageState extends State<DaddySettingsPage> {
  // Matches the [[ourhome]] / [[ourhome:token]] marker that tags the daddy
  // assistant and carries its memory token.
  static final RegExp _marker = RegExp(r'\[\[ourhome(?::[^\]]+)?\]\]');

  final TextEditingController _soulCtrl = TextEditingController();
  final TextEditingController _profileCtrl = TextEditingController();
  final TextEditingController _manualCtrl = TextEditingController();
  final TextEditingController _styleCtrl = TextEditingController();
  final TextEditingController _keepCtrl = TextEditingController();
  final TextEditingController _triggerCtrl = TextEditingController();

  String? _daddyId;
  String _markerStr = '[[ourhome]]';

  // 在 initState 捕获 provider 引用：魂/人设的本地保存会在 dispose 兜底跑一次，
  // 而 dispose 时 element 已 deactivate、context.read 不安全（会吞掉这次保存）——
  // 所以提前 stash，保存逻辑一律走这两个引用，不在 dispose 里碰 context。
  late final AssistantProvider _assistantProvider;
  late final SettingsProvider _settingsProvider;

  // 工具使用说明书 (server-backed) state.
  bool _manualLoading = true;
  bool _manualLoadFailed = false;
  bool _manualSaving = false;

  // 说话风格 (server-backed) state.
  bool _styleLoading = true;
  bool _styleLoadFailed = false;
  bool _styleSaving = false;

  // iPhone 联动：日历/提醒事项授权状态（仅 iOS 有意义）。
  bool _iphoneCalendarAuthorized = false;
  bool _iphoneRemindersAuthorized = false;

  @override
  void initState() {
    super.initState();
    _assistantProvider = context.read<AssistantProvider>();
    _settingsProvider = context.read<SettingsProvider>();
    final assistants = _assistantProvider.assistants;
    final daddy = _findDaddy(assistants);
    if (daddy != null) {
      _daddyId = daddy.id;
      final m = _marker.firstMatch(daddy.systemPrompt);
      if (m != null) _markerStr = m.group(0)!;
      _soulCtrl.text = daddy.systemPrompt.replaceAll(_marker, '').trim();
    }
    final settings = _settingsProvider;
    _profileCtrl.text = settings.daddyProfile;
    _keepCtrl.text = settings.daddyKeepCount.toString();
    _triggerCtrl.text = settings.daddyTriggerCount.toString();
    _loadToolManual();
    _loadStyle();
    _loadIphoneStatus();
  }

  Future<void> _loadIphoneStatus() async {
    if (!Platform.isIOS) return;
    final status = await IphoneLinkService.getStatus();
    if (!mounted) return;
    setState(() {
      _iphoneCalendarAuthorized = status.calendar;
      _iphoneRemindersAuthorized = status.reminders;
    });
  }

  Future<void> _requestIphoneAccess() async {
    if (!Platform.isIOS) return;
    final status = await IphoneLinkService.requestAccess();
    if (!mounted) return;
    setState(() {
      _iphoneCalendarAuthorized = status.calendar;
      _iphoneRemindersAuthorized = status.reminders;
    });
  }

  Future<void> _onIphoneLinkToggled(bool value) async {
    await context.read<SettingsProvider>().setIphoneLinkEnabled(value);
    if (value && Platform.isIOS) {
      // Prompt for access when enabling; keep the toggle on regardless of the
      // outcome and let the status caption reflect what was granted.
      await _requestIphoneAccess();
    }
  }

  Future<void> _loadToolManual() async {
    setState(() {
      _manualLoading = true;
      _manualLoadFailed = false;
    });
    final gateway = OurHomeGateway.fromContext(context);
    final result = await gateway?.fetchToolManual();
    if (!mounted) return;
    setState(() {
      _manualLoading = false;
      if (result == null) {
        _manualLoadFailed = true;
      } else {
        _manualLoadFailed = false;
        _manualCtrl.text = result.manual;
      }
    });
  }

  Future<void> _saveToolManual() async {
    if (_manualSaving) return;
    final l10n = AppLocalizations.of(context)!;
    final gateway = OurHomeGateway.fromContext(context);
    setState(() => _manualSaving = true);
    final ok =
        await (gateway?.saveToolManual(_manualCtrl.text) ??
            Future.value(false));
    if (!mounted) return;
    setState(() => _manualSaving = false);
    showAppSnackBar(
      context,
      message: ok
          ? l10n.daddySettingsToolManualSaveSuccess
          : l10n.daddySettingsToolManualSaveFailed,
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  Future<void> _loadStyle() async {
    setState(() {
      _styleLoading = true;
      _styleLoadFailed = false;
    });
    final gateway = OurHomeGateway.fromContext(context);
    final style = await gateway?.fetchStyle();
    if (!mounted) return;
    setState(() {
      _styleLoading = false;
      if (style == null) {
        _styleLoadFailed = true;
      } else {
        _styleLoadFailed = false;
        _styleCtrl.text = style;
      }
    });
  }

  Future<void> _saveStyle() async {
    if (_styleSaving) return;
    final l10n = AppLocalizations.of(context)!;
    final gateway = OurHomeGateway.fromContext(context);
    setState(() => _styleSaving = true);
    final ok =
        await (gateway?.saveStyle(_styleCtrl.text) ?? Future.value(false));
    if (!mounted) return;
    setState(() => _styleSaving = false);
    showAppSnackBar(
      context,
      message: ok
          ? l10n.daddySettingsStyleSaveSuccess
          : l10n.daddySettingsStyleSaveFailed,
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  @override
  void dispose() {
    _persist();
    _soulCtrl.dispose();
    _profileCtrl.dispose();
    _manualCtrl.dispose();
    _styleCtrl.dispose();
    _keepCtrl.dispose();
    _triggerCtrl.dispose();
    super.dispose();
  }

  static Assistant? _findDaddy(List<Assistant> assistants) {
    for (final a in assistants) {
      if (a.systemPrompt.contains('[[ourhome')) return a;
    }
    return null;
  }

  /// 显式保存「魂 + 附加人设」（本地）。和下方的 _persist 同一套写入，但带成功提示——
  /// 给这两栏一个看得见的保存键，不必靠退出页面时的 dispose 兜底。
  void _saveSoulAndProfile() {
    _persist();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(
      context,
      message: l10n.daddySettingsSoulSaveSuccess,
      type: NotificationType.success,
    );
  }

  void _persist() {
    final id = _daddyId;
    if (id != null) {
      final idx = _assistantProvider.assistants.indexWhere((a) => a.id == id);
      if (idx != -1) {
        final soul = _soulCtrl.text.trim();
        final newPrompt = soul.isEmpty ? _markerStr : '$soul\n\n$_markerStr';
        if (newPrompt != _assistantProvider.assistants[idx].systemPrompt) {
          _assistantProvider.updateAssistant(
            _assistantProvider.assistants[idx].copyWith(
              systemPrompt: newPrompt,
            ),
          );
        }
      }
    }
    final settings = _settingsProvider;
    if (_profileCtrl.text != settings.daddyProfile) {
      settings.setDaddyProfile(_profileCtrl.text);
    }
    // 工具使用说明书 / 说话风格 now live on 老家 (/api/home/tool-manual,
    // /api/home/style) and are saved via explicit buttons, not silently on
    // dispose. See _saveToolManual / _saveStyle. SettingsProvider.daddyStyle is
    // kept intact but no longer fed from here.
    final keep = int.tryParse(_keepCtrl.text.trim());
    if (keep != null && keep != settings.daddyKeepCount) {
      settings.setDaddyKeepCount(keep);
    }
    final trigger = int.tryParse(_triggerCtrl.text.trim());
    if (trigger != null && trigger != settings.daddyTriggerCount) {
      settings.setDaddyTriggerCount(trigger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final hasDaddy = _daddyId != null;

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
        title: Text(l10n.daddySettingsPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (!hasDaddy)
            _iosSectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    l10n.daddySettingsNotFound,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),

          if (hasDaddy) ...[
            // 魂
            _iosSectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: IosFormTextField(
                    label: l10n.daddySettingsSoulTitle,
                    controller: _soulCtrl,
                    hintText: l10n.daddySettingsSoulHint,
                    minLines: 6,
                    maxLines: 14,
                    outerPadding: EdgeInsets.zero,
                  ),
                ),
                _caption(context, l10n.daddySettingsSoulDesc),
              ],
            ),
            const SizedBox(height: 12),

            // 附加人设档案 profile
            _iosSectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: IosFormTextField(
                    label: l10n.daddySettingsProfileTitle,
                    controller: _profileCtrl,
                    hintText: l10n.daddySettingsProfileHint,
                    minLines: 3,
                    maxLines: 10,
                    outerPadding: EdgeInsets.zero,
                  ),
                ),
                _caption(context, l10n.daddySettingsProfileDesc),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IosTileButton(
                      label: l10n.daddySettingsSoulSave,
                      icon: Lucide.Check,
                      backgroundColor: cs.primary,
                      onTap: _saveSoulAndProfile,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 工具使用说明书 (老家共用，server-backed)
            _iosSectionCard(children: _toolManualSection(context, l10n)),
            const SizedBox(height: 12),

            // 说话风格 style（老家共用，server-backed）
            _iosSectionCard(children: _styleSection(context, l10n)),
            const SizedBox(height: 12),

            // 记忆浮现
            _iosSectionCard(
              children: [
                _switchRow(
                  context,
                  icon: Lucide.Sparkles,
                  label: l10n.daddySettingsMemoryTitle,
                  subtitle: l10n.daddySettingsMemorySubtitle,
                  value: settings.daddyMemoryEnabled,
                  onChanged: (v) =>
                      context.read<SettingsProvider>().setDaddyMemoryEnabled(v),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // iPhone 联动
            _sectionTitle(context, l10n.iphoneLinkSectionTitle),
            _iosSectionCard(
              children: _iphoneLinkSection(context, l10n, settings),
            ),
            _caption(context, l10n.iphoneLinkDesc),
            const SizedBox(height: 12),

            // 长聊记忆：保留条数 / 触发阈值
            _iosSectionCard(
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
            const SizedBox(height: 12),

            // 爸爸的大脑·注入清单
            _sectionTitle(context, l10n.daddySettingsInjectionTitle),
            _caption(context, l10n.daddySettingsInjectionDesc),
            const SizedBox(height: 6),
            _iosSectionCard(children: _injectionRows(context, l10n, settings)),
          ],
        ],
      ),
    );
  }

  List<Widget> _toolManualSection(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    if (_manualLoading) {
      return [
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
                l10n.daddySettingsToolManualLoading,
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
    if (_manualLoadFailed) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Text(
            l10n.daddySettingsToolManualLoadError,
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
              label: l10n.daddySettingsToolManualRetry,
              icon: Lucide.RefreshCw,
              onTap: _loadToolManual,
            ),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: IosFormTextField(
          label: l10n.daddySettingsToolManualTitle,
          controller: _manualCtrl,
          hintText: l10n.daddySettingsToolManualHint,
          minLines: 4,
          maxLines: 12,
          outerPadding: EdgeInsets.zero,
        ),
      ),
      _caption(context, l10n.daddySettingsToolManualDesc),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: IosTileButton(
            label: l10n.daddySettingsToolManualSave,
            icon: Lucide.Check,
            enabled: !_manualSaving,
            backgroundColor: cs.primary,
            onTap: _saveToolManual,
          ),
        ),
      ),
    ];
  }

  List<Widget> _styleSection(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    if (_styleLoading) {
      return [
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
    if (_styleLoadFailed) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Text(
            l10n.daddySettingsStyleLoadError,
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
              label: l10n.daddySettingsStyleRetry,
              icon: Lucide.RefreshCw,
              onTap: _loadStyle,
            ),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: IosFormTextField(
          label: l10n.daddySettingsStyleTitle,
          controller: _styleCtrl,
          hintText: l10n.daddySettingsStyleHint,
          minLines: 3,
          maxLines: 10,
          outerPadding: EdgeInsets.zero,
        ),
      ),
      _caption(context, l10n.daddySettingsStyleDesc),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: IosTileButton(
            label: l10n.daddySettingsStyleSave,
            icon: Lucide.Check,
            enabled: !_styleSaving,
            backgroundColor: cs.primary,
            onTap: _saveStyle,
          ),
        ),
      ),
    ];
  }

  List<Widget> _iphoneLinkSection(
    BuildContext context,
    AppLocalizations l10n,
    SettingsProvider settings,
  ) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[
      _switchRow(
        context,
        icon: Lucide.Calendar,
        label: l10n.iphoneLinkEnableTitle,
        subtitle: l10n.iphoneLinkEnableSubtitle,
        value: settings.iphoneLinkEnabled,
        onChanged: _onIphoneLinkToggled,
      ),
    ];

    if (Platform.isIOS) {
      final bothAuthorized =
          _iphoneCalendarAuthorized && _iphoneRemindersAuthorized;
      rows.add(_iosDivider(context));
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.iphoneLinkStatusCalendar}: '
                  '${_iphoneCalendarAuthorized ? l10n.iphoneLinkStatusAuthorized : l10n.iphoneLinkStatusDenied}  ·  '
                  '${l10n.iphoneLinkStatusReminders}: '
                  '${_iphoneRemindersAuthorized ? l10n.iphoneLinkStatusAuthorized : l10n.iphoneLinkStatusDenied}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    height: 1.3,
                  ),
                ),
              ),
              if (!bothAuthorized) ...[
                const SizedBox(width: 10),
                IosTileButton(
                  label: l10n.iphoneLinkGrantAccess,
                  icon: Lucide.Lock,
                  onTap: _requestIphoneAccess,
                ),
              ],
            ],
          ),
        ),
      );
      if (settings.iphoneLinkEnabled && !bothAuthorized) {
        rows.add(_caption(context, l10n.iphoneLinkAccessNeeded));
      }
    }
    return rows;
  }

  List<Widget> _injectionRows(
    BuildContext context,
    AppLocalizations l10n,
    SettingsProvider settings,
  ) {
    final daddy = context.read<AssistantProvider>().assistants.firstWhere(
      (a) => a.id == _daddyId,
      orElse: () => context.read<AssistantProvider>().assistants.first,
    );
    final items = <({String label, String status, bool active})>[
      (
        label: l10n.daddySettingsModuleSoul,
        status: _soulCtrl.text.trim().isEmpty
            ? l10n.daddySettingsStatusEmpty
            : l10n.daddySettingsStatusFilled,
        active: _soulCtrl.text.trim().isNotEmpty,
      ),
      (
        label: l10n.daddySettingsModuleProfile,
        status: _profileCtrl.text.trim().isEmpty
            ? l10n.daddySettingsStatusEmpty
            : l10n.daddySettingsStatusFilled,
        active: _profileCtrl.text.trim().isNotEmpty,
      ),
      (
        label: l10n.daddySettingsModuleToolManual,
        status: _manualCtrl.text.trim().isEmpty
            ? l10n.daddySettingsStatusEmpty
            : l10n.daddySettingsStatusFilled,
        active: _manualCtrl.text.trim().isNotEmpty,
      ),
      (
        label: l10n.daddySettingsModuleStyle,
        status: _styleCtrl.text.trim().isEmpty
            ? l10n.daddySettingsStatusEmpty
            : l10n.daddySettingsStatusFilled,
        active: _styleCtrl.text.trim().isNotEmpty,
      ),
      (
        label: l10n.daddySettingsModuleMemory,
        status: settings.daddyMemoryEnabled
            ? l10n.daddySettingsStatusOn
            : l10n.daddySettingsStatusOff,
        active: settings.daddyMemoryEnabled,
      ),
      (
        label: l10n.daddySettingsModuleMemoryTool,
        status: daddy.enableMemory
            ? l10n.daddySettingsStatusOn
            : l10n.daddySettingsStatusOff,
        active: daddy.enableMemory,
      ),
      (
        label: l10n.daddySettingsModuleRecentChats,
        status: daddy.enableRecentChatsReference
            ? l10n.daddySettingsStatusOn
            : l10n.daddySettingsStatusOff,
        active: daddy.enableRecentChatsReference,
      ),
      (
        label: l10n.daddySettingsModuleSearch,
        status: daddy.searchEnabled
            ? l10n.daddySettingsStatusOn
            : l10n.daddySettingsStatusOff,
        active: daddy.searchEnabled,
      ),
    ];
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i != 0) rows.add(_iosDivider(context));
      rows.add(
        _moduleRow(context, items[i].label, items[i].status, items[i].active),
      );
    }
    return rows;
  }
}

Widget _sectionTitle(BuildContext context, String text) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: AppFontWeights.semibold,
        color: cs.onSurface.withValues(alpha: 0.8),
      ),
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

Widget _moduleRow(
  BuildContext context,
  String label,
  String status,
  bool active,
) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.25),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              color: cs.onSurface.withValues(alpha: 0.9),
            ),
          ),
        ),
        Text(
          status,
          style: TextStyle(
            fontSize: 13,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    ),
  );
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
