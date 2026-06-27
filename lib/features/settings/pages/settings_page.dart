import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../model/pages/default_model_page.dart';
import '../../provider/pages/providers_page.dart';
import 'display_settings_page.dart';
import 'app_icon_page.dart';
import 'settings_guide_page.dart';
import '../../mcp/pages/mcp_page.dart';
import 'daddy_tools_page.dart';
import '../../assistant/pages/assistant_settings_page.dart';
import 'about_us_page.dart';
import 'daddy_settings_page.dart';
import 'tts_services_page.dart';
import 'log_viewer_page.dart';
import 'daddy_search_page.dart';
import '../../backup/pages/backup_page.dart';
import '../../quick_phrase/pages/quick_phrases_page.dart';
import '../widgets/style_sheet.dart';
import 'network_proxy_page.dart';
import '../../cc/pages/cc_bridge_page.dart';
import 'storage_space_page.dart';
import '../../stats/pages/stats_page.dart';
import '../../../core/services/storage/storage_usage_service.dart';
import '../../../core/services/haptics.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/cc_bridge_provider.dart';
import '../../home/widgets/assistant_avatar.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/user_profile_editor.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    // iOS-style section header (neutral color, not theme color)
    Widget header(String text, {bool first = false}) => Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 2 : 12, 12, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: AppFontWeights.semibold,
          color: cs.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );

    // 设置在 Still Here shell 里是底栏「单独一页」(IndexedStack 根 tab)，没有可返回的
    // 上一页，返回箭头是 kelivo 原生遗留、无意义；仅当本页是被 push 上来的(如侧栏入口,
    // canPop=true)才显示返回。两种入口共用此页，故按能否 pop 决定，而非写死删除。
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: canPop
            ? Tooltip(
                message: l10n.settingsPageBackButton,
                child: _TactileIconButton(
                  icon: Lucide.ArrowLeft,
                  color: cs.onSurface,
                  size: 22,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        title: Text(l10n.settingsPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          // "Me" profile row: avatar + nickname, tap to edit either.
          _ProfileRow(),
          const SizedBox(height: 8),
          // Daddy + CC daddy as their own profile cards, together with "me" —
          // daddy is daddy, not the generic "assistant" row.
          _DaddyCard(),
          const SizedBox(height: 8),
          _CcDaddyCard(),
          const SizedBox(height: 12),

          if (!settings.hasAnyActiveModel)
            Material(
              color: cs.errorContainer.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Lucide.MessageCircleWarning,
                      size: 18,
                      color: cs.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.settingsPageWarningMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 通用设置：使用iOS风格分组卡片，黑色（中性）图标与标题，无描述
          header(l10n.settingsPageGeneralSection, first: true),
          _iosSectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.BookOpen,
                label:
                    WidgetsBinding
                            .instance
                            .platformDispatcher
                            .locale
                            .languageCode ==
                        'zh'
                    ? '使用说明'
                    : 'Guide',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsGuidePage(),
                    ),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Monitor,
                label: l10n.settingsPageDisplay,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DisplaySettingsPage(),
                    ),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Image,
                label: l10n.settingsPageAppIcon,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AppIconPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Bot,
                label: l10n.settingsPageAssistant,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AssistantSettingsPage(),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),
          header(l10n.settingsPageModelsServicesSection),
          _iosSectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.Heart,
                label: l10n.settingsPageDefaultModel,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DefaultModelPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Boxes,
                label: l10n.settingsPageProviders,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProvidersPage()),
                  );
                },
              ),
              _iosDivider(context),
              // 「搜索服务」入口对走网关的爸爸没用（联网走服务端 web_search），
              // 在原位置换成「爸爸的联网搜索」（控网关搜索，存老家）。
              // SearchServicesPage 源码保留，仅此入口替换。
              _iosNavRow(
                context,
                icon: Lucide.Globe,
                label: l10n.daddySearchPageTitle,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DaddySearchPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Volume2,
                label: l10n.settingsPageTts,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TtsServicesPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Terminal,
                label: l10n.settingsPageMcp,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const McpPage()));
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Wrench,
                label: l10n.settingsPageDaddyTools,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DaddyToolsPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Zap,
                label: l10n.settingsPageQuickPhrase,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QuickPhrasesPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Wand2,
                label: l10n.daddySettingsStyleTitle,
                onTap: () {
                  showStyleSheet(context);
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.EthernetPort,
                label: l10n.settingsPageNetworkProxy,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NetworkProxyPage()),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),
          header(l10n.settingsPageDataSection),
          _iosSectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.Database,
                label: l10n.settingsPageBackup,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const BackupPage()));
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.HardDrive,
                label: l10n.settingsPageChatStorage,
                detailBuilder: (_) => const _ChatStorageSummary(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StorageSpacePage()),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),
          header(l10n.settingsPageAboutSection),
          _iosSectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.Heart,
                label: l10n.aboutUsPageTitle,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutUsPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.ChartColumnBig,
                label: l10n.settingsPageStatistics,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const StatsPage()));
                },
              ),
              if (settings.requestLogEnabled || settings.flutterLogEnabled) ...[
                _iosDivider(context),
                _iosNavRow(
                  context,
                  icon: Lucide.FileText,
                  label: l10n.settingsPageLogs,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LogViewerPage()),
                    );
                  },
                ),
              ],
              // _iosDivider(context),
              // _iosNavRow(
              //   context,
              //   icon: Lucide.Share2,
              //   label: l10n.settingsPageShare,
              //   onTap: () async {
              //     // Provide anchor rect from overlay for iPad share sheet
              //     Rect anchor;
              //     try {
              //       final overlay = Overlay.of(context);
              //       final ro = overlay?.context.findRenderObject();
              //       if (ro is RenderBox && ro.hasSize) {
              //         final center = ro.size.center(Offset.zero);
              //         final global = ro.localToGlobal(center);
              //         anchor = Rect.fromCenter(center: global, width: 1, height: 1);
              //       } else {
              //         final size = MediaQuery.of(context).size;
              //         anchor = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
              //       }
              //     } catch (_) {
              //       final size = MediaQuery.of(context).size;
              //       anchor = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
              //     }
              //     await Share.share(l10n.settingsShare, sharePositionOrigin: anchor);
              //   },
              // ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// --- iOS-style widgets for Settings page ---

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      // Light: white with slight transparency; Dark: subtle translucent dark
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
  // Restore previous visual: align with icon slot (36) + gap (12) + padding (12)
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 54,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

