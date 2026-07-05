import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/eryu/eryu_player_controller.dart';
import 'package:Kelivo/features/home/widgets/assistant_avatar.dart';
import 'package:Kelivo/features/home/widgets/still_glass.dart';
import 'package:Kelivo/shared/widgets/ios_form_text_field.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:Kelivo/shared/widgets/user_profile_editor.dart';

import '../../../../icons/lucide_adapter.dart';

/// The "在一起" companion view shown in the now-playing page while a room is
/// open: two avatars joined by a cord, the relationship stat line, a compact
/// now-card, and the activity/chat timeline. Ported in spirit from the eryu web
/// client's together panel. The "边听边说" input lives in the page, above the
/// transport bar.
class MusicTogetherView extends StatefulWidget {
  const MusicTogetherView({
    super.key,
    required this.zh,
    required this.onHeart,
    this.companion = '',
  });

  final bool zh;
  final VoidCallback onHeart;

  /// When non-empty, the partner head is an always-present companion (Llaude)
  /// rather than an eryu room peer — a filled avatar instead of the waiting
  /// ghost circle.
  final String companion;

  @override
  State<MusicTogetherView> createState() => _MusicTogetherViewState();
}

class _MusicTogetherViewState extends State<MusicTogetherView> {
  static const _kBubYou = 'music_tg_bub_you_v1';
  static const _kBubPartner = 'music_tg_bub_partner_v1';
  static const _kKm = 'music_tg_km_v1';

  String _bubYou = '今天也一起听';
  String _bubPartner = '嗯嗯！';
  String _km = '520';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _bubYou = p.getString(_kBubYou) ?? _bubYou;
        _bubPartner = p.getString(_kBubPartner) ?? _bubPartner;
        _km = p.getString(_kKm) ?? _km;
      });
    });
  }

  Future<void> _editBubble({required bool mine}) async {
    final zh = widget.zh;
    final v = await _promptText(
      title: zh ? '改一句悄悄话' : 'Edit bubble',
      initial: mine ? _bubYou : _bubPartner,
      maxLength: 24,
    );
    if (v == null) return;
    final p = await SharedPreferences.getInstance();
    setState(() {
      if (mine) {
        _bubYou = v;
      } else {
        _bubPartner = v;
      }
    });
    await p.setString(mine ? _kBubYou : _kBubPartner, v);
  }

  Future<void> _editKm() async {
    final zh = widget.zh;
    final v = await _promptText(
      title: zh ? '改一下距离（公里）' : 'Distance (km)',
      initial: _km,
      maxLength: 6,
      number: true,
    );
    if (v == null) return;
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    final km = digits.isEmpty ? '0' : digits;
    final p = await SharedPreferences.getInstance();
    setState(() => _km = km);
    await p.setString(_kKm, km);
  }

  Future<String?> _promptText({
    required String title,
    required String initial,
    int maxLength = 24,
    bool number = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: IosFormTextField(
          label: '',
          inlineLabel: false,
          controller: controller,
          autofocus: true,
          maxLines: 1,
          keyboardType: number ? TextInputType.number : null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(zh ? '取消' : 'Cancel', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(zh ? '好' : 'OK', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return null;
    return result.characters.take(maxLength).toString();
  }

  String _fmtDur(int secs) {
    final zh = widget.zh;
    final m = secs ~/ 60;
    if (m < 60) return zh ? '$m 分钟' : '$m min';
    final h = m ~/ 60;
    final mm = m % 60;
    if (zh) return mm > 0 ? '$h 小时 $mm 分钟' : '$h 小时';
    return mm > 0 ? '${h}h ${mm}m' : '${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = widget.zh;
    final player = context.watch<EryuPlayerController>();
    final user = context.watch<UserProvider>();
    final companionPresent = widget.companion.isNotEmpty;
    final partner = companionPresent
        ? widget.companion
        : (player.partners.isNotEmpty ? player.partners.first : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bond(
          zh: zh,
          user: user,
          partner: partner,
          daddy: companionPresent,
          bubYou: _bubYou,
          bubPartner: _bubPartner,
          accent: cs.primary,
          ink: cs.onSurface,
          onEditYou: () => _editBubble(mine: true),
          onEditPartner: () => _editBubble(mine: false),
        ),
        const SizedBox(height: 2),
        _StatLine(
          zh: zh,
          km: _km,
          durText: _fmtDur(player.togetherSecs),
          ink: cs.onSurface,
          onEditKm: _editKm,
        ),
        const SizedBox(height: 14),
        _NowCard(zh: zh, player: player, accent: cs.primary, ink: cs.onSurface, onHeart: widget.onHeart),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            zh ? '此刻' : 'Right now',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.5)),
          ),
        ),
        Expanded(child: _Feed(zh: zh, entries: player.feed, accent: cs.primary, ink: cs.onSurface)),
      ],
    );
  }
}

