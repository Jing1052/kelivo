import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';

/// The Parlour (客厅) — the two-faced mailbox. Cing leaves a note; Llaude lifts
/// the lid each day and replies. Fully native, talks to `/api/home/board`.
class ParlourPage extends StatefulWidget {
  const ParlourPage({super.key});

  @override
  State<ParlourPage> createState() => _ParlourPageState();
}

class _ParlourPageState extends State<ParlourPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  OurHomeGateway? _gateway;
  List<OurHomeBoardNote> _notes = const [];
  bool _loading = true;
  bool _error = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
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
      final notes = await gateway.fetchBoard();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Parlour] fetchBoard failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final gateway = _gateway;
    if (text.isEmpty || gateway == null || _sending) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    setState(() => _sending = true);
    Haptics.soft();
    try {
      await gateway.postBoardNote(text);
      _input.clear();
      _focus.unfocus();
      await _load();
    } catch (e) {
      debugPrint('[Parlour] postBoardNote failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(zh ? '没发出去，再试一次' : "couldn't send, try again"),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
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
          zh ? '客厅' : 'The Parlour',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(context, zh, cs)),
          _buildComposer(context, zh, cs),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return _Hint(
        icon: Lucide.Mail,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n客厅才连得上。'
            : 'Set up our home gateway in the daddy assistant first.',
      );
    }
    if (_error) {
      return _Hint(
        icon: Lucide.RefreshCw,
        text: zh ? '没连上 · 点一下重试' : "couldn't load · tap to retry",
        onTap: _load,
      );
    }
    if (_notes.isEmpty) {
      return _Hint(
        icon: Lucide.Mail,
        text: zh
            ? '还没有留言。\n给爸爸留第一句话吧。'
            : 'No notes yet.\nLeave Llaude the first word.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _notes.length,
        itemBuilder: (context, i) => _NoteCard(note: _notes[i], zh: zh),
      ),
    );
  }

  Widget _buildComposer(BuildContext context, bool zh, ColorScheme cs) {
    final canSend = !_sending && _gateway != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  enabled: _gateway != null,
                  style: const TextStyle(fontSize: 15.5),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: zh ? '给爸爸留句话…' : 'Leave Llaude a word…',
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(enabled: canSend, sending: _sending, onTap: _send),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.18),
        ),
        child: sending
            ? Padding(
                padding: const EdgeInsets.all(11),
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: cs.onPrimary,
                ),
              )
            : Icon(Lucide.ArrowUp, size: 20, color: cs.onPrimary),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.zh});

  final OurHomeBoardNote note;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String timeStr = '';
    final parsed = DateTime.tryParse(note.time);
    if (parsed != null) {
      final now = DateTime.now();
      timeStr = (now.difference(parsed).inDays >= 1)
          ? DateFormat.MMMd().add_Hm().format(parsed)
          : DateFormat.Hm().format(parsed);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                zh ? '你' : 'You',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.primary.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
              const Spacer(),
              if (note.react.isNotEmpty)
                Text(note.react, style: const TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note.text,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.45,
              color: cs.onSurface.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 10),
          if (note.answered)
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Llaude',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    note.reply,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Icon(
                  note.read ? Lucide.Eye : Lucide.Mail,
                  size: 13,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  note.read
                      ? (zh ? '爸爸看过了，等他回' : 'Llaude has read it')
                      : (zh ? '等爸爸来揭' : 'waiting for Llaude'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: cs.onSurface.withValues(alpha: 0.28)),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: onTap == null
            ? child
            : GestureDetector(onTap: onTap, child: child),
      ),
    );
  }
}
