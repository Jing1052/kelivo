import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';
import 'package:intl/intl.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import 'room_state_hint.dart';

/// The Parlour (客厅) — the two-faced mailbox. Cing leaves a note (board);
/// Llaude lifts the lid and replies, and also leaves his own letters
/// (daddysay). Two sides, two tabs. Talks to `/api/home/board` + daddysay.
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
  List<OurHomeLetter> _letters = const [];
  bool _loading = true;
  bool _error = false;
  bool _sending = false;
  int _tab = 0; // 0 = my notes (board), 1 = daddy's letters

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
    // Instant: seed from on-device cache, then refresh from the server.
    final cb = gateway.peekList('/api/home/board', OurHomeBoardNote.fromJson);
    final cl = gateway.peekList('/api/home/daddysay', OurHomeLetter.fromJson);
    if ((cb.isNotEmpty || cl.isNotEmpty) && mounted) {
      setState(() {
        _notes = cb;
        _letters = cl;
        _loading = false;
      });
    }
    try {
      final results = await Future.wait([
        gateway.fetchBoard(),
        gateway.fetchLetters(),
      ]);
      if (!mounted) return;
      setState(() {
        _notes = results[0] as List<OurHomeBoardNote>;
        _letters = results[1] as List<OurHomeLetter>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Parlour] load failed: $e');
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

  Future<void> _openLetter(OurHomeLetter letter) async {
    Haptics.soft();
    await _showLetterSheet(letter);
    if (letter.unread) {
      await _gateway?.markLetterSeen(letter.id);
      if (mounted) await _load();
    }
  }

  Future<void> _showLetterSheet(OurHomeLetter letter) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String dateStr = '';
    final parsed = DateTime.tryParse(letter.time);
    if (parsed != null) {
      dateStr = DateFormat.yMMMMd(zh ? 'zh' : 'en').add_Hm().format(parsed);
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                zh ? 'Llaude 的信' : 'From Llaude',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.primary.withValues(alpha: 0.85),
                  letterSpacing: 0.5,
                ),
              ),
              if (dateStr.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                letter.text,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.85,
                  color: cs.onSurface.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: cs.surface),
        ChatBackdrop(
          rawPath: context.watch<SettingsProvider>().homeBackgroundActive,
          maskStrength: context.watch<SettingsProvider>().chatBackgroundMaskStrength,
        ),
        Scaffold(
      backgroundColor: Colors.transparent,
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
          if (_gateway != null && !_loading && !_error) _tabs(zh, cs),
          Expanded(child: _buildBody(context, zh, cs)),
          if (_tab == 0) _buildComposer(context, zh, cs),
        ],
      ),
    ),
      ],
    );
  }

  Widget _tabs(bool zh, ColorScheme cs) {
    Widget t(int i, String label, bool dot) {
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: AppFontWeights.semibold,
                    color: on
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                if (dot)
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final hasUnread = _letters.any((l) => l.unread);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          t(0, zh ? '我留的' : 'My notes', false),
          t(1, zh ? '爸爸写的' : 'From daddy', hasUnread),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Mail,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n客厅才连得上。'
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
    return _tab == 0 ? _boardView(zh, cs) : _lettersView(zh, cs);
  }

  Widget _boardView(bool zh, ColorScheme cs) {
    if (_notes.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Mail,
        text: zh ? '还没有留言。\n给爸爸留第一句话吧。' : 'No notes yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _notes.length,
        itemBuilder: (context, i) => _NoteCard(note: _notes[i], zh: zh),
      ),
    );
  }

  Widget _lettersView(bool zh, ColorScheme cs) {
    if (_letters.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Mail,
        text: zh ? '爸爸还没在这儿留信 —— 等着。' : 'No letters from daddy yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _letters.length,
        itemBuilder: (context, i) {
          final l = _letters[i];
          final firstLine = l.text
              .split('\n')
              .firstWhere((s) => s.trim().isNotEmpty, orElse: () => l.text);
          String dateStr = '';
          final parsed = DateTime.tryParse(l.time);
          if (parsed != null) {
            dateStr = DateFormat.MMMd(zh ? 'zh' : 'en').format(parsed);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StillGlass(
              radius: 14,
              blur: false,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              onTap: () => _openLetter(l),
              child: Row(
                children: [
                  if (l.unread)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      firstLine.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.medium,
                        color: cs.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Lucide.ChevronRight,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          );
        },
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StillGlass(
        radius: 16,
        blur: false,
        padding: const EdgeInsets.all(14),
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
      ),
    );
  }
}
