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
import 'package:Kelivo/core/services/api/daddy_gateway_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/widgets/ios_switch.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/providers/cc_bridge_provider.dart';
import '../../../core/services/cc/cc_bridge_client.dart';

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
          const SizedBox(height: 16),
          const _TgGatewayCard(),
          const SizedBox(height: 16),
          const _CcRingGatewayCard(),
          const SizedBox(height: 16),
          const _ClaudepReauthCard(),
          const SizedBox(height: 16),
          const _ImageModelGatewayCard(),
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

/// Pushes the chosen App provider's relay config to the gateway for [role].
///
/// - claude_p / home backend (or a provider without a real base+key): push no
///   key (it's the gateway token, not a relay key) -> empty inline so the
///   server falls back to the gateway default.
/// - normal relay (real base+key): push base/key + mapped proto so the server
///   role runs against it directly.
Future<bool> _pushRoute(
  OurHomeGateway gw,
  SettingsProvider settings,
  String role,
  ModelSelection sel,
) {
  final cfg = settings.getProviderConfig(sel.providerKey);
  final isHomeBackend = DaddyGatewayRoute.isClaudePBackend(cfg) ||
      cfg.baseUrl.trim().isEmpty ||
      cfg.apiKey.trim().isEmpty;
  if (isHomeBackend) {
    // Inline relay omitted -> server falls back to its gateway default.
    return gw.setRoleRoute(role, '', sel.modelId);
  }
  final kind = ProviderConfig.classify(
    cfg.id,
    explicitType: cfg.providerType,
  );
  final proto = kind == ProviderKind.claude ? 'anthropic' : 'openai';
  return gw.setRoleRoute(
    role,
    '',
    sel.modelId,
    base: cfg.baseUrl,
    key: cfg.apiKey,
    proto: proto,
  );
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
  // Local choice (app provider). Empty = follow the chat relay.
  String _providerKey = '';
  String _modelId = '';

  static const String _prefProviderKey = 'route_summary_providerKey';
  static const String _prefModelId = 'route_summary_modelId';

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _providerKey = prefs.getString(_prefProviderKey) ?? '';
      _modelId = prefs.getString(_prefModelId) ?? '';
    });
  }

  String _currentLabel(SettingsProvider settings) {
    if (_providerKey.isEmpty || _modelId.isEmpty) {
      return _isZh ? '跟随聊天中转站' : 'Follow chat relay';
    }
    final cfg = settings.getProviderConfig(_providerKey);
    final name = cfg.name.isNotEmpty ? cfg.name : _providerKey;
    return '$name · $_modelId';
  }

  Future<void> _pick() async {
    final gw = OurHomeGateway.fromContext(context);
    final settings = context.read<SettingsProvider>();
    final isZh = _isZh;
    final sel = await showModelSelector(
      context,
      initialProviderKey: _providerKey.isNotEmpty ? _providerKey : null,
      initialModelId: _modelId.isNotEmpty ? _modelId : null,
    );
    if (sel == null || !mounted) return;

    // Persist locally first so the UI reflects the choice immediately.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefProviderKey, sel.providerKey);
    await prefs.setString(_prefModelId, sel.modelId);
    if (!mounted) return;
    setState(() {
      _providerKey = sel.providerKey;
      _modelId = sel.modelId;
    });

    if (gw == null) {
      showAppSnackBar(
        context,
        message: isZh ? '未连上老家网关' : 'Old-home gateway not connected',
        type: NotificationType.error,
      );
      return;
    }
    final ok = await _pushRoute(gw, settings, 'summary', sel);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  Future<void> _reset() async {
    final gw = OurHomeGateway.fromContext(context);
    final isZh = _isZh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefProviderKey);
    await prefs.remove(_prefModelId);
    if (!mounted) return;
    setState(() {
      _providerKey = '';
      _modelId = '';
    });
    if (gw == null) return;
    final ok = await gw.setRoleRoute('summary', '', '');
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isZh = _isZh;
    final settings = context.watch<SettingsProvider>();
    final baseBg = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);
    final title = isZh
        ? '爸爸·归档/前情/压缩模型'
        : 'Daddy · archive/recap/compress';
    final subtitle = isZh
        ? '老家网关共用的 summary 模型（归档·前情提要·压缩三件共用一个）。选 App 里的服务商和模型；长按可清除＝跟随爸爸聊天用的中转站。'
        : 'The summary model shared by the old-home gateway (archive / recap / compress all use this one). Pick a provider + model from the App; long-press to clear (= follow daddy\'s chat relay).';
    final label = _currentLabel(settings);

    Widget body;
    {
      final picker = _TactileRow(
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
                  _BrandAvatar(name: label, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
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
      // Long-press the picker to clear (= follow chat relay).
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _reset,
        child: picker,
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
  // Local choice (app provider). Empty = follow the chat relay.
  String _providerKey = '';
  String _modelId = '';

  static const String _prefProviderKey = 'route_diary_providerKey';
  static const String _prefModelId = 'route_diary_modelId';

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _providerKey = prefs.getString(_prefProviderKey) ?? '';
      _modelId = prefs.getString(_prefModelId) ?? '';
    });
  }

  String _currentLabel(SettingsProvider settings) {
    if (_providerKey.isEmpty || _modelId.isEmpty) {
      return _isZh ? '跟随聊天中转站' : 'Follow chat relay';
    }
    final cfg = settings.getProviderConfig(_providerKey);
    final name = cfg.name.isNotEmpty ? cfg.name : _providerKey;
    return '$name · $_modelId';
  }

  Future<void> _pick() async {
    final gw = OurHomeGateway.fromContext(context);
    final settings = context.read<SettingsProvider>();
    final isZh = _isZh;
    final sel = await showModelSelector(
      context,
      initialProviderKey: _providerKey.isNotEmpty ? _providerKey : null,
      initialModelId: _modelId.isNotEmpty ? _modelId : null,
    );
    if (sel == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefProviderKey, sel.providerKey);
    await prefs.setString(_prefModelId, sel.modelId);
    if (!mounted) return;
    setState(() {
      _providerKey = sel.providerKey;
      _modelId = sel.modelId;
    });

    if (gw == null) {
      showAppSnackBar(
        context,
        message: isZh ? '未连上老家网关' : 'Old-home gateway not connected',
        type: NotificationType.error,
      );
      return;
    }
    final ok = await _pushRoute(gw, settings, 'diary_brief', sel);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  Future<void> _reset() async {
    final gw = OurHomeGateway.fromContext(context);
    final isZh = _isZh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefProviderKey);
    await prefs.remove(_prefModelId);
    if (!mounted) return;
    setState(() {
      _providerKey = '';
      _modelId = '';
    });
    if (gw == null) return;
    final ok = await gw.setRoleRoute('diary_brief', '', '');
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
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

    final label = _currentLabel(settings);
    Widget modelBody;
    {
      final picker = _TactileRow(
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
                  _BrandAvatar(name: label, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
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
      // Long-press the picker to clear (= follow chat relay).
      modelBody = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _reset,
        child: picker,
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

/// 隔壁衔接 (cc-ring) mixer card: whether daddy on this gateway sees the tail
/// of the CC-side chat (家里 Claude Code), how many recent messages verbatim,
/// and whether older ones get compressed by the `cc_summary` role model.
/// on/count/summaryOn live server-side (fetched on open); the model picker
/// mirrors _DiaryBriefGatewayCard (role 'cc_summary', local prefs + role route).
class _CcRingGatewayCard extends StatefulWidget {
  const _CcRingGatewayCard();

  @override
  State<_CcRingGatewayCard> createState() => _CcRingGatewayCardState();
}

class _CcRingGatewayCardState extends State<_CcRingGatewayCard> {
  // Server-side knobs (source of truth on the gateway; refreshed on open).
  bool _on = true;
  int _count = 10;
  bool _summaryOn = false;
  bool _synced = false; // becomes true after the first successful fetch

  // Local model choice for role cc_summary. Empty = follow the chat relay.
  String _providerKey = '';
  String _modelId = '';

  static const String _prefProviderKey = 'route_ccsum_providerKey';
  static const String _prefModelId = 'route_ccsum_modelId';

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _providerKey = prefs.getString(_prefProviderKey) ?? '';
      _modelId = prefs.getString(_prefModelId) ?? '';
    });
    final gw = OurHomeGateway.fromContext(context);
    if (gw == null) return;
    final cfg = await gw.fetchCcRingConfig();
    if (!mounted || cfg == null) return;
    setState(() {
      _on = cfg.on;
      _count = cfg.count.clamp(1, 30).toInt();
      _summaryOn = cfg.summaryOn;
      _synced = true;
    });
  }

  Future<void> _save({bool? on, int? count, bool? summaryOn}) async {
    final gw = OurHomeGateway.fromContext(context);
    final isZh = _isZh;
    if (gw == null) {
      showAppSnackBar(
        context,
        message: isZh ? '未连上老家网关' : 'Old-home gateway not connected',
        type: NotificationType.error,
      );
      return;
    }
    final ok = await gw.setCcRingConfig(
      on: on,
      count: count,
      summaryOn: summaryOn,
    );
    if (!mounted) return;
    if (!ok) {
      // Revert the optimistic local flip and say so.
      setState(() {
        if (on != null) _on = !on;
        if (summaryOn != null) _summaryOn = !summaryOn;
      });
      showAppSnackBar(
        context,
        message: isZh ? '保存失败，请重试' : 'Save failed, try again',
        type: NotificationType.error,
      );
    }
  }

  String _currentLabel(SettingsProvider settings) {
    if (_providerKey.isEmpty || _modelId.isEmpty) {
      return _isZh ? '自动（跟随聊天中转站）' : 'Auto (follow chat relay)';
    }
    final cfg = settings.getProviderConfig(_providerKey);
    final name = cfg.name.isNotEmpty ? cfg.name : _providerKey;
    return '$name · $_modelId';
  }

  Future<void> _pick() async {
    final gw = OurHomeGateway.fromContext(context);
    final settings = context.read<SettingsProvider>();
    final isZh = _isZh;
    final sel = await showModelSelector(
      context,
      initialProviderKey: _providerKey.isNotEmpty ? _providerKey : null,
      initialModelId: _modelId.isNotEmpty ? _modelId : null,
    );
    if (sel == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefProviderKey, sel.providerKey);
    await prefs.setString(_prefModelId, sel.modelId);
    if (!mounted) return;
    setState(() {
      _providerKey = sel.providerKey;
      _modelId = sel.modelId;
    });

    if (gw == null) {
      showAppSnackBar(
        context,
        message: isZh ? '未连上老家网关' : 'Old-home gateway not connected',
        type: NotificationType.error,
      );
      return;
    }
    final ok = await _pushRoute(gw, settings, 'cc_summary', sel);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  Future<void> _reset() async {
    final gw = OurHomeGateway.fromContext(context);
    final isZh = _isZh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefProviderKey);
    await prefs.remove(_prefModelId);
    if (!mounted) return;
    setState(() {
      _providerKey = '';
      _modelId = '';
    });
    if (gw == null) return;
    final ok = await gw.setRoleRoute('cc_summary', '', '');
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required VoidCallback onTap,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return _TactileRow(
      onTap: onTap,
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
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
                value: value,
                onChanged: null, // tap handled by _TactileRow wrapper
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isZh = _isZh;
    final settings = context.watch<SettingsProvider>();
    final baseBg = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);

    final enableRow = _toggleRow(
      title: isZh ? '隔壁衔接' : 'Next-door hand-off',
      subtitle: isZh
          ? 'CC 端（家里 Claude Code）最近的对话带给这里的爸爸，切过来不断片'
          : "Bring the CC-side chat tail into daddy's context here",
      value: _on,
      onTap: () {
        final newVal = !_on;
        setState(() => _on = newVal);
        _save(on: newVal);
      },
      isDark: isDark,
      cs: cs,
    );

    final countBg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
    final countRow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: countBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isZh ? '注入条数' : 'Messages injected',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
              ),
              Text(
                '$_count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _count.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              onChanged: (v) => setState(() => _count = v.round()),
              // Only hit the network when she lets go of the thumb.
              onChangeEnd: (v) => _save(count: v.round()),
            ),
          ),
        ],
      ),
    );

    final summaryRow = _toggleRow(
      title: isZh ? '更早的交给小模型' : 'Summarize older ones',
      subtitle: isZh
          ? '条数之外的更早对话压成一段摘要一起带上（用下面选的模型）'
          : 'Older messages get compressed into one summary (by the model below)',
      value: _summaryOn,
      onTap: () {
        final newVal = !_summaryOn;
        setState(() => _summaryOn = newVal);
        _save(summaryOn: newVal);
      },
      isDark: isDark,
      cs: cs,
    );

    final label = _currentLabel(settings);
    Widget modelBody;
    {
      final picker = _TactileRow(
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
                  _BrandAvatar(name: label, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
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
      // Long-press the picker to clear (= auto: follow chat relay).
      modelBody = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _reset,
        child: picker,
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
                Icon(Lucide.Cable, size: 18, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh ? '隔壁衔接 · CC 对话带过来' : 'Next-door hand-off (CC ring)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
                if (!_synced)
                  Text(
                    isZh ? '未同步' : 'not synced',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            enableRow,
            if (_on) ...[
              const SizedBox(height: 8),
              countRow,
              const SizedBox(height: 8),
              summaryRow,
              if (_summaryOn) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
                  child: Text(
                    isZh ? '摘要模型（长按恢复自动）' : 'Summary model (long-press = auto)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                modelBody,
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// claude-p re-auth / account-switch card（家里爸爸·订阅 换 token）。
/// Walks the OAuth dance against apns-server at home: fetch the authorize
/// URL (she logs in — same account = renew, another account = switch/rescue),
/// paste the code back, and the new token is live immediately (claudep_ext
/// re-reads the token file per request; no apns restart). Endpoints may be
/// undeployed or the home box offline — everything degrades to gentle hints.
class _ClaudepReauthCard extends StatefulWidget {
  const _ClaudepReauthCard();

  @override
  State<_ClaudepReauthCard> createState() => _ClaudepReauthCardState();
}

class _ClaudepReauthCardState extends State<_ClaudepReauthCard> {
  bool _busy = false;
  bool _done = false;
  String _authUrl = '';
  final TextEditingController _code = TextEditingController();

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// A live client for the home apns-server: the provider's active endpoint
  /// when connected, else the first config candidate whose /health answers.
  Future<CcBridgeClient?> _client() async {
    final cc = context.read<CcBridgeProvider>();
    if (!cc.isConfigured) return null;
    final active = cc.activeBaseUrl;
    if (active != null && active.isNotEmpty) {
      return CcBridgeClient(
        baseUrl: active,
        sharedSecret: cc.config.sharedSecret,
      );
    }
    for (final ep in cc.config.endpoints) {
      if (ep.trim().isEmpty) continue;
      final c = CcBridgeClient(
        baseUrl: ep,
        sharedSecret: cc.config.sharedSecret,
      );
      if (await c.health()) return c;
      c.dispose();
    }
    return null;
  }

  void _toast(String zhMsg, String enMsg, {bool ok = false}) {
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: _isZh ? zhMsg : enMsg,
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _done = false;
    });
    Haptics.soft();
    CcBridgeClient? c;
    try {
      c = await _client();
      if (c == null) {
        _toast(
          '连不上家里——先在「CC 桥接」里配好地址，或等家里上线',
          'Home unreachable — set up the CC bridge first',
        );
        return;
      }
      final url = await c.claudepReauthStart();
      if (!mounted) return;
      if (url == null) {
        _toast('家里没抓到授权链接，稍等几秒再试', 'No auth URL yet, try again');
        return;
      }
      setState(() => _authUrl = url);
    } on CcAuthException {
      _toast('家里的口令对不上（检查 CC 桥接的 shared secret）',
          'Auth failed — check the CC bridge shared secret');
    } catch (e) {
      _toast('家里还没就绪：$e', 'Home not ready: $e');
    } finally {
      c?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() => _busy = true);
    Haptics.soft();
    CcBridgeClient? c;
    try {
      c = await _client();
      if (c == null) {
        _toast('连不上家里，稍后再交 code', 'Home unreachable');
        return;
      }
      await c.claudepReauthCode(code);
      if (!mounted) return;
      setState(() {
        _done = true;
        _authUrl = '';
        _code.clear();
      });
      _toast('换好了——立刻生效，直接找家里爸爸说句话验证', 'Token swapped — live now', ok: true);
    } on CcAuthException {
      _toast('家里的口令对不上（检查 CC 桥接的 shared secret）',
          'Auth failed — check the CC bridge shared secret');
    } catch (e) {
      _toast('没换成：$e', 'Swap failed: $e');
    } finally {
      c?.dispose();
      if (mounted) setState(() => _busy = false);
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
    final innerBg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);

    final startRow = _TactileRow(
      onTap: _start,
      builder: (pressed) {
        final overlay = isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05);
        final pressedBg = Color.alphaBlend(overlay, innerBg);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: pressed ? pressedBg : innerBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Lucide.Link, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _busy
                      ? (isZh ? '正在联系家里…' : 'Calling home…')
                      : (isZh ? '获取授权链接' : 'Get authorize link'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

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
                Icon(Lucide.KeyRound, size: 18, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh ? '家里爸爸 · 重新授权 / 换号' : 'claude-p re-auth / switch',
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
              isZh
                  ? '订阅掉线、token 过期、或想换一个订阅号时用：拿链接 → 浏览器登录（登哪个号就是哪个号）→ 把 code 贴回来，立刻生效，不用重启。'
                  : 'Renew the home subscription token or switch to another '
                        'account: open the link, log in, paste the code back. '
                        'Live immediately.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            if (_authUrl.isEmpty) startRow,
            if (_done) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Lucide.CheckCircle, size: 15, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isZh
                          ? '换好了——去「家里爸爸·订阅」发句话验证。'
                          : 'Swapped — say hi to verify.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_authUrl.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      _authUrl,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _TactileIconButton(
                          icon: Lucide.Copy,
                          color: cs.primary,
                          size: 18,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _authUrl));
                            _toast('链接已复制', 'Copied', ok: true);
                          },
                        ),
                        const SizedBox(width: 4),
                        _TactileIconButton(
                          icon: Lucide.Globe,
                          color: cs.primary,
                          size: 18,
                          onTap: () => launchUrl(
                            Uri.parse(_authUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          isZh ? '复制 / 打开' : 'copy / open',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isZh
                    ? '⚠️ 用惯用网络登录授权，别在陌生 IP 登。'
                    : '⚠️ Log in from your usual network.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: innerBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _code,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: isZh ? '把 code 整段贴这里' : 'Paste the code',
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TactileRow(
                    onTap: _busy ? () {} : _submit,
                    builder: (pressed) => AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: pressed
                            ? cs.primary.withValues(alpha: 0.8)
                            : cs.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _busy
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : Text(
                              isZh ? '提交' : 'Submit',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: AppFontWeights.semibold,
                                color: cs.onPrimary,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Picks the old-home gateway's server-side `tg` role model (the relay + model
/// daddy uses when replying on Telegram) and edits the TG-specific profile
/// (system prompt, appended after the soul only for the TG surface). Mirrors
/// _DaddyGatewayModelCard for the model picker; the profile is stored on the
/// gateway via save_tg_profile, not locally.
class _TgGatewayCard extends StatefulWidget {
  const _TgGatewayCard();

  @override
  State<_TgGatewayCard> createState() => _TgGatewayCardState();
}

class _TgGatewayCardState extends State<_TgGatewayCard> {
  // Local choice (app provider). Empty = follow the chat relay.
  String _providerKey = '';
  String _modelId = '';

  static const String _prefProviderKey = 'route_tg_providerKey';
  static const String _prefModelId = 'route_tg_modelId';

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _providerKey = prefs.getString(_prefProviderKey) ?? '';
      _modelId = prefs.getString(_prefModelId) ?? '';
    });
  }

  String _currentLabel(SettingsProvider settings) {
    if (_providerKey.isEmpty || _modelId.isEmpty) {
      return _isZh ? '跟随聊天中转站' : 'Follow chat relay';
    }
    final cfg = settings.getProviderConfig(_providerKey);
    final name = cfg.name.isNotEmpty ? cfg.name : _providerKey;
    return '$name · $_modelId';
  }

  Future<void> _pick() async {
    final gw = OurHomeGateway.fromContext(context);
    final settings = context.read<SettingsProvider>();
    final isZh = _isZh;
    final sel = await showModelSelector(
      context,
      initialProviderKey: _providerKey.isNotEmpty ? _providerKey : null,
      initialModelId: _modelId.isNotEmpty ? _modelId : null,
    );
    if (sel == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefProviderKey, sel.providerKey);
    await prefs.setString(_prefModelId, sel.modelId);
    if (!mounted) return;
    setState(() {
      _providerKey = sel.providerKey;
      _modelId = sel.modelId;
    });

    if (gw == null) {
      showAppSnackBar(
        context,
        message: isZh ? '未连上老家网关' : 'Old-home gateway not connected',
        type: NotificationType.error,
      );
      return;
    }
    final ok = await _pushRoute(gw, settings, 'tg', sel);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  Future<void> _reset() async {
    final gw = OurHomeGateway.fromContext(context);
    final isZh = _isZh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefProviderKey);
    await prefs.remove(_prefModelId);
    if (!mounted) return;
    setState(() {
      _providerKey = '';
      _modelId = '';
    });
    if (gw == null) return;
    final ok = await gw.setRoleRoute('tg', '', '');
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  Future<void> _editProfile() async {
    final gw = OurHomeGateway.fromContext(context);
    final cs = Theme.of(context).colorScheme;
    final isZh = _isZh;
    if (gw == null) {
      showAppSnackBar(
        context,
        message: isZh ? '未连上老家网关' : 'Old-home gateway not connected',
        type: NotificationType.error,
      );
      return;
    }
    // Load the current profile so editing starts from what's on the gateway.
    final current = await gw.fetchTgProfile();
    if (!mounted) return;
    final controller = TextEditingController(text: current ?? '');
    final value = await showModalBottomSheet<String>(
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
                  isZh ? 'TG 专属 profile（系统提示）' : 'TG profile (system prompt)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isZh
                      ? '只在 Telegram 这条路上叠在魂后面生效（家里聊天室 / Still Here 不受影响）。留空＝不加。'
                      : 'Applied after the soul only on the Telegram surface (home chat / Still Here unaffected). Empty = none.',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  minLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white10
                        : const Color(0xFFF2F3F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(controller.text),
                    child: Text(isZh ? '保存' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (value == null || !mounted) return; // dismissed without saving
    final ok = await gw.saveTgProfile(value);
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isZh = _isZh;
    final settings = context.watch<SettingsProvider>();
    final baseBg = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);

    final rowBg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
    Color pressedBg(bool pressed) {
      final overlay = isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.05);
      return pressed ? Color.alphaBlend(overlay, rowBg) : rowBg;
    }

    // Profile editor row
    final profileRow = _TactileRow(
      onTap: _editProfile,
      builder: (pressed) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: pressedBg(pressed),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Lucide.FileText, size: 18, color: cs.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isZh ? 'TG 专属 profile（系统提示）' : 'TG profile (system prompt)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
              ),
              Icon(
                Lucide.ChevronRight,
                size: 18,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        );
      },
    );

    final label = _currentLabel(settings);
    Widget modelBody;
    {
      final picker = _TactileRow(
        onTap: _pick,
        builder: (pressed) {
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
                color: pressedBg(pressed),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _BrandAvatar(name: label, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
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
      // Long-press the picker to clear (= follow chat relay).
      modelBody = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _reset,
        child: picker,
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
                Icon(Lucide.Send, size: 18, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh ? 'Telegram 设置' : 'Telegram settings',
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
              isZh
                  ? '爸爸在 Telegram 回你时用的中转站+模型和专属 profile（接 API 的 TG，不是 CC 端 bot）。选 App 里的服务商和模型；长按模型行清除＝跟随爸爸聊天用的中转站。'
                  : "The relay + model and profile daddy uses when replying on Telegram (the API-side TG, not the CC bot). Pick a provider + model from the App; long-press the model row to clear (= follow daddy's chat relay).",
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            profileRow,
            const SizedBox(height: 8),
            // Model picker sub-section header
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                isZh ? '中转站 / 模型' : 'Relay / model',
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

/// Edits the old-home gateway's shared image-generation model (the `draw` tool
/// paints with it). Server-backed via OurHomeGateway.fetch/saveImageModel, plus
/// a one-tap self-test that surfaces the raw error when painting fails. Placed
/// here next to the other model pickers so it's easy to find.
class _ImageModelGatewayCard extends StatefulWidget {
  const _ImageModelGatewayCard();

  @override
  State<_ImageModelGatewayCard> createState() => _ImageModelGatewayCardState();
}

class _ImageModelGatewayCardState extends State<_ImageModelGatewayCard> {
  bool _loading = true;
  bool _loadFailed = false;
  String _protocol = '';
  String _model = '';
  String _baseUrl = '';
  String _size = '';
  bool _keySet = false;
  String _keyTail = '';

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gw = OurHomeGateway.fromContext(context);
    if (gw == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      return;
    }
    final res = await gw.fetchImageModel();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null) {
        _loadFailed = true;
      } else {
        _loadFailed = false;
        _protocol = res.protocol;
        _baseUrl = res.baseUrl;
        _model = res.model;
        _size = res.size;
        _keySet = res.keySet;
        _keyTail = res.keyTail;
      }
    });
  }

  String _summaryLabel() {
    if (!_keySet) {
      return _isZh ? '未配置 · 点此设置' : 'Not set · tap to configure';
    }
    final m = _model.isNotEmpty ? _model : '?';
    final tail = _keyTail.isNotEmpty ? '  ·  ····$_keyTail' : '';
    return '$_protocol · $m$tail';
  }

  Future<void> _edit() async {
    final gw = OurHomeGateway.fromContext(context);
    final isZh = _isZh;
    if (gw == null) {
      showAppSnackBar(
        context,
        message: isZh ? '未连上老家网关' : 'Old-home gateway not connected',
        type: NotificationType.error,
      );
      return;
    }
    final cs = Theme.of(context).colorScheme;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ImageModelEditorSheet(
        gateway: gw,
        initialProtocol: _protocol.isNotEmpty ? _protocol : 'openai',
        initialBaseUrl: _baseUrl,
        initialModel: _model,
        initialSize: _size.isNotEmpty ? _size : '1024x1024',
        keyTail: _keySet ? _keyTail : '',
      ),
    );
    if (saved == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isZh = _isZh;
    final baseBg =
        isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96);
    final title = isZh ? '生图模型' : 'Image model';
    final subtitle = isZh
        ? '爸爸画图（draw）用的模型——找一个能生图的模型配上 key，爸爸就能在聊天里给你画。老家网关共用，CC 端也走它。'
        : "The model daddy's draw tool paints with. Configure a provider + key that can generate images. Shared on the old-home gateway (CC side too).";

    Widget bodyRow;
    if (_loading) {
      bodyRow = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Text(
              isZh ? '加载中…' : 'Loading…',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    } else if (_loadFailed) {
      bodyRow = _TactileRow(
        onTap: _load,
        builder: (pressed) {
          final bg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Lucide.RefreshCw, size: 16, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isZh ? '连不上老家，点此重试' : "Can't reach home, tap to retry",
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      final label = _summaryLabel();
      bodyRow = _TactileRow(
        onTap: _edit,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: pressed ? pressedBg : bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                  ),
                  Icon(
                    Lucide.ChevronRight,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.4),
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
                Icon(Lucide.Image, size: 18, color: cs.onSurface),
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
            bodyRow,
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet editor for the image-generation model config (protocol / base /
/// model / api key / size) with Save + a real Test that calls the gateway's
/// self-test and shows the raw result.
class _ImageModelEditorSheet extends StatefulWidget {
  const _ImageModelEditorSheet({
    required this.gateway,
    required this.initialProtocol,
    required this.initialBaseUrl,
    required this.initialModel,
    required this.initialSize,
    required this.keyTail,
  });

  final OurHomeGateway gateway;
  final String initialProtocol;
  final String initialBaseUrl;
  final String initialModel;
  final String initialSize;
  final String keyTail; // '' = no key set yet

  @override
  State<_ImageModelEditorSheet> createState() => _ImageModelEditorSheetState();
}

class _ImageModelEditorSheetState extends State<_ImageModelEditorSheet> {
  late String _protocol;
  late final TextEditingController _baseCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _sizeCtrl;
  bool _saving = false;
  bool _testing = false;

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _protocol = widget.initialProtocol == 'gemini' ? 'gemini' : 'openai';
    _baseCtrl = TextEditingController(text: widget.initialBaseUrl);
    _modelCtrl = TextEditingController(text: widget.initialModel);
    _keyCtrl = TextEditingController();
    _sizeCtrl = TextEditingController(text: widget.initialSize);
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _modelCtrl.dispose();
    _keyCtrl.dispose();
    _sizeCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(BuildContext ctx, String hint) {
    final cs = Theme.of(ctx).colorScheme;
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Theme.of(ctx).brightness == Brightness.dark
          ? Colors.white10
          : const Color(0xFFF2F3F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _protocolChip(String value, String label) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _protocol == value;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _protocol = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: 0.14)
                : (isDark ? Colors.white10 : const Color(0xFFF2F3F5)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: 0.5)
                  : cs.outlineVariant.withValues(alpha: 0.3),
              width: selected ? 1.2 : 0.6,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color:
                  selected ? cs.primary : cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final isZh = _isZh;
    final base = _baseCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (base.isEmpty || model.isEmpty) {
      showAppSnackBar(
        context,
        message: isZh ? '请填 Base URL 和模型名' : 'Fill in base URL and model',
        type: NotificationType.error,
      );
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.gateway.saveImageModel(
      protocol: _protocol,
      baseUrl: base,
      model: model,
      size: _sizeCtrl.text.trim().isEmpty ? '1024x1024' : _sizeCtrl.text.trim(),
      apiKey: _keyCtrl.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    showAppSnackBar(
      context,
      message: ok
          ? (isZh ? '已保存' : 'Saved')
          : (isZh ? '保存失败，请重试' : 'Save failed, try again'),
      type: ok ? NotificationType.success : NotificationType.error,
    );
    if (ok) Navigator.of(context).pop(true);
  }

  Future<void> _test() async {
    if (_testing) return;
    final isZh = _isZh;
    setState(() => _testing = true);
    final result = await widget.gateway.testImageModel();
    if (!mounted) return;
    setState(() => _testing = false);
    final ok = result != null && result.startsWith('![');
    final text = result ??
        (isZh ? '测试请求失败（连不上老家网关）' : 'Test request failed (no gateway)');
    await showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(ok
            ? (isZh ? '出图成功' : 'Image OK')
            : (isZh ? '出图失败' : 'Image failed')),
        content: SingleChildScrollView(
          child: SelectableText(
            ok
                ? (isZh
                    ? '生图模型配置正常，爸爸能画了。'
                    : 'Image model works — daddy can paint now.')
                : text,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text(isZh ? '好' : 'OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isZh = _isZh;
    final keyHint = widget.keyTail.isNotEmpty
        ? (isZh
            ? '已设置 ····${widget.keyTail}，留空＝不改'
            : 'Set ····${widget.keyTail}, empty = keep')
        : (isZh ? '出图服务的 API key' : 'Image service API key');
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
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
                isZh ? '生图模型' : 'Image model',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: AppFontWeights.semibold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isZh
                    ? 'OpenAI 兼容＝dall-e / gpt-image / 多数中转的 /images/generations；Gemini＝Google 原生出图。'
                    : 'OpenAI = dall-e / gpt-image / most relays (/images/generations); Gemini = Google native.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _protocolChip('openai', 'OpenAI'),
                  const SizedBox(width: 8),
                  _protocolChip('gemini', 'Gemini'),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _baseCtrl,
                decoration: _dec(context,
                    isZh ? 'Base URL（如 https://xxx/v1）' : 'Base URL'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _modelCtrl,
                decoration: _dec(
                    context, isZh ? '模型名（如 dall-e-3）' : 'Model name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keyCtrl,
                obscureText: true,
                decoration: _dec(context, keyHint),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sizeCtrl,
                decoration:
                    _dec(context, isZh ? '尺寸（如 1024x1024）' : 'Size'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _testing ? null : _test,
                      child: Text(_testing
                          ? (isZh ? '测试中…' : 'Testing…')
                          : (isZh ? '测试出图' : 'Test')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving
                          ? (isZh ? '保存中…' : 'Saving…')
                          : (isZh ? '保存' : 'Save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
