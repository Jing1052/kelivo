import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/snackbar.dart';
import '../widgets/model_select_sheet.dart';
import '../widgets/ocr_prompt_sheet.dart';
import '../utils/ocr_model_capability.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/brand_assets.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';
import '../../../shared/widgets/ios_switch.dart';

class DefaultModelPage extends StatelessWidget {
  const DefaultModelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    Future<ModelSelection?> pickConfiguredModel(
      String? providerKey,
      String? modelId,
    ) {
      return showModelSelector(
        context,
        initialProviderKey: providerKey,
        initialModelId: modelId,
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.defaultModelPageBackTooltip,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.defaultModelPageTitle),
        actions: const [SizedBox(width: 12)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _ModelCard(
            icon: Lucide.MessageCircle,
            title: l10n.defaultModelPageChatModelTitle,
            subtitle: l10n.defaultModelPageChatModelSubtitle,
            modelProvider: settings.currentModelProvider,
            modelId: settings.currentModelId,
            onReset: () async {
              await settings.resetCurrentModel();
            },
            onPick: () async {
              final sel = await pickConfiguredModel(
                settings.currentModelProvider,
                settings.currentModelId,
              );
              if (sel != null) {
                await settings.setCurrentModel(sel.providerKey, sel.modelId);
              }
            },
          ),
          const SizedBox(height: 16),
          _ModelCard(
            icon: Lucide.FileText,
            title: l10n.defaultModelPageSummaryModelTitle,
            subtitle: l10n.defaultModelPageSummaryModelSubtitle,
            modelProvider: settings.summaryModelProvider,
            modelId: settings.summaryModelId,
            fallbackProvider:
                settings.titleModelProvider ?? settings.currentModelProvider,
            fallbackModelId: settings.titleModelId ?? settings.currentModelId,
            onReset: () async {
              await settings.resetSummaryModel();
            },
            onPick: () async {
              final sel = await pickConfiguredModel(
                settings.summaryModelProvider,
                settings.summaryModelId,
              );
              if (sel != null) {
                await settings.setSummaryModel(sel.providerKey, sel.modelId);
              }
            },
            configAction: () => _showSummaryPromptSheet(context),
          ),
          const SizedBox(height: 16),
          _ModelCard(
            icon: Lucide.Eye,
            title: l10n.defaultModelPageOcrModelTitle,
            subtitle: l10n.defaultModelPageOcrModelSubtitle,
            modelProvider: settings.ocrModelProvider,
            modelId: settings.ocrModelId,
            disabledWhenUnset: true,
            onReset: () async {
              await settings.resetOcrModel();
            },
            onPick: () async {
              final sel = await pickConfiguredModel(
                settings.ocrModelProvider,
                settings.ocrModelId,
              );
              if (sel != null) {
                if (!modelSupportsOcrImageInput(
                  settings,
                  sel.providerKey,
                  sel.modelId,
                )) {
                  if (!context.mounted) return;
                  showAppSnackBar(
                    context,
                    message: l10n.defaultModelPageOcrModelRequiresImageInput,
                    type: NotificationType.error,
                  );
                  return;
                }
                await settings.setOcrModel(sel.providerKey, sel.modelId);
              }
            },
            configAction: () => showOcrPromptSheet(context),
          ),
          const SizedBox(height: 16),
          const _DaddyGatewayModelCard(),
          const SizedBox(height: 16),
          const _DiaryBriefGatewayCard(),
        ],
      ),
    );
  }

  Future<void> _showSummaryPromptSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final controller = TextEditingController(text: settings.summaryPrompt);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
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
                  l10n.defaultModelPagePromptLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: l10n.defaultModelPageSummaryPromptHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white10
                        : const Color(0xFFF2F3F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: cs.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await settings.resetSummaryPrompt();
                        controller.text = settings.summaryPrompt;
                      },
                      child: Text(l10n.defaultModelPageResetDefault),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        await settings.setSummaryPrompt(controller.text.trim());
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.defaultModelPageSave),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.defaultModelPageSummaryVars(
                    '{previous_summary}',
                    '{user_messages}',
                  ),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Picks the old-home gateway's server-side `summary` model (archive / recap /
/// compress all share this one role on the gateway). Empty = follow the chat
/// relay. This is NOT a kelivo relay; it reads/writes the gateway role route.
class _DaddyGatewayModelCard extends StatefulWidget {
  const _DaddyGatewayModelCard();

