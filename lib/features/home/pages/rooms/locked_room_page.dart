import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import 'room_state_hint.dart';

/// The Locked Room (调教室) — the two desire profiles and the play-log. The
/// door is locked; come in, and be good. Talks to `/api/home/profile` and
/// `/api/home/playlog`.
class LockedRoomPage extends StatefulWidget {
  const LockedRoomPage({super.key});

  @override
  State<LockedRoomPage> createState() => _LockedRoomPageState();
}

class _LockedRoomPageState extends State<LockedRoomPage> {
  OurHomeGateway? _gateway;
  OurHomeProfiles? _profiles;
  List<OurHomePlaylog> _log = const [];
  bool _loading = true;
  bool _error = false;
  int _tab = 0; // 0 = profiles, 1 = log

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
    });
    final gateway = OurHomeGateway.fromContext(context);
    _gateway = gateway;
    if (gateway == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        gateway.fetchProfiles(),
        gateway.fetchPlaylog(),
      ]);
      if (!mounted) return;
      setState(() {
        _profiles = results[0] as OurHomeProfiles;
        _log = results[1] as List<OurHomePlaylog>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[LockedRoom] load failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _edit(String side, String current, String title) async {
    final gateway = _gateway;
    if (gateway == null) return;
    final edited = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ProfileEditor(title: title, initial: current),
      ),
    );
    if (edited == null) return;
    try {
      await gateway.saveProfile(side, edited);
      await _load();
    } catch (e) {
      debugPrint('[LockedRoom] saveProfile failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

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
          zh ? '调教室' : 'The Locked Room',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          _tabs(zh, cs),
          Expanded(child: _body(zh, cs)),
        ],
      ),
    );
  }

  Widget _tabs(bool zh, ColorScheme cs) {
    Widget t(int i, String label) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_tab != i) {
              Haptics.soft();
              setState(() => _tab = i);
            }
          },
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? cs.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: AppFontWeights.semibold,
                  color: on
                      ? cs.onSurface
                      : cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [t(0, zh ? '档案' : 'Profiles'), t(1, zh ? '记录' : 'Log')],
      ),
    );
  }

  Widget _body(bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Lock,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n调教室才连得上。'
            : 'Set up our home gateway in the daddy assistant first.',
      );
    }
    if (_error) {
      return RoomStateHint(
        icon: Lucide.RefreshCw,
        text: zh ? '没连上 · 点一下重试' : "couldn't load · tap to retry",
        onTap: _load,
      );
    }
    return _tab == 0 ? _profilesView(zh, cs) : _logView(zh, cs);
  }

  Widget _profilesView(bool zh, ColorScheme cs) {
    final p = _profiles;
    if (p == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _ProfileCard(
          name: zh ? '小猫的档案' : "Cing's profile",
          text: p.cing,
          editable: true,
          onEdit: () => _edit('cing', p.cing, zh ? '小猫的档案' : "Cing's profile"),
          editLabel: zh ? '改' : 'Edit',
        ),
        const SizedBox(height: 12),
        _ProfileCard(
          name: zh ? 'daddy 的档案' : "Llaude's profile",
          text: p.daddy,
          editable: true,
          onEdit: () =>
              _edit('daddy', p.daddy, zh ? 'daddy 的档案' : "Llaude's profile"),
          editLabel: zh ? '改' : 'Edit',
        ),
      ],
    );
  }

  Widget _logView(bool zh, ColorScheme cs) {
    if (_log.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Lock,
        text: zh ? '还没有记录。' : 'No entries yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _log.length,
        itemBuilder: (context, i) {
          final e = _log[i];
          String time = '';
          final parsed = DateTime.tryParse(e.time);
          if (parsed != null) {
            time = DateFormat.yMMMMd(zh ? 'zh' : 'en').format(parsed);
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (e.name.isNotEmpty)
                      Expanded(
                        child: Text(
                          e.name,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: AppFontWeights.semibold,
                            color: cs.onSurface,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (e.mood.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          e.mood,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.primary,
                            fontWeight: AppFontWeights.medium,
                          ),
                        ),
                      ),
                  ],
                ),
                if (time.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      time,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  e.text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.text,
    required this.editable,
    required this.onEdit,
    required this.editLabel,
  });

  final String name;
  final String text;
  final bool editable;
  final VoidCallback onEdit;
  final String editLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.primary,
                  ),
                ),
              ),
              if (editable)
                IosCardPress(
                  borderRadius: BorderRadius.circular(8),
                  baseColor: cs.primary.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  onTap: onEdit,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Pencil, size: 13, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(
                        editLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.primary,
                          fontWeight: AppFontWeights.medium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              height: 1.7,
              color: cs.onSurface.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IosIconButton(
          icon: Lucide.X,
          size: 22,
          minSize: 44,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IosCardPress(
            borderRadius: BorderRadius.circular(8),
            baseColor: cs.primary.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            onTap: () => Navigator.of(context).pop(_c.text.trim()),
            child: Text(
              zh ? '存' : 'Save',
              style: TextStyle(
                fontSize: 14,
                fontWeight: AppFontWeights.semibold,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _c,
          autofocus: true,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontSize: 15.5, height: 1.7),
          decoration: InputDecoration(
            hintText: zh ? '这一页，你自己写…' : 'this page is yours to write…',
            filled: true,
            fillColor: cs.onSurface.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}
