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
