import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../core/services/iphone_link_service.dart';
import '../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/widgets/assistant_avatar.dart';
import '../../../shared/widgets/emoji_picker_dialog.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
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

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _soulCtrl = TextEditingController();
  final TextEditingController _profileCtrl = TextEditingController();
  final TextEditingController _manualCtrl = TextEditingController();
  final TextEditingController _memoryPromptCtrl = TextEditingController();
  final TextEditingController _recapPromptCtrl = TextEditingController();
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

  // 整理记忆提示词 (server-backed) state.
  bool _memoryPromptLoading = true;
  bool _memoryPromptLoadFailed = false;
  bool _memoryPromptSaving = false;

  // 前情提要提示词 (server-backed) state.
  bool _recapPromptLoading = true;
  bool _recapPromptLoadFailed = false;
  bool _recapPromptSaving = false;

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
      _nameCtrl.text = daddy.name;
      final m = _marker.firstMatch(daddy.systemPrompt);
      if (m != null) _markerStr = m.group(0)!;
      _soulCtrl.text = daddy.systemPrompt.replaceAll(_marker, '').trim();
    }
    final settings = _settingsProvider;
    _profileCtrl.text = settings.daddyProfile;
    _keepCtrl.text = settings.daddyKeepCount.toString();
    _triggerCtrl.text = settings.daddyTriggerCount.toString();
    _loadToolManual();
    _loadMemoryPrompt();
    _loadRecapPrompt();
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

  Future<void> _loadMemoryPrompt() async {
    setState(() {
      _memoryPromptLoading = true;
      _memoryPromptLoadFailed = false;
    });
    final gateway = OurHomeGateway.fromContext(context);
    final result = await gateway?.fetchMemoryPrompt();
    if (!mounted) return;
    setState(() {
      _memoryPromptLoading = false;
      if (result == null) {
        _memoryPromptLoadFailed = true;
      } else {
        _memoryPromptLoadFailed = false;
        _memoryPromptCtrl.text = result.prompt;
      }
    });
  }

  Future<void> _saveMemoryPrompt() async {
    if (_memoryPromptSaving) return;
    final l10n = AppLocalizations.of(context)!;
    final gateway = OurHomeGateway.fromContext(context);
    setState(() => _memoryPromptSaving = true);
    final ok =
        await (gateway?.saveMemoryPrompt(_memoryPromptCtrl.text) ??
            Future.value(false));
    if (!mounted) return;
    setState(() => _memoryPromptSaving = false);
    showAppSnackBar(
      context,
      message: ok
          ? l10n.daddySettingsMemoryPromptSaveSuccess
          : l10n.daddySettingsMemoryPromptSaveFailed,
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  Future<void> _loadRecapPrompt() async {
    setState(() {
      _recapPromptLoading = true;
      _recapPromptLoadFailed = false;
    });
    final gateway = OurHomeGateway.fromContext(context);
    final result = await gateway?.fetchRecapPrompt();
    if (!mounted) return;
    setState(() {
      _recapPromptLoading = false;
      if (result == null) {
        _recapPromptLoadFailed = true;
      } else {
        _recapPromptLoadFailed = false;
        _recapPromptCtrl.text = result.prompt;
      }
    });
  }

  Future<void> _saveRecapPrompt() async {
    if (_recapPromptSaving) return;
    final l10n = AppLocalizations.of(context)!;
    final gateway = OurHomeGateway.fromContext(context);
    setState(() => _recapPromptSaving = true);
    final ok =
        await (gateway?.saveRecapPrompt(_recapPromptCtrl.text) ??
            Future.value(false));
    if (!mounted) return;
    setState(() => _recapPromptSaving = false);
    showAppSnackBar(
      context,
      message: ok
          ? l10n.daddySettingsRecapPromptSaveSuccess
          : l10n.daddySettingsRecapPromptSaveFailed,
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  @override
  void dispose() {
    _persist();
    _nameCtrl.dispose();
    _soulCtrl.dispose();
    _profileCtrl.dispose();
    _manualCtrl.dispose();
    _memoryPromptCtrl.dispose();
    _recapPromptCtrl.dispose();
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
    // 工具使用说明书 / 整理记忆 / 前情提要提示词 now live on 老家
    // (/api/home/tool-manual, /api/home/memory-prompt, /api/home/recap-prompt)
    // and are saved via explicit buttons, not silently on dispose. See
    // _saveToolManual / _saveMemoryPrompt / _saveRecapPrompt. 说话风格 moved out
    // to the shared StyleSheet (chat "+" menu + settings entry).
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
    // Watch so the basic section (avatar / temperature / stream) reflects edits
    // immediately after updateAssistant.
    context.watch<AssistantProvider>();
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
            // 基础：头像 / 名字 / 温度 / 流式输出（直接改这个爸爸助手）
            _sectionTitle(context, l10n.daddySettingsBasicSectionTitle),
            _iosSectionCard(children: _basicSection(context, l10n)),
            const SizedBox(height: 12),

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

            // 整理记忆提示词（老家共用，server-backed）
            _iosSectionCard(children: _memoryPromptSection(context, l10n)),
            const SizedBox(height: 12),

            // 前情提要提示词（老家共用，server-backed）
            _iosSectionCard(children: _recapPromptSection(context, l10n)),
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

  /// Generic server-backed prompt section (loading / error+retry / editor),
  /// mirroring [_toolManualSection]. Used for both 整理记忆 and 前情提要 prompts.
  List<Widget> _promptSection(
    BuildContext context, {
    required bool loading,
    required bool loadFailed,
    required bool saving,
    required String title,
    required String hint,
    required String desc,
    required String loadingText,
    required String loadErrorText,
    required String retryLabel,
    required String saveLabel,
    required TextEditingController controller,
    required VoidCallback onRetry,
    required VoidCallback onSave,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (loading) {
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
                loadingText,
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
    if (loadFailed) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Text(
            loadErrorText,
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
              label: retryLabel,
              icon: Lucide.RefreshCw,
              onTap: onRetry,
            ),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: IosFormTextField(
          label: title,
          controller: controller,
          hintText: hint,
          minLines: 4,
          maxLines: 12,
          outerPadding: EdgeInsets.zero,
        ),
      ),
      _caption(context, desc),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: IosTileButton(
            label: saveLabel,
            icon: Lucide.Check,
            enabled: !saving,
            backgroundColor: cs.primary,
            onTap: onSave,
          ),
        ),
      ),
    ];
  }

  List<Widget> _memoryPromptSection(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return _promptSection(
      context,
      loading: _memoryPromptLoading,
      loadFailed: _memoryPromptLoadFailed,
      saving: _memoryPromptSaving,
      title: l10n.daddySettingsMemoryPromptTitle,
      hint: l10n.daddySettingsMemoryPromptHint,
      desc: l10n.daddySettingsMemoryPromptDesc,
      loadingText: l10n.daddySettingsMemoryPromptLoading,
      loadErrorText: l10n.daddySettingsMemoryPromptLoadError,
      retryLabel: l10n.daddySettingsMemoryPromptRetry,
      saveLabel: l10n.daddySettingsMemoryPromptSave,
      controller: _memoryPromptCtrl,
      onRetry: _loadMemoryPrompt,
      onSave: _saveMemoryPrompt,
    );
  }

  List<Widget> _recapPromptSection(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return _promptSection(
      context,
      loading: _recapPromptLoading,
      loadFailed: _recapPromptLoadFailed,
      saving: _recapPromptSaving,
      title: l10n.daddySettingsRecapPromptTitle,
      hint: l10n.daddySettingsRecapPromptHint,
      desc: l10n.daddySettingsRecapPromptDesc,
      loadingText: l10n.daddySettingsRecapPromptLoading,
      loadErrorText: l10n.daddySettingsRecapPromptLoadError,
      retryLabel: l10n.daddySettingsRecapPromptRetry,
      saveLabel: l10n.daddySettingsRecapPromptSave,
      controller: _recapPromptCtrl,
      onRetry: _loadRecapPrompt,
      onSave: _saveRecapPrompt,
    );
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

  /// 当前爸爸助手对象。仅在 hasDaddy（_daddyId != null）时调用。
  Assistant _daddy() {
    return _assistantProvider.assistants.firstWhere((a) => a.id == _daddyId);
  }

  /// 基础 section：头像 / 名字 / 温度 / 流式输出。都直接改这个爸爸助手。
  /// 头像选择、温度交互照搬通用助手页（assistant_settings_edit_basic_tab.dart），
  /// 存储格式（avatar 字段：本地路径 / emoji / url）与那边完全一致。
  List<Widget> _basicSection(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final daddy = _daddy();
    return [
      // 头像
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _showAvatarPicker(context),
              child: AssistantAvatar(
                assistant: daddy,
                fallbackName: '爸',
                size: 56,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.daddySettingsAvatarTitle,
                    style: TextStyle(
                      fontSize: 15,
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.daddySettingsUseAssistantAvatarSubtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            IosSwitch(
              value: daddy.useAssistantAvatar,
              onChanged: (v) => _assistantProvider.updateAssistant(
                daddy.copyWith(useAssistantAvatar: v),
              ),
            ),
          ],
        ),
      ),
      _iosDivider(context),
      // 名字
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: IosFormTextField(
          label: l10n.daddySettingsNameTitle,
          controller: _nameCtrl,
          hintText: l10n.daddySettingsNameHint,
          outerPadding: EdgeInsets.zero,
          onChanged: (v) =>
              _assistantProvider.updateAssistant(_daddy().copyWith(name: v)),
        ),
      ),
      _iosDivider(context),
      // 温度
      _iosNavRow(
        context,
        icon: Lucide.Thermometer,
        label: l10n.daddySettingsTemperatureTitle,
        detailText: daddy.temperature != null
            ? daddy.temperature!.toStringAsFixed(2)
            : l10n.assistantEditParameterDisabled,
        onTap: () => _showTemperatureSheet(context),
      ),
      _caption(context, l10n.daddySettingsTemperatureDesc),
      _iosDivider(context),
      // 流式输出
      _switchRow(
        context,
        icon: Lucide.Zap,
        label: l10n.daddySettingsStreamOutputTitle,
        value: daddy.streamOutput,
        onChanged: (v) => _assistantProvider.updateAssistant(
          _daddy().copyWith(streamOutput: v),
        ),
      ),
    ];
  }

  Future<void> _showAvatarPicker(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final maxH = MediaQuery.of(ctx).size.height * 0.8;
        Widget row(String text, Future<void> Function() action) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(
              height: 48,
              child: IosCardPress(
                borderRadius: BorderRadius.circular(14),
                baseColor: cs.surface,
                duration: const Duration(milliseconds: 260),
                onTap: () async {
                  Haptics.light();
                  Navigator.of(ctx).pop();
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                  await action();
                },
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.medium,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                    const SizedBox(height: 10),
                    row(
                      l10n.assistantEditAvatarChooseImage,
                      () async => _pickLocalImage(context),
                    ),
                    row(l10n.assistantEditAvatarChooseEmoji, () async {
                      final emoji = await showEmojiPickerDialog(context);
                      if (!context.mounted || emoji == null) return;
                      await _assistantProvider.updateAssistant(
                        _daddy().copyWith(avatar: emoji),
                      );
                    }),
                    row(
                      l10n.assistantEditAvatarEnterLink,
                      () async => _inputAvatarUrl(context),
                    ),
                    row(
                      l10n.assistantEditAvatarImportQQ,
                      () async => _inputQQAvatar(context),
                    ),
                    row(l10n.assistantEditAvatarReset, () async {
                      await _assistantProvider.updateAssistant(
                        _daddy().copyWith(clearAvatar: true),
                      );
                    }),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickLocalImage(BuildContext context) async {
    if (kIsWeb) {
      await _inputAvatarUrl(context);
      return;
    }
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 90,
      );
      if (file == null) return;
      await _assistantProvider.updateAssistant(
        _daddy().copyWith(avatar: file.path),
      );
    } on PlatformException {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.assistantEditGalleryErrorMessage,
        type: NotificationType.error,
      );
      await _inputAvatarUrl(context);
    } catch (_) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.assistantEditGeneralErrorMessage,
        type: NotificationType.error,
      );
      await _inputAvatarUrl(context);
    }
  }

  Future<void> _inputAvatarUrl(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        bool valid(String s) =>
            s.trim().startsWith('http://') || s.trim().startsWith('https://');
        String value = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: cs.surface,
              title: Text(l10n.assistantEditImageUrlDialogTitle),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.assistantEditImageUrlDialogHint,
                  filled: true,
                  fillColor: Theme.of(ctx).brightness == Brightness.dark
                      ? Colors.white10
                      : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                onChanged: (v) => setLocal(() => value = v),
                onSubmitted: (_) {
                  if (valid(value)) Navigator.of(ctx).pop(true);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.assistantEditImageUrlDialogCancel),
                ),
                TextButton(
                  onPressed: valid(value)
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  child: Text(
                    l10n.assistantEditImageUrlDialogSave,
                    style: TextStyle(
                      color: valid(value)
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.38),
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true) {
      final url = controller.text.trim();
      if (url.isEmpty) return;
      await _assistantProvider.updateAssistant(_daddy().copyWith(avatar: url));
    }
  }

  Future<void> _inputQQAvatar(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        String value = '';
        bool valid(String s) => RegExp(r'^[0-9]{5,12}$').hasMatch(s.trim());
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: cs.surface,
              title: Text(l10n.assistantEditQQAvatarDialogTitle),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: l10n.assistantEditQQAvatarDialogHint,
                  filled: true,
                  fillColor: Theme.of(ctx).brightness == Brightness.dark
                      ? Colors.white10
                      : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                onChanged: (v) => setLocal(() => value = v),
                onSubmitted: (_) {
                  if (valid(value)) Navigator.of(ctx).pop(true);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.assistantEditQQAvatarDialogCancel),
                ),
                TextButton(
                  onPressed: valid(value)
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  child: Text(
                    l10n.assistantEditQQAvatarDialogSave,
                    style: TextStyle(
                      color: valid(value)
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.38),
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true) {
      final qq = controller.text.trim();
      if (qq.isEmpty) return;
      final url = 'https://q2.qlogo.cn/headimg_dl?dst_uin=$qq&spec=100';
      await _assistantProvider.updateAssistant(_daddy().copyWith(avatar: url));
    }
  }

  Future<void> _showTemperatureSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Builder(
              builder: (context) {
                final cs = Theme.of(context).colorScheme;
                final daddy = context
                    .watch<AssistantProvider>()
                    .assistants
                    .firstWhere((a) => a.id == _daddyId);
                final value = daddy.temperature ?? 0.6;
                return Column(
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.daddySettingsTemperatureTitle,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: AppFontWeights.semibold,
                            ),
                          ),
                        ),
                        IosSwitch(
                          value: daddy.temperature != null,
                          onChanged: (v) async {
                            final navigator = Navigator.of(ctx);
                            if (v) {
                              await _assistantProvider.updateAssistant(
                                _daddy().copyWith(temperature: 0.6),
                              );
                            } else {
                              await _assistantProvider.updateAssistant(
                                _daddy().copyWith(clearTemperature: true),
                              );
                            }
                            if (navigator.mounted) navigator.pop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (daddy.temperature != null) ...[
                      _DaddyTempSlider(
                        value: value.clamp(0.0, 2.0),
                        onChanged: (v) => _assistantProvider.updateAssistant(
                          _daddy().copyWith(temperature: v),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.daddySettingsTemperatureDesc,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          l10n.assistantEditParameterDisabled,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
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

/// iOS 风格的可点击导航行：左图标 + 标题，右侧灰色数值 + 箭头。点击有轻微缩放反馈，
/// 不引入 Material ripple。用于温度行（点开 sheet 编辑）。
Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String detailText,
  required VoidCallback onTap,
}) {
  return _NavRow(
    icon: icon,
    label: label,
    detailText: detailText,
    onTap: onTap,
  );
}

class _NavRow extends StatefulWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.detailText,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detailText;
  final VoidCallback onTap;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: cs.onSurface.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
              Text(
                widget.detailText,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Lucide.ChevronRight,
                size: 18,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 温度滑块：0.0–2.0，步长 0.1。视觉与通用助手页一致（同款 SfSlider 配置）。
class _DaddyTempSlider extends StatelessWidget {
  const _DaddyTempSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final active = cs.primary;
    final inactive = cs.onSurface.withValues(alpha: isDark ? 0.25 : 0.20);
    final label = value.toStringAsFixed(2);
    return Row(
      children: [
        Expanded(
          child: SfSliderTheme(
            data: SfSliderThemeData(
              activeTrackHeight: 8,
              inactiveTrackHeight: 8,
              overlayRadius: 14,
              activeTrackColor: active,
              inactiveTrackColor: inactive,
              tooltipBackgroundColor: cs.primary,
              tooltipTextStyle: TextStyle(
                color: cs.onPrimary,
                fontWeight: AppFontWeights.semibold,
              ),
              thumbStrokeColor: Colors.transparent,
              thumbStrokeWidth: 0,
              activeTickColor: cs.onSurface.withValues(
                alpha: isDark ? 0.45 : 0.35,
              ),
              inactiveTickColor: cs.onSurface.withValues(
                alpha: isDark ? 0.30 : 0.25,
              ),
              activeMinorTickColor: cs.onSurface.withValues(
                alpha: isDark ? 0.34 : 0.28,
              ),
              inactiveMinorTickColor: cs.onSurface.withValues(
                alpha: isDark ? 0.24 : 0.20,
              ),
            ),
            child: SfSlider(
              value: value.clamp(0.0, 2.0),
              min: 0.0,
              max: 2.0,
              stepSize: 0.1,
              enableTooltip: true,
              shouldAlwaysShowTooltip: false,
              showTicks: true,
              showLabels: true,
              interval: 0.5,
              minorTicksPerInterval: 4,
              activeColor: active,
              inactiveColor: inactive,
              tooltipTextFormatterCallback: (actual, text) => label,
              tooltipShape: const SfPaddleTooltipShape(),
              labelFormatterCallback: (actual, formattedText) =>
                  actual.toStringAsFixed(1),
              thumbIcon: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  boxShadow: isDark
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
              ),
              onChanged: (v) =>
                  onChanged(v is num ? v.toDouble() : (v as double)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: cs.primary.withValues(alpha: isDark ? 0.28 : 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                color: cs.primary,
                fontWeight: AppFontWeights.emphasis,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
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
