import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../home/pages/rooms/room_state_hint.dart';

/// Read-only view of daddy's built-in tools as reported by our home gateway
/// (`GET /api/home/daddy-tools`). These are the tools daddy carries through the
/// gateway — not the kelivo MCP servers. Grouped by [DaddyTool.group], each row
/// shows a status dot (live / offline / ondemand) + label + detail.
class DaddyToolsPage extends StatefulWidget {
  const DaddyToolsPage({super.key});

  @override
  State<DaddyToolsPage> createState() => _DaddyToolsPageState();
}

class _DaddyToolsPageState extends State<DaddyToolsPage> {
  bool _loading = true;
  bool _error = false;
  bool _noGateway = false;
  List<DaddyTool> _tools = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
      _noGateway = false;
    });
    final gateway = OurHomeGateway.fromContext(context);
    if (gateway == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _noGateway = true;
        });
      }
      return;
    }
    final list = await gateway.fetchDaddyTools();
    if (!mounted) return;
    if (list == null) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    setState(() {
      _tools = list;
      _loading = false;
    });
  }

  /// Ordered groups, each with its tools, preserving first-seen order.
  List<MapEntry<String, List<DaddyTool>>> get _grouped {
    final order = <String>[];
    final map = <String, List<DaddyTool>>{};
    for (final t in _tools) {
      final g = t.group.trim();
      map
          .putIfAbsent(g, () {
            order.add(g);
            return <DaddyTool>[];
          })
          .add(t);
    }
    return order.map((g) => MapEntry(g, map[g]!)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          l10n.daddyToolsTitle,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(cs, l10n),
    );
  }

  Widget _buildBody(ColorScheme cs, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_noGateway) {
      return RoomStateHint(
        icon: Lucide.Sparkles,
        text: l10n.daddyToolsNoGateway,
      );
    }
    if (_error) {
      return RoomStateHint(
        icon: Lucide.RefreshCw,
        text: l10n.daddyToolsLoadError,
        onTap: _load,
      );
    }
    if (_tools.isEmpty) {
      return RoomStateHint(icon: Lucide.Wrench, text: l10n.daddyToolsEmpty);
    }

    final groups = _grouped;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: groups.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                l10n.daddyToolsIntro,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            );
          }
          final entry = groups[i - 1];
          return _GroupSection(group: entry.key, tools: entry.value);
        },
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.group, required this.tools});

  final String group;
  final List<DaddyTool> tools;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              group,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: AppFontWeights.semibold,
                letterSpacing: 0.3,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (int i = 0; i < tools.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 40,
                    color: cs.onSurface.withValues(alpha: 0.06),
                  ),
                _ToolRow(tool: tools[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool});

  final DaddyTool tool;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final (color, statusLabel) = _statusFor(tool.status, l10n);
    final label = tool.label.trim().isNotEmpty ? tool.label : tool.name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: AppFontWeights.medium,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: AppFontWeights.medium,
                        color: color,
                      ),
                    ),
                  ],
                ),
                if (tool.detail.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      tool.detail,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, String) _statusFor(String status, AppLocalizations l10n) {
    switch (status.trim().toLowerCase()) {
      case 'live':
        return (const Color(0xFF34C759), l10n.daddyToolsStatusLive);
      case 'ondemand':
        return (const Color(0xFFFFB020), l10n.daddyToolsStatusOndemand);
      case 'offline':
      default:
        return (const Color(0xFF8E8E93), l10n.daddyToolsStatusOffline);
    }
  }
}