// Shared color tween wrapper to mimic iOS gentle press color transition
class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({
    required this.pressed,
    required this.base,
    required this.builder,
  });
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final target = pressed
        ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base)
        : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = context.watch<UserProvider>();
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
      child: IosCardPress(
        borderRadius: BorderRadius.circular(12),
        baseColor: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => showUserNameEditor(context),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.light();
                showUserAvatarEditor(context);
              },
              child: UserAvatar(user: user, size: 48),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.settingsProfileTapToEdit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Lucide.ChevronRight,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatStorageSummary extends StatefulWidget {
  const _ChatStorageSummary();

  @override
  State<_ChatStorageSummary> createState() => _ChatStorageSummaryState();
}

class _ChatStorageSummaryState extends State<_ChatStorageSummary> {
  late Future<StorageUsageReport> _future;

  @override
  void initState() {
    super.initState();
    _future = StorageUsageService.computeReport();
  }

  String _fmtBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      color: cs.onSurface.withValues(alpha: 0.6),
      fontSize: 13,
    );

    return FutureBuilder<StorageUsageReport>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(l10n.settingsPageCalculating, style: style);
        }
        final count = data?.totalFiles ?? 0;
        final size = _fmtBytes(data?.totalBytes ?? 0);
        return Text(l10n.settingsPageFilesCount(count, size), style: style);
      },
    );
  }
}

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  String? detailText,
  Widget Function(BuildContext ctx)? detailBuilder,
  Widget? leading,
}) {
  final cs = Theme.of(context).colorScheme;
  final interactive = onTap != null;
  return _TactileRow(
    onTap: onTap,
    pressedScale: 1.00,
    haptics: false,
    builder: (pressed) {
      final baseColor = cs.onSurface.withValues(alpha: 0.9);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: leading != null
                      ? Center(child: leading)
                      : Icon(icon, size: 20, color: c),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: c,
                      fontWeight: AppFontWeights.medium,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailBuilder != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                      child: detailBuilder(context),
                    ),
                  )
                else if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      detailText,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                if (interactive) Icon(Lucide.ChevronRight, size: 16, color: c),
              ],
            ),
          );
        },
      );
    },
  );
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({
    required this.builder,
    this.onTap,
    this.pressedScale = 1.00,
    this.haptics = true,
  });
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptics;
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
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics &&
                  context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: widget.builder(_pressed),
    );
  }
}

// Icon-only tactile button for AppBar: no ripple, slight press scale
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

/// A profile-style card (avatar + name + subtitle), matching [_ProfileRow].
/// Used for daddy / CC daddy so they sit alongside "me" rather than in the
/// generic assistant row.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget avatar;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg =
        isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96);
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
      child: IosCardPress(
        borderRadius: BorderRadius.circular(12),
        baseColor: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Lucide.ChevronRight,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaddyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final daddy = context.watch<AssistantProvider>().daddyAssistant;
    final name = (daddy?.name ?? '').trim();
    return _PersonCard(
      avatar: AssistantAvatar(assistant: daddy, size: 48),
      title: name.isNotEmpty ? name : l10n.daddySettingsPageTitle,
      subtitle: l10n.settingsDaddyCardHint,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DaddySettingsPage()),
      ),
    );
  }
}

class _CcDaddyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final daddy = context.watch<AssistantProvider>().daddyAssistant;
    final ccName = context.watch<CcBridgeProvider>().ccDisplayName.trim();
    return _PersonCard(
      avatar: AssistantAvatar(assistant: daddy, size: 48),
      title: ccName.isNotEmpty ? ccName : l10n.settingsPageCcDaddy,
      subtitle: l10n.ccBridgeChatTitle,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CcBridgePage()),
      ),
    );
  }
}