  @override
  State<_DaddyGatewayModelCard> createState() => _DaddyGatewayModelCardState();
}

class _DaddyGatewayModelCardState extends State<_DaddyGatewayModelCard> {
  OurHomeGateway? _gateway;
  bool _loading = true;
  bool _noGateway = false;
  List<({String id, String name, String model})> _profiles = const [];
  // Current summary route. Empty id = follow the chat relay.
  String _summaryId = '';

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final gw = OurHomeGateway.fromContext(context);
    if (gw == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _noGateway = true;
        });
      }
      return;
    }
    _gateway = gw;
    final data = await gw.fetchChatProviders();
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _loading = false;
        _noGateway = true;
      });
      return;
    }
    final summary = data.roleRoutes['summary'];
    final sid = (summary is Map ? (summary['id'] ?? '') : '').toString();
    setState(() {
      _loading = false;
      _noGateway = false;
      _profiles = data.profiles;
      _summaryId = sid;
    });
  }

  String get _currentLabel {
    if (_summaryId.isEmpty) {
      return _isZh ? '跟随聊天中转站' : 'Follow chat relay';
    }
    for (final p in _profiles) {
      if (p.id == _summaryId) {
        return p.name.isNotEmpty ? p.name : p.id;
      }
    }
    return _summaryId;
  }

  Future<void> _pick() async {
    final gw = _gateway;
    if (gw == null) return;
    final cs = Theme.of(context).colorScheme;
    final isZh = _isZh;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        Widget row({
          required String label,
          String? sub,
          required bool selectedNow,
          required VoidCallback onTap,
        }) {
          return _TactileRow(
            onTap: onTap,
            builder: (pressed) {
              final bg = pressed
                  ? (isDark ? Colors.white10 : const Color(0xFFF2F3F5))
                  : Colors.transparent;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: AppFontWeights.semibold,
                            ),
                          ),
                          if (sub != null && sub.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selectedNow)
                      Icon(Lucide.Check, size: 18, color: cs.primary),
                  ],
                ),
              );
            },
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                row(
                  label: isZh
                      ? '跟随聊天中转站（默认）'
                      : 'Follow chat relay (default)',
                  selectedNow: _summaryId.isEmpty,
                  onTap: () => Navigator.of(ctx).pop(''),
                ),
                for (final p in _profiles)
                  row(
                    label: p.name.isNotEmpty ? p.name : p.id,
                    sub: p.model,
                    selectedNow: p.id == _summaryId,
                    onTap: () => Navigator.of(ctx).pop(p.id),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    final ok = await gw.setRoleRoute('summary', selected, '');
    if (!mounted) return;
    if (ok) {
      setState(() => _summaryId = selected);
      showAppSnackBar(
        context,
        message: isZh ? '已保存' : 'Saved',
        type: NotificationType.success,
      );
    } else {
      showAppSnackBar(
        context,
        message: isZh ? '保存失败，请重试' : 'Save failed, try again',
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isZh = _isZh;
    final baseBg = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);
    final title = isZh
        ? '爸爸·归档/前情/压缩模型'
        : 'Daddy · archive/recap/compress';
    final subtitle = isZh
        ? '老家网关共用的 summary 模型（归档·前情提要·压缩三件共用一个）。选老家的中转站；留空=跟随爸爸聊天用的中转站。'
        : 'The summary model shared by the old-home gateway (archive / recap / compress all use this one). Pick an old-home relay; leave empty to follow daddy\'s chat relay.';

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_noGateway) {
      body = Text(
        isZh ? '未连上老家网关' : 'Old-home gateway not connected',
        style: TextStyle(
          fontSize: 13,
          color: cs.onSurface.withValues(alpha: 0.5),
        ),
      );
    } else {
      body = _TactileRow(
        onTap: _pick,
        builder: (pressed) {
          final bg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
          final overlay = isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05);
          final pressedBg = Color.alphaBlend(overlay, bg);
          return AnimatedScale(
            scale: pressed ? 0.98 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: pressed ? pressedBg : bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _BrandAvatar(name: _currentLabel, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
          width: 0.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Lucide.Archive, size: 18, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    );
  }
}

/// Picks the old-home gateway's server-side `diary_brief` model and toggles
/// the daily-brief (日记底稿) feature on/off. Mirrors _DaddyGatewayModelCard
/// but for role 'diary_brief'. Enable state is persisted locally in
/// SettingsProvider and pushed to the server via OurHomeGateway.setDailyBriefEnabled.
class _DiaryBriefGatewayCard extends StatefulWidget {
  const _DiaryBriefGatewayCard();

  @override
  State<_DiaryBriefGatewayCard> createState() => _DiaryBriefGatewayCardState();
}

class _DiaryBriefGatewayCardState extends State<_DiaryBriefGatewayCard> {
  OurHomeGateway? _gateway;
  bool _loading = true;
  bool _noGateway = false;
  List<({String id, String name, String model})> _profiles = const [];
  // Current diary_brief route. Empty id = follow the chat relay.
  String _diaryBriefId = '';

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final gw = OurHomeGateway.fromContext(context);
    if (gw == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _noGateway = true;
        });
      }
      return;
    }
    _gateway = gw;
    final data = await gw.fetchChatProviders();
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _loading = false;
        _noGateway = true;
      });
      return;
    }
    final diaryBrief = data.roleRoutes['diary_brief'];
    final did =
        (diaryBrief is Map ? (diaryBrief['id'] ?? '') : '').toString();
    setState(() {
      _loading = false;
      _noGateway = false;
      _profiles = data.profiles;
      _diaryBriefId = did;
    });
  }

  String get _currentLabel {
    if (_diaryBriefId.isEmpty) {
      return _isZh ? '跟随聊天中转站' : 'Follow chat relay';
    }
    for (final p in _profiles) {
      if (p.id == _diaryBriefId) {
        return p.name.isNotEmpty ? p.name : p.id;
      }
    }
    return _diaryBriefId;
  }

  Future<void> _pick() async {
    final gw = _gateway;
    if (gw == null) return;
    final cs = Theme.of(context).colorScheme;
    final isZh = _isZh;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        Widget row({
          required String label,
          String? sub,
          required bool selectedNow,
          required VoidCallback onTap,
        }) {
          return _TactileRow(
            onTap: onTap,
            builder: (pressed) {
              final bg = pressed
                  ? (isDark ? Colors.white10 : const Color(0xFFF2F3F5))
                  : Colors.transparent;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: AppFontWeights.semibold,
                            ),
                          ),
                          if (sub != null && sub.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selectedNow)
                      Icon(Lucide.Check, size: 18, color: cs.primary),
                  ],
                ),
              );
            },
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                row(
                  label: isZh
                      ? '跟随聊天中转站（默认）'
                      : 'Follow chat relay (default)',
                  selectedNow: _diaryBriefId.isEmpty,
                  onTap: () => Navigator.of(ctx).pop(''),
                ),
                for (final p in _profiles)
                  row(
                    label: p.name.isNotEmpty ? p.name : p.id,
                    sub: p.model,
                    selectedNow: p.id == _diaryBriefId,
                    onTap: () => Navigator.of(ctx).pop(p.id),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    final ok = await gw.setRoleRoute('diary_brief', selected, '');
    if (!mounted) return;
    if (ok) {
      setState(() => _diaryBriefId = selected);
      showAppSnackBar(
        context,
        message: _isZh ? '已保存' : 'Saved',
        type: NotificationType.success,
      );
    } else {
      showAppSnackBar(
        context,
        message: _isZh ? '保存失败，请重试' : 'Save failed, try again',
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isZh = _isZh;
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final baseBg = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);

    // Enable switch row
    final enableRow = _TactileRow(
      onTap: () async {
        final newVal = !settings.dailyBriefEnabled;
        await settings.setDailyBriefEnabled(newVal);
        final gw = OurHomeGateway.fromContext(context);
        if (gw == null) return;
        final ok = await gw.setDailyBriefEnabled(newVal);
        if (!mounted) return;
        if (!ok) {
          // Revert local on server failure
          await settings.setDailyBriefEnabled(!newVal);
          showAppSnackBar(
            context,
            message: isZh ? '保存失败，请重试' : 'Save failed, try again',
            type: NotificationType.error,
          );
        }
      },
      builder: (pressed) {
        final bg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
        final overlay = isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05);
        final pressedBg = Color.alphaBlend(overlay, bg);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: pressed ? pressedBg : bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.defaultModelPageDiaryBriefEnableTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.defaultModelPageDiaryBriefEnableSubtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IosSwitch(
                value: settings.dailyBriefEnabled,
                onChanged: null, // tap handled by _TactileRow wrapper
              ),
            ],
          ),
        );
      },
    );

    Widget modelBody;
    if (_loading) {
      modelBody = const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_noGateway) {
      modelBody = Text(
        isZh ? '未连上老家网关' : 'Old-home gateway not connected',
        style: TextStyle(
          fontSize: 13,
          color: cs.onSurface.withValues(alpha: 0.5),
        ),
      );
    } else {
      modelBody = _TactileRow(
        onTap: _pick,
        builder: (pressed) {
          final bg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
          final overlay = isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05);
          final pressedBg = Color.alphaBlend(overlay, bg);
          return AnimatedScale(
            scale: pressed ? 0.98 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: pressed ? pressedBg : bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _BrandAvatar(name: _currentLabel, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
          width: 0.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Lucide.NotebookTabs, size: 18, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.defaultModelPageDiaryBriefSectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            enableRow,
            const SizedBox(height: 8),
            // Model picker sub-section header
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                l10n.defaultModelPageDiaryBriefModelTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            modelBody,
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.modelProvider,
    required this.modelId,
    required this.onPick,
    this.onReset,
    this.fallbackProvider,
    this.fallbackModelId,
    this.disabledWhenUnset = false,
    this.configAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? modelProvider;
  final String? modelId;
  final String? fallbackProvider;
  final String? fallbackModelId;
  final bool disabledWhenUnset;
  final VoidCallback onPick;
  final VoidCallback? onReset;
  final VoidCallback? configAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.read<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;

    // Check if using fallback (not explicitly set)
    final usingFallback = modelProvider == null || modelId == null;

    // Use fallback values if needed
    final effectiveProvider = modelProvider ?? fallbackProvider;
    final effectiveModelId = modelId ?? fallbackModelId;

    String? providerName;
    String? modelDisplay;
    if (effectiveProvider != null && effectiveModelId != null) {
      final cfg = settings.getProviderConfig(effectiveProvider);
      providerName = cfg.name.isNotEmpty ? cfg.name : effectiveProvider;
      final ov = cfg.modelOverrides[effectiveModelId] as Map?;
      if (ov != null) {
        final overrideName = (ov['name'] as String?)?.trim();
        if (overrideName != null && overrideName.isNotEmpty) {
          modelDisplay = overrideName;
        } else {
          final apiId = (ov['apiModelId'] ?? ov['api_model_id'])
              ?.toString()
              .trim();
          modelDisplay = (apiId != null && apiId.isNotEmpty)
              ? apiId
              : effectiveModelId;
        }
      } else {
        modelDisplay = effectiveModelId;
      }
    }

    // Override display text if using fallback
    if (usingFallback) {
      modelDisplay = disabledWhenUnset
          ? l10n.defaultModelPageNotEnabled
          : l10n.defaultModelPageUseCurrentModel;
    }
    final baseBg = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);
    return Container(
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
          width: 0.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
                if (onReset != null && !usingFallback)
                  Tooltip(
                    message: l10n.defaultModelPageResetDefault,
                    child: _TactileIconButton(
                      icon: Lucide.RotateCcw,
                      color: cs.onSurface,
                      size: 20,
                      onTap: onReset!,
                    ),
                  ),
                if (configAction != null)
                  _TactileIconButton(
                    icon: Lucide.Settings,
                    color: cs.onSurface,
                    size: 20,
                    onTap: configAction!,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // description under title
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            const SizedBox(height: 8),
            _TactileRow(
              onTap: onPick,
              builder: (pressed) {
                final bg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
                final overlay = isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05);
                final pressedBg = Color.alphaBlend(overlay, bg);
                return AnimatedScale(
                  scale: pressed ? 0.98 : 1.0,
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: pressed ? pressedBg : bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _BrandAvatar(
                          name: modelDisplay ?? (providerName ?? '?'),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            modelDisplay ?? (providerName ?? '-'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: AppFontWeights.semibold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 20});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = BrandAssets.assetForName(name);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final dark = Theme.of(context).brightness == Brightness.dark;
        final ColorFilter? tint = (dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          fit: BoxFit.contain,
        );
      }
    } else {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.42,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
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

class _TactileRow extends StatefulWidget {
  const _TactileRow({required this.builder, this.onTap});
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null
          ? null
          : (_) async {
              // Keep pressed state for a short moment to avoid flicker
              await Future.delayed(const Duration(milliseconds: 60));
              if (mounted) _setPressed(false);
            },
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: widget.builder(_pressed),
    );
  }
}