class _Bond extends StatelessWidget {
  const _Bond({
    required this.zh,
    required this.user,
    required this.partner,
    required this.daddy,
    required this.bubYou,
    required this.bubPartner,
    required this.accent,
    required this.ink,
    required this.onEditYou,
    required this.onEditPartner,
  });

  final bool zh;
  final UserProvider user;
  final String partner;
  final bool daddy;
  final String bubYou;
  final String bubPartner;
  final Color accent;
  final Color ink;
  final VoidCallback onEditYou;
  final VoidCallback onEditPartner;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CordPainter(accent))),
          Row(
            children: [
              Expanded(
                child: _Head(
                  bubble: bubYou,
                  name: zh ? '你' : 'You',
                  accent: accent,
                  ink: ink,
                  onEditBubble: onEditYou,
                  avatar: UserAvatar(user: user, size: 68),
                ),
              ),
              Expanded(
                child: _Head(
                  bubble: bubPartner,
                  name: partner.isNotEmpty ? partner : (zh ? '等 TA 来' : 'waiting'),
                  accent: accent,
                  ink: ink,
                  onEditBubble: onEditPartner,
                  avatar: _PartnerAvatar(name: partner, daddy: daddy, accent: accent, ink: ink, size: 68),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({
    required this.bubble,
    required this.name,
    required this.accent,
    required this.ink,
    required this.onEditBubble,
    required this.avatar,
  });

  final String bubble;
  final String name;
  final Color accent;
  final Color ink;
  final VoidCallback onEditBubble;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onEditBubble,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 130),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Text(
              bubble.isEmpty ? '…' : bubble,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xFF3A3A3C), fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: ClipOval(child: avatar),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: ink.withValues(alpha: 0.5)),
        ),
      ],
    );
  }
}

class _PartnerAvatar extends StatelessWidget {
  const _PartnerAvatar({
    required this.name,
    required this.daddy,
    required this.accent,
    required this.ink,
    required this.size,
  });

  final String name;
  final bool daddy;
  final Color accent;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Llaude, always present — his own avatar (the couple avatar she set for the
    // assistant), falling back to his initial if none is set.
    if (daddy) {
      final assistant = context.watch<AssistantProvider>().currentAssistant;
      return AssistantAvatar(assistant: assistant, size: size);
    }
    if (name.isEmpty) {
      // Waiting: a dashed ghost circle.
      return DottedCircle(size: size, color: ink.withValues(alpha: 0.3));
    }
    final letter = name.characters.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: accent.withValues(alpha: 0.16),
      child: Text(letter, style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w600, color: accent)),
    );
  }
}

/// A dashed hollow circle for the "waiting for TA" placeholder head.
class DottedCircle extends StatelessWidget {
  const DottedCircle({super.key, required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _DottedCirclePainter(color),
      child: Center(
        child: Text('?', style: TextStyle(fontSize: size * 0.34, color: color)),
      ),
    );
  }
}

class _DottedCirclePainter extends CustomPainter {
  _DottedCirclePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final r = size.width / 2 - 1;
    final c = Offset(size.width / 2, size.height / 2);
    const dash = 0.28; // radians on
    const gap = 0.20;
    double a = 0;
    while (a < 6.28318) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, dash, false, paint);
      a += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedCirclePainter old) => old.color != color;
}

/// The soft cord that ties the two heads together — a downward-dipping curve
/// with a small dot at each anchor.
class _CordPainter extends CustomPainter {
  _CordPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ax1 = w * 0.25;
    final ax2 = w * 0.75;
    final ay = h * 0.62;
    final dip = h * 0.86;
    final line = Paint()
      ..color = accent.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..moveTo(ax1, ay)
      ..cubicTo(ax1, dip, ax2, dip, ax2, ay);
    canvas.drawPath(path, line);
    final dot = Paint()..color = accent.withValues(alpha: 0.8);
    canvas.drawCircle(Offset(ax1, ay), 2.6, dot);
    canvas.drawCircle(Offset(ax2, ay), 2.6, dot);
  }

  @override
  bool shouldRepaint(covariant _CordPainter old) => old.accent != accent;
}

