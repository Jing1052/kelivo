import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../icons/lucide_adapter.dart' as lucide;
import '../../l10n/app_localizations.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/ourhome/ourhome_gateway.dart';
import '../../shared/widgets/snackbar.dart';
import '../../shared/widgets/ios_switch.dart';
import '../../features/model/widgets/model_select_sheet.dart';
import '../../features/model/utils/ocr_model_capability.dart';
import '../../utils/brand_assets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/app_font_weights.dart';

class DesktopDefaultModelPane extends StatelessWidget {
  const DesktopDefaultModelPane({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
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

    return Container(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Center(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 36,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.defaultModelPageTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: AppFontWeights.regular,
                          color: cs.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  _ModelCard(
                    icon: lucide.Lucide.MessageCircle,
                    title: l10n.defaultModelPageChatModelTitle,
                    subtitle: l10n.defaultModelPageChatModelSubtitle,
                    modelProvider: settings.currentModelProvider,
                    modelId: settings.currentModelId,
                    onReset: () async {
                      await context
                          .read<SettingsProvider>()
                          .resetCurrentModel();
                    },
                    onPick: () async {
                      final settingsProvider = context.read<SettingsProvider>();
                      final sel = await pickConfiguredModel(
                        settings.currentModelProvider,
                        settings.currentModelId,
                      );
                      if (sel != null) {
                        await settingsProvider.setCurrentModel(
                          sel.providerKey,
                          sel.modelId,
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 16),
                  _ModelCard(
                    icon: lucide.Lucide.NotebookTabs,
                    title: l10n.defaultModelPageTitleModelTitle,
                    subtitle: l10n.defaultModelPageTitleModelSubtitle,
                    modelProvider: settings.titleModelProvider,
                    modelId: settings.titleModelId,
                    fallbackProvider: settings.currentModelProvider,
                    fallbackModelId: settings.currentModelId,
                    onReset: () async {
                      await context.read<SettingsProvider>().resetTitleModel();
                    },
                    onPick: () async {
                      final settingsProvider = context.read<SettingsProvider>();
                      final sel = await pickConfiguredModel(
                        settings.titleModelProvider,
                        settings.titleModelId,
                      );
                      if (sel != null) {
                        await settingsProvider.setTitleModel(
                          sel.providerKey,
                          sel.modelId,
                        );
                      }
                    },
                    configAction: () => _showTitlePromptDialog(context),
                  ),

                  const SizedBox(height: 16),
                  _ModelCard(
                    icon: lucide.Lucide.FileText,
                    title: l10n.defaultModelPageSummaryModelTitle,
                    subtitle: l10n.defaultModelPageSummaryModelSubtitle,
                    modelProvider: settings.summaryModelProvider,
                    modelId: settings.summaryModelId,
                    fallbackProvider:
                        settings.titleModelProvider ??
                        settings.currentModelProvider,
                    fallbackModelId:
                        settings.titleModelId ?? settings.currentModelId,
                    onReset: () async {
                      await context
                          .read<SettingsProvider>()
                          .resetSummaryModel();
                    },
                    onPick: () async {
                      final settingsProvider = context.read<SettingsProvider>();
                      final sel = await pickConfiguredModel(
                        settings.summaryModelProvider,
                        settings.summaryModelId,
                      );
                      if (sel != null) {
                        await settingsProvider.setSummaryModel(
                          sel.providerKey,
                          sel.modelId,
                        );
                      }
                    },
                    configAction: () => _showSummaryPromptDialog(context),
                  ),

                  const SizedBox(height: 16),
                  _ModelCard(
                    icon: lucide.Lucide.MessagesSquare,
                    title: l10n.defaultModelPageSuggestionModelTitle,
                    subtitle: l10n.defaultModelPageSuggestionModelSubtitle,
                    modelProvider: settings.suggestionModelProvider,
                    modelId: settings.suggestionModelId,
                    disabledWhenUnset: true,
                    onReset: () async {
                      await context
                          .read<SettingsProvider>()
                          .resetSuggestionModel();
                    },
                    onPick: () async {
                      final settingsProvider = context.read<SettingsProvider>();
                      final sel = await pickConfiguredModel(
                        settings.suggestionModelProvider,
                        settings.suggestionModelId,
                      );
                      if (sel != null) {
                        await settingsProvider.setSuggestionModel(
                          sel.providerKey,
                          sel.modelId,
                        );
                      }
                    },
                    configAction: () => _showSuggestionPromptDialog(context),
                  ),

                  const SizedBox(height: 16),
                  _ModelCard(
                    icon: lucide.Lucide.package2,
                    title: l10n.defaultModelPageCompressModelTitle,
                    subtitle: l10n.defaultModelPageCompressModelSubtitle,
                    modelProvider: settings.compressModelProvider,
                    modelId: settings.compressModelId,
                    fallbackProvider:
                        settings.summaryModelProvider ??
                        settings.titleModelProvider ??
                        settings.currentModelProvider,
                    fallbackModelId:
                        settings.summaryModelId ??
                        settings.titleModelId ??
                        settings.currentModelId,
                    onReset: () async {
                      await context
                          .read<SettingsProvider>()
                          .resetCompressModel();
                    },
                    onPick: () async {
                      final settingsProvider = context.read<SettingsProvider>();
                      final sel = await pickConfiguredModel(
                        settings.compressModelProvider,
                        settings.compressModelId,
                      );
                      if (sel != null) {
                        await settingsProvider.setCompressModel(
                          sel.providerKey,
                          sel.modelId,
                        );
                      }
                    },
                    configAction: () => _showCompressPromptDialog(context),
                  ),

                  const SizedBox(height: 16),
                  _ModelCard(
                    icon: lucide.Lucide.Languages,
                    title: l10n.defaultModelPageTranslateModelTitle,
                    subtitle: l10n.defaultModelPageTranslateModelSubtitle,
                    modelProvider: settings.translateModelProvider,
                    modelId: settings.translateModelId,
                    fallbackProvider: settings.currentModelProvider,
                    fallbackModelId: settings.currentModelId,
                    onReset: () async {
                      await context
                          .read<SettingsProvider>()
                          .resetTranslateModel();
                    },
                    onPick: () async {
                      final settingsProvider = context.read<SettingsProvider>();
                      final sel = await pickConfiguredModel(
                        settings.translateModelProvider,
                        settings.translateModelId,
                      );
                      if (sel != null) {
                        await settingsProvider.setTranslateModel(
                          sel.providerKey,
                          sel.modelId,
                        );
                      }
                    },
                    configAction: () => _showTranslatePromptDialog(context),
                  ),
                  const SizedBox(height: 16),
                  _ModelCard(
                    icon: lucide.Lucide.Eye,
                    title: l10n.defaultModelPageOcrModelTitle,
                    subtitle: l10n.defaultModelPageOcrModelSubtitle,
                    modelProvider: settings.ocrModelProvider,
                    modelId: settings.ocrModelId,
                    disabledWhenUnset: true,
                    onReset: () async {
                      await context.read<SettingsProvider>().resetOcrModel();
                    },
                    onPick: () async {
                      final settingsProvider = context.read<SettingsProvider>();
                      final sel = await pickConfiguredModel(
                        settings.ocrModelProvider,
                        settings.ocrModelId,
                      );
                      if (sel != null) {
                        if (!modelSupportsOcrImageInput(
                          settingsProvider,
                          sel.providerKey,
                          sel.modelId,
                        )) {
                          if (!context.mounted) return;
                          showAppSnackBar(
                            context,
                            message:
                                l10n.defaultModelPageOcrModelRequiresImageInput,
                            type: NotificationType.error,
                          );
                          return;
                        }
                        await settingsProvider.setOcrModel(
                          sel.providerKey,
                          sel.modelId,
                        );
                      }
                    },
                    configAction: () => _showOcrPromptDialog(context),
                  ),
                  const SizedBox(height: 16),
                  const _DiaryBriefGatewayCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTitlePromptDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    final ctrl = TextEditingController(text: sp.titlePrompt);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Consumer<SettingsProvider>(
          builder: (context, sp, _) {
            return Dialog(
              backgroundColor: cs.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TitleThinkingSwitchRow(
                        settings: sp,
                        l10n: l10n,
                        cs: cs,
                        trailing: _SmallIconBtn(
                          icon: lucide.Lucide.X,
                          onTap: () => Navigator.of(ctx).maybePop(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.defaultModelPagePromptLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _promptEditor(
                        ctx,
                        controller: ctrl,
                        hintText: l10n.defaultModelPageTitlePromptHint,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.defaultModelPageTitleVars('{content}', '{locale}'),
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _DeskIosButton(
                            label: l10n.defaultModelPageResetDefault,
                            filled: false,
                            dense: true,
                            onTap: () async {
                              await sp.resetTitlePrompt();
                              await sp.resetTitleGenerationThinkingEnabled();
                              ctrl.text = sp.titlePrompt;
                            },
                          ),
                          const Spacer(),
                          _DeskIosButton(
                            label: l10n.defaultModelPageSave,
                            filled: true,
                            dense: true,
                            onTap: () async {
                              await sp.setTitlePrompt(ctrl.text.trim());
                              if (ctx.mounted) Navigator.of(ctx).maybePop();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showTranslatePromptDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    final ctrl = TextEditingController(text: sp.translatePrompt);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.defaultModelPagePromptLabel,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ),
                      _SmallIconBtn(
                        icon: lucide.Lucide.X,
                        onTap: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _promptEditor(
                    ctx,
                    controller: ctrl,
                    hintText: l10n.defaultModelPageTranslatePromptHint,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _DeskIosButton(
                        label: l10n.defaultModelPageResetDefault,
                        filled: false,
                        dense: true,
                        onTap: () async {
                          await sp.resetTranslatePrompt();
                          ctrl.text = sp.translatePrompt;
                        },
                      ),
                      const Spacer(),
                      _DeskIosButton(
                        label: l10n.defaultModelPageSave,
                        filled: true,
                        dense: true,
                        onTap: () async {
                          await sp.setTranslatePrompt(ctrl.text.trim());
                          if (ctx.mounted) Navigator.of(ctx).maybePop();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.defaultModelPageTranslateVars(
                      '{source_text}',
                      '{target_lang}',
                    ),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showOcrPromptDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    final ctrl = TextEditingController(text: sp.ocrPrompt);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.defaultModelPagePromptLabel,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ),
                      _SmallIconBtn(
                        icon: lucide.Lucide.X,
                        onTap: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _promptEditor(
                    ctx,
                    controller: ctrl,
                    hintText: l10n.defaultModelPageOcrPromptHint,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _DeskIosButton(
                        label: l10n.defaultModelPageResetDefault,
                        filled: false,
                        dense: true,
                        onTap: () async {
                          await sp.resetOcrPrompt();
                          ctrl.text = sp.ocrPrompt;
                        },
                      ),
                      const Spacer(),
                      _DeskIosButton(
                        label: l10n.defaultModelPageSave,
                        filled: true,
                        dense: true,
                        onTap: () async {
                          await sp.setOcrPrompt(ctrl.text.trim());
                          if (ctx.mounted) Navigator.of(ctx).maybePop();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSummaryPromptDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    final ctrl = TextEditingController(text: sp.summaryPrompt);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.defaultModelPagePromptLabel,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ),
                      _SmallIconBtn(
                        icon: lucide.Lucide.X,
                        onTap: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _promptEditor(
                    ctx,
                    controller: ctrl,
                    hintText: l10n.defaultModelPageSummaryPromptHint,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _DeskIosButton(
                        label: l10n.defaultModelPageResetDefault,
                        filled: false,
                        dense: true,
                        onTap: () async {
                          await sp.resetSummaryPrompt();
                          ctrl.text = sp.summaryPrompt;
                        },
                      ),
                      const Spacer(),
                      _DeskIosButton(
                        label: l10n.defaultModelPageSave,
                        filled: true,
                        dense: true,
                        onTap: () async {
                          await sp.setSummaryPrompt(ctrl.text.trim());
                          if (ctx.mounted) Navigator.of(ctx).maybePop();
                        },
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
          ),
        );
      },
    );
  }

  Future<void> _showCompressPromptDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    final ctrl = TextEditingController(text: sp.compressPrompt);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.defaultModelPagePromptLabel,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ),
                      _SmallIconBtn(
                        icon: lucide.Lucide.X,
                        onTap: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _promptEditor(
                    ctx,
                    controller: ctrl,
                    hintText: l10n.defaultModelPageCompressPromptHint,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _DeskIosButton(
                        label: l10n.defaultModelPageResetDefault,
                        filled: false,
                        dense: true,
                        onTap: () async {
                          await sp.resetCompressPrompt();
                          ctrl.text = sp.compressPrompt;
                        },
                      ),
                      const Spacer(),
                      _DeskIosButton(
                        label: l10n.defaultModelPageSave,
                        filled: true,
                        dense: true,
                        onTap: () async {
                          await sp.setCompressPrompt(ctrl.text.trim());
                          if (ctx.mounted) Navigator.of(ctx).maybePop();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.defaultModelPageCompressVars('{content}', '{locale}'),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSuggestionPromptDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final sp = context.read<SettingsProvider>();
    final ctrl = TextEditingController(text: sp.suggestionPrompt);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.defaultModelPagePromptLabel,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ),
                      _SmallIconBtn(
                        icon: lucide.Lucide.X,
                        onTap: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _promptEditor(
                    ctx,
                    controller: ctrl,
                    hintText: l10n.defaultModelPageSuggestionPromptHint,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _DeskIosButton(
                        label: l10n.defaultModelPageResetDefault,
                        filled: false,
                        dense: true,
                        onTap: () async {
                          await sp.resetSuggestionPrompt();
                          ctrl.text = sp.suggestionPrompt;
                        },
                      ),
                      const Spacer(),
                      _DeskIosButton(
                        label: l10n.defaultModelPageSave,
                        filled: true,
                        dense: true,
                        onTap: () async {
                          await sp.setSuggestionPrompt(ctrl.text.trim());
                          if (ctx.mounted) Navigator.of(ctx).maybePop();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.defaultModelPageSuggestionVars(
                      '{content}',
                      '{locale}',
                    ),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Desktop counterpart to the mobile _DiaryBriefGatewayCard.
/// Picks the gateway's 'diary_brief' role route and toggles the diary-draft
/// feature. Mirrors the mobile card's pattern (fetch on load, pick sheet, snackbar).
class _DiaryBriefGatewayCard extends StatefulWidget {
  const _DiaryBriefGatewayCard();

  @override
  State<_DiaryBriefGatewayCard> createState() =>
      _DiaryBriefGatewayCardState();
}

class _DiaryBriefGatewayCardState extends State<_DiaryBriefGatewayCard> {
  OurHomeGateway? _gateway;
  bool _loading = true;
  bool _noGateway = false;
  List<({String id, String name, String model})> _profiles = const [];
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
    final profiles = _profiles;
    final currentId = _diaryBriefId;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final rowBg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
        Widget row({
          required String label,
          String? sub,
          required bool selectedNow,
          required VoidCallback onTap,
        }) {
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: selectedNow ? rowBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
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
                              fontSize: 14,
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
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selectedNow)
                      Icon(
                        lucide.Lucide.Check,
                        size: 16,
                        color: cs.primary,
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 40,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  row(
                    label: isZh
                        ? '跟随聊天中转站（默认）'
                        : 'Follow chat relay (default)',
                    selectedNow: currentId.isEmpty,
                    onTap: () => Navigator.of(ctx).pop(''),
                  ),
                  for (final p in profiles)
                    row(
                      label: p.name.isNotEmpty ? p.name : p.id,
                      sub: p.model,
                      selectedNow: p.id == currentId,
                      onTap: () => Navigator.of(ctx).pop(p.id),
                    ),
                ],
              ),
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
    final borderColor = cs.outlineVariant.withValues(
      alpha: isDark ? 0.08 : 0.06,
    );
    final rowBg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);

    Widget modelBody;
    if (_loading) {
      modelBody = const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: 16,
          height: 16,
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
      modelBody = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _pick,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: rowBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _BrandCircle(name: _currentLabel, size: 22),
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
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.6),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card header
            Row(
              children: [
                Icon(lucide.Lucide.NotebookTabs, size: 18, color: cs.onSurface),
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
            // Enable switch row
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final newVal = !settings.dailyBriefEnabled;
                  await settings.setDailyBriefEnabled(newVal);
                  final gw = OurHomeGateway.fromContext(context);
                  if (gw == null) return;
                  final ok = await gw.setDailyBriefEnabled(newVal);
                  if (!mounted) return;
                  if (!ok) {
                    await settings.setDailyBriefEnabled(!newVal);
                    showAppSnackBar(
                      context,
                      message: isZh ? '保存失败，请重试' : 'Save failed, try again',
                      type: NotificationType.error,
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: rowBg,
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
                        onChanged: null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Model sub-section label
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

class _ModelCard extends StatefulWidget {
  const _ModelCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.modelProvider,
    required this.modelId,
    required this.onPick,
    this.fallbackProvider,
    this.fallbackModelId,
    this.disabledWhenUnset = false,
    this.onReset,
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
  final VoidCallback? onReset;
  final VoidCallback onPick;
  final VoidCallback? configAction;

  @override
  State<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<_ModelCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.read<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;

    final usingFallback =
        widget.modelProvider == null || widget.modelId == null;
    final effectiveProvider = widget.modelProvider ?? widget.fallbackProvider;
    final effectiveModelId = widget.modelId ?? widget.fallbackModelId;

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
    if (usingFallback) {
      modelDisplay = widget.disabledWhenUnset
          ? l10n.defaultModelPageNotEnabled
          : l10n.defaultModelPageUseCurrentModel;
    }

    final baseBg = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);
    final borderColor = cs.outlineVariant.withValues(
      alpha: isDark ? 0.08 : 0.06,
    );
    final rowBase = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
    final hoverOverlay = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    return Container(
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.6),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, size: 18, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
                if (widget.onReset != null && !usingFallback)
                  Tooltip(
                    message: l10n.defaultModelPageResetDefault,
                    child: _SmallIconBtn(
                      icon: lucide.Lucide.RotateCcw,
                      onTap: widget.onReset!,
                    ),
                  ),
                if (widget.configAction != null)
                  _SmallIconBtn(
                    icon: lucide.Lucide.Settings,
                    onTap: widget.configAction!,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),

            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                onTap: widget.onPick,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _hover
                        ? Color.alphaBlend(hoverOverlay, rowBase)
                        : rowBase,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _BrandCircle(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleThinkingSwitchRow extends StatelessWidget {
  const _TitleThinkingSwitchRow({
    required this.settings,
    required this.l10n,
    required this.cs,
    required this.trailing,
  });

  final SettingsProvider settings;
  final AppLocalizations l10n;
  final ColorScheme cs;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final value = settings.titleGenerationThinkingEnabled;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => settings.setTitleGenerationThinkingEnabled(!value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.titleModelThinkingTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: AppFontWeights.semibold,
                          color: cs.onSurface.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    IosSwitch(
                      value: value,
                      hitTestSize: 36,
                      semanticLabel: l10n.titleModelThinkingTitle,
                      onChanged: settings.setTitleGenerationThinkingEnabled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    );
  }
}

class _DeskIosButton extends StatefulWidget {
  const _DeskIosButton({
    required this.label,
    required this.filled,
    required this.dense,
    required this.onTap,
  });
  final String label;
  final bool filled;
  final bool dense;
  final VoidCallback onTap;
  @override
  State<_DeskIosButton> createState() => _DeskIosButtonState();
}

class _DeskIosButtonState extends State<_DeskIosButton> {
  bool _hover = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = widget.filled
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.8);
    final textColor = widget.filled ? Colors.white : baseColor;
    final bg = widget.filled
        ? (_hover ? cs.primary.withValues(alpha: 0.92) : cs.primary)
        : (_hover
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05))
              : Colors.transparent);
    final borderColor = widget.filled
        ? Colors.transparent
        : cs.outlineVariant.withValues(alpha: isDark ? 0.22 : 0.18);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: widget.dense ? 8 : 12,
              horizontal: 12,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: textColor,
                fontWeight: AppFontWeights.semibold,
                fontSize: widget.dense ? 13 : 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatefulWidget {
  const _SmallIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  State<_SmallIconBtn> createState() => _SmallIconBtnState();
}

class _SmallIconBtnState extends State<_SmallIconBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover
        ? (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05))
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 18, color: cs.onSurface),
        ),
      ),
    );
  }
}

class _BrandCircle extends StatelessWidget {
  const _BrandCircle({required this.name, this.size = 22});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = BrandAssets.assetForName(name);
    Widget inner;
    if (asset == null) {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.heavy,
          fontSize: size * 0.45,
        ),
      );
    } else if (asset.endsWith('.svg')) {
      inner = SvgPicture.asset(
        asset,
        width: size * 0.62,
        height: size * 0.62,
        fit: BoxFit.contain,
      );
    } else {
      inner = Image.asset(
        asset,
        width: size * 0.62,
        height: size * 0.62,
        fit: BoxFit.contain,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

Widget _promptEditor(
  BuildContext context, {
  required TextEditingController controller,
  required String hintText,
}) {
  final editorHeight = (MediaQuery.of(context).size.height * 0.45).clamp(
    180.0,
    420.0,
  );
  return SizedBox(
    height: editorHeight.toDouble(),
    child: TextField(
      controller: controller,
      maxLines: null,
      minLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: TextStyle(fontSize: 14),
      decoration: _deskInputDecoration(context).copyWith(hintText: hintText),
    ),
  );
}

InputDecoration _deskInputDecoration(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cs = Theme.of(context).colorScheme;
  return InputDecoration(
    isDense: false,
    filled: true,
    fillColor: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.2),
        width: 0.8,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.2),
        width: 0.8,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: cs.primary.withValues(alpha: 0.45),
        width: 1.0,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}
