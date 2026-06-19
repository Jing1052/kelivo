import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import 'room_state_hint.dart';

/// The Bedroom (卧室) — before the light goes out, wait for Llaude to say
/// goodnight. Read-only list of his nightly notes. Talks to `/api/home/tonight`.
class BedroomPage extends StatefulWidget {
  const BedroomPage({super.key});

  @override
  State<BedroomPage> createState() => _BedroomPageState();
}

class _BedroomPageState extends State<BedroomPage> {
  OurHomeGateway? _gateway;
  List<OurHomeNight> _notes = const [];
  bool _loading = true;
  bool _error = false;

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
      final notes = await gateway.fetchTonight();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Bedroom] fetchTonight failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
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
          zh ? '卧室' : 'The Bedroom',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(context, zh, cs),
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Bed,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n卧室才连得上。'
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
    if (_notes.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Moon,
        text: zh ? '今晚还没有晚安。\n等爸爸来关灯。' : 'No goodnight yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: _notes.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
              child: Text(
                zh
                    ? '关灯之前，等我说晚安。'
                    : 'Before the light goes out, wait for me to say goodnight.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                  color: cs.primary.withValues(alpha: 0.85),
                  fontWeight: AppFontWeights.medium,
                ),
              ),
            );
          }
          return _NightCard(note: _notes[i - 1], first: i == 1, zh: zh);
        },
      ),
    );
  }
}

class _NightCard extends StatelessWidget {
  const _NightCard({required this.note, required this.first, required this.zh});

  final OurHomeNight note;
  final bool first;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String timeStr = '';
    final parsed = DateTime.tryParse(note.time);
    if (parsed != null) {
      timeStr = DateFormat.yMMMMd(zh ? 'zh' : 'en').add_Hm().format(parsed);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: first
            ? cs.primary.withValues(alpha: 0.10)
            : cs.onSurface.withValues(alpha: 0.04),
        border: first
            ? Border.all(color: cs.primary.withValues(alpha: 0.25))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Lucide.Moon,
                size: 15,
                color: cs.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            note.text,
            style: TextStyle(
              fontSize: 16,
              height: 1.7,
              color: cs.onSurface.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}