class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.zh,
    required this.km,
    required this.durText,
    required this.ink,
    required this.onEditKm,
  });

  final bool zh;
  final String km;
  final String durText;
  final Color ink;
  final VoidCallback onEditKm;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.62));
    final strong = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink.withValues(alpha: 0.82));
    return Center(
      child: GestureDetector(
        onTap: onEditKm,
        behavior: HitTestBehavior.opaque,
        child: RichText(
          text: TextSpan(
            style: base,
            children: zh
                ? [
                    const TextSpan(text: '相距 '),
                    TextSpan(text: km, style: strong),
                    const TextSpan(text: ' 公里 · 一起听了 '),
                    TextSpan(text: durText, style: strong),
                  ]
                : [
                    TextSpan(text: km, style: strong),
                    const TextSpan(text: ' km apart · listened '),
                    TextSpan(text: durText, style: strong),
                    const TextSpan(text: ' together'),
                  ],
          ),
        ),
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.zh, required this.player, required this.accent, required this.ink, required this.onHeart});

  final bool zh;
  final EryuPlayerController player;
  final Color accent;
  final Color ink;
  final VoidCallback onHeart;

  @override
  Widget build(BuildContext context) {
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    String? by;
    if (player.controlledBy.isNotEmpty) {
      by = player.controlledBy == player.roomUser
          ? (zh ? '你在放' : 'you\'re playing')
          : '${player.controlledBy} ${zh ? '在放' : 'is playing'}';
    }
    return StillGlass(
      radius: 16,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: song.cover.isEmpty
                ? Container(
                    width: 44,
                    height: 44,
                    color: accent.withValues(alpha: 0.14),
                    child: Icon(Lucide.Music, size: 20, color: accent.withValues(alpha: 0.6)),
                  )
                : Image.network(
                    song.cover,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 44,
                      height: 44,
                      color: accent.withValues(alpha: 0.14),
                      child: Icon(Lucide.Music, size: 20, color: accent.withValues(alpha: 0.6)),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.name.isEmpty ? (zh ? '未知歌曲' : 'Unknown') : song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
                ),
                const SizedBox(height: 2),
                Text(
                  by ?? song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: by != null ? accent.withValues(alpha: 0.85) : ink.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          IosIconButton(
            icon: Lucide.Heart,
            size: 20,
            color: accent,
            minSize: 40,
            onTap: onHeart,
          ),
        ],
      ),
    );
  }
}

class _Feed extends StatelessWidget {
  const _Feed({required this.zh, required this.entries, required this.accent, required this.ink});

  final bool zh;
  final List<RoomFeedEntry> entries;
  final Color accent;
  final Color ink;

  String _relTime(int ts) {
    final d = DateTime.now().millisecondsSinceEpoch - ts;
    if (d < 60000) return zh ? '刚刚' : 'now';
    if (d < 3600000) return zh ? '${d ~/ 60000}分钟前' : '${d ~/ 60000}m';
    return zh ? '${d ~/ 3600000}小时前' : '${d ~/ 3600000}h';
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          zh ? '还没有动静，放首歌吧' : 'Quiet so far — play something',
          style: TextStyle(fontSize: 13, color: ink.withValues(alpha: 0.4)),
        ),
      );
    }
    final reversed = entries.reversed.toList();
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: reversed.length,
      itemBuilder: (context, i) {
        final e = reversed[i];
        if (e.type == 'say') return _sayBubble(e);
        return _eventRow(e);
      },
    );
  }

  Widget _sayBubble(RoomFeedEntry e) {
    final mine = e.mine;
    final who = mine ? (zh ? '你' : 'You') : e.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(who, style: TextStyle(fontSize: 10, color: ink.withValues(alpha: 0.45))),
            ),
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: mine ? accent : Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                e.text,
                style: TextStyle(fontSize: 13, color: mine ? Colors.white : const Color(0xFF3A3A3C)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventRow(RoomFeedEntry e) {
    final who = e.mine ? (zh ? '你' : 'You') : e.user;
    final song = e.songName;
    String text;
    IconData ico = Lucide.Music;
    switch (e.type) {
      case 'track':
        text = zh ? '$who 放了《$song》' : '$who played $song';
        break;
      case 'play':
        ico = Lucide.Play;
        text = zh ? '$who 继续播放${song.isEmpty ? '' : '《$song》'}' : '$who resumed';
        break;
      case 'pause':
        ico = Lucide.Pause;
        text = zh ? '$who 暂停了${song.isEmpty ? '' : '《$song》'}' : '$who paused';
        break;
      case 'heart':
        ico = Lucide.Heart;
        text = zh ? '$who 心动了${song.isEmpty ? '' : ' · $song'}' : '$who ♥ $song';
        break;
      case 'quote':
        ico = Lucide.MessageSquare;
        final ln = e.line.characters.take(30).toString();
        text = zh ? '$who 记下一句：$ln' : '$who saved: $ln';
        break;
      case 'hello':
        ico = Lucide.Sparkles;
        text = e.mine ? (zh ? '你 打开了房间' : 'You opened the room') : (zh ? '$who 来了' : '$who is here');
        break;
      case 'bye':
        ico = Lucide.Users;
        text = zh ? '$who 离开了' : '$who left';
        break;
      default:
        text = '';
    }
    final leading = (e.type == 'track' && e.cover.isNotEmpty)
        ? ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(e.cover, width: 28, height: 28, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _glyph(ico)),
          )
        : _glyph(ico);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: ink.withValues(alpha: 0.72)),
            ),
          ),
          const SizedBox(width: 8),
          Text(_relTime(e.ts), style: TextStyle(fontSize: 10, color: ink.withValues(alpha: 0.35))),
        ],
      ),
    );
  }

  Widget _glyph(IconData ico) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(ico, size: 14, color: accent.withValues(alpha: 0.8)),
    );
  }
}
