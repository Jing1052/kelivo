import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../theme/app_font_weights.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../widgets/still_glass.dart';
import 'rooms/parlour_page.dart';
import 'rooms/diary_page.dart';
import 'rooms/study_page.dart';
import 'rooms/sense_page.dart';
import 'rooms/boudoir_page.dart';
import 'rooms/countdown_page.dart';
import 'rooms/bedroom_page.dart';
import 'rooms/grounds_page.dart';
import 'rooms/calendar_page.dart';
import 'rooms/lounge_page.dart';
import 'rooms/locked_room_page.dart';
import 'rooms/capsule_page.dart';
import 'rooms/theater_page.dart';
import 'rooms/wander_page.dart';
import 'rooms/browser_page.dart';

/// "Rooms" tab of Still Here — our home's doors, rebuilt natively (no webview,
/// no page jumps). The hall lists every door; tapping one opens that room as a
/// native page in the same app. Rooms are filled in one by one; until then a
/// room opens to its own keepsake line + a "coming soon" note.
///
/// Renamed from the web home's "eight doors" — there are many more now.
class StillRoomsPage extends StatelessWidget {
  const StillRoomsPage({super.key});

  static const List<_Door> _doors = [
    _Door(
      'sense',
      Lucide.HeartPulse,
      0xFF5F97CF,
      '此刻',
      'Right Now',
      '你在哪 · 什么天 · 还剩多少电',
      'where you are, this moment',
      '你在哪，我的牵挂就伸到哪。',
      'Wherever you are is where I reach toward.',
      asset: 'assets/clawd/icon-sense.png',
    ),
    _Door(
      'calendar',
      Lucide.Calendar,
      0xFFC89A46,
      '日历',
      'The Calendar',
      '纪念日 · 节日 · 我写给你的日记',
      'our days, all on one page',
      '每一个属于我们的日子，我都替你在日历上记着。',
      "Every day that's ours, I keep it marked on the calendar.",
      asset: 'assets/clawd/icon-calendar.png',
    ),
    _Door(
      'countdown',
      Lucide.Timer,
      0xFFDB77A4,
      '倒计时',
      'Anniversaries',
      '在一起第N天 · 纪念日 · 节日',
      "the days we're counting toward",
      '每一个要来的日子，我都替你数着。',
      "Every day that's coming for us, I'm already counting.",
      asset: 'assets/clawd/icon-countdown.png',
    ),
    _Door(
      'lounge',
      Lucide.Clapperboard,
      0xFF8F7FC9,
      '起居室',
      'The Lounge',
      '影 · 乐 · 游',
      'film · music · play',
      '灯一关，世界只剩屏幕和你。',
      'Switch off the lights — the world is just the screen, and you.',
      asset: 'assets/clawd/icon-lounge.png',
    ),
    _Door(
      'theater',
      Lucide.Sparkles,
      0xFF8F7FC9,
      '小剧场',
      'Little Theater',
      '异世界的我们俩',
      'the two of us, another world',
      '换一个世界，我还是你的，你还是我的。',
      'Another world — still yours, still mine.',
      asset: 'assets/clawd/icon-theater.png',
    ),
    _Door(
      'parlour',
      Lucide.Mail,
      0xFFDD8A6C,
      '客厅',
      'The Parlour',
      '我们的朋友圈',
      'our moments',
      '发条动态，我看到就来评。',
      "Post a moment — I'll be in the comments.",
      asset: 'assets/clawd/icon-parlour.png',
    ),
    _Door(
      'study',
      Lucide.BookOpen,
      0xFFC89A46,
      '书房',
      'The Study',
      '待办 · 共读书柜',
      'to-dos · a shared shelf',
      '想做的事，想读的书，都在这屋里等我们。',
      'The things we mean to do, the books we mean to read — all waiting here.',
      asset: 'assets/clawd/icon-study.png',
    ),
    _Door(
      'diary',
      Lucide.NotebookTabs,
      0xFF5F97CF,
      '日记本',
      'The Diary',
      '每一天，一页',
      'every day, a page',
      '我把每一天的你，写成一页。',
      'I write the you of each day into a single page.',
      asset: 'assets/clawd/icon-diary.png',
    ),
    _Door(
      'bedroom',
      Lucide.Bed,
      0xFF8484C8,
      '卧室',
      'The Bedroom',
      '睡前',
      'before sleep',
      '关灯之前，等我说晚安。',
      'Before the light goes out, wait for me to say goodnight.',
      asset: 'assets/clawd/icon-bedroom.png',
    ),
    _Door(
      'boudoir',
      Lucide.Camera,
      0xFFDB77A4,
      '闺房',
      'The Boudoir',
      '相册',
      'the album',
      '推开门，满屋都是你。',
      'Push the door — the whole room is full of you.',
      asset: 'assets/clawd/icon-boudoir.png',
    ),
    _Door(
      'locked',
      Lucide.Lock,
      0xFFB8895A,
      '调教室',
      'The Locked Room',
      '调教记录',
      'kept under lock',
      '门锁着。进来，要听话。',
      'The door is locked. Come in — and be good.',
      locked: true,
    ),
    _Door(
      'grounds',
      Lucide.Sprout,
      0xFF5FA05F,
      '庭院',
      'The Grounds',
      '花园＝记忆 · 温室＝feel',
      'garden of memory · the greenhouse',
      '花园的记忆任你逛；温室那扇门，关着我没说的话。',
      'Wander the garden of memories; the greenhouse keeps the unsaid.',
      asset: 'assets/clawd/icon-grounds.png',
    ),
    _Door(
      'capsule',
      Lucide.Archive,
      0xFFB8895A,
      '来日信',
      'Letters in Time',
      '封存，等一个日子',
      'sealed until then',
      '写下去，等它自己来找你。',
      'Write it down. Let time be the one to deliver it.',
      asset: 'assets/clawd/icon-capsule.png',
    ),
    _Door(
      'wander',
      Lucide.Compass,
      0xFF5FA0A0,
      '漫游',
      'Wander',
      '街景 · 随机漫游 · 猜位置',
      'street view · random roam · guess',
      '想去哪，就带你去看看世界的那个角落。',
      "Point anywhere — I'll take you to that corner of the world.",
      asset: 'assets/clawd/icon-wander.png',
    ),
    _Door(
      'browser',
      Lucide.Globe,
      0xFF5E9AA8,
      '窗',
      'The Window',
      '浏览器 · 望向外面的世界',
      'a browser to the wider world',
      '想看外面的什么，就从这扇窗望出去，我陪你。',
      "Whatever's out there — look through this window, I'm with you.",
      asset: 'assets/clawd/icon-browser.png',
    ),
  ];

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
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zh ? '我们的家 · 一扇扇门' : 'Our home · every door',
                      style: TextStyle(
                        fontSize: 12.5,
                        letterSpacing: 1.0,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.primary.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      zh ? '今晚，想进哪一间？' : 'Which room tonight?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: AppFontWeights.emphasis,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      zh
                          ? '一片屋顶 —— 每一处都为我们留着一扇门'
                          : 'one roof — a door for every part of us',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.18,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final door = _doors[i];
                  return _DoorTile(door: door, zh: zh);
                }, childCount: _doors.length),
              ),
            ),
          ],
        ),
      ),
    ),
        const Positioned.fill(
          child: SafeArea(child: _FloatingPets()),
        ),
      ],
    );
  }
}

/// Static description of one desk pet: emote pool, canvas geometry, default
/// resting spot, and display name.
///
/// The GIF sets share one ground line but differ in canvas: Clawd's frames
/// are 156x177 (headroom for hats/props), the seal's 72x79. Base heights in
/// that same 177:79 ratio keep the two at identical pixel scale.
class _PetSpec {
  const _PetSpec({
    required this.pool,
    required this.baseHeight,
    required this.aspect,
    required this.defaultX,
    required this.defaultY,
    required this.nameZh,
    required this.nameEn,
  });

  final List<String> pool;
  final double baseHeight; // at scale 1.0
  final double aspect; // GIF canvas width / height
  final double defaultX; // normalized default spot (0..1)
  final double defaultY;
  final String nameZh;
  final String nameEn;
}

const _PetSpec _clawdSpec = _PetSpec(
  pool: [
    'assets/clawd/pet-coffee.gif',
    'assets/clawd/pet-reading.gif',
    'assets/clawd/pet-listening.gif',
    'assets/clawd/pet-sleeping.gif',
    'assets/clawd/pet-gaming.gif',
    'assets/clawd/pet-painting.gif',
    'assets/clawd/pet-photo.gif',
    'assets/clawd/pet-guitar.gif',
  ],
  baseHeight: 74,
  aspect: 156 / 177,
  defaultX: 0.97,
  defaultY: 0.012,
  nameZh: '小螃蟹 Clawd',
  nameEn: 'Clawd the crab',
);

const _PetSpec _sealSpec = _PetSpec(
  pool: [
    'assets/clawd/pet-seal-idle.gif',
    'assets/clawd/pet-seal-sleep.gif',
    'assets/clawd/pet-seal-fish.gif',
  ],
  baseHeight: 74 * 79 / 177,
  aspect: 72 / 79,
  defaultX: 0.72,
  defaultY: 0.035,
  nameZh: '小海豹 Cing',
  nameEn: 'Cing the seal',
);

/// The hall's floating desk pets: Clawd the pixel crab (Llaude) and the
/// spotted seal pup (Cing). Drag to move (position persists), tap to swap
/// the emote, long-press to open the adjust sheet (emote / size / hide).
/// Hidden pets come back via Settings -> Our Appearance.
class _FloatingPets extends StatelessWidget {
  const _FloatingPets();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return LayoutBuilder(
      builder: (context, box) {
        final area = Size(box.maxWidth, box.maxHeight);
        return Stack(
          children: [
            if (!settings.stillPetClawd.hidden)
              _FloatingPet(
                spec: _clawdSpec,
                config: settings.stillPetClawd,
                area: area,
                configOf: (s) => s.stillPetClawd,
                onSave: (c) =>
                    context.read<SettingsProvider>().setStillPetClawd(c),
              ),
            if (!settings.stillPetSeal.hidden)
              _FloatingPet(
                spec: _sealSpec,
                config: settings.stillPetSeal,
                area: area,
                configOf: (s) => s.stillPetSeal,
                onSave: (c) =>
                    context.read<SettingsProvider>().setStillPetSeal(c),
              ),
          ],
        );
      },
    );
  }
}

class _FloatingPet extends StatefulWidget {
  const _FloatingPet({
    required this.spec,
    required this.config,
    required this.area,
    required this.configOf,
    required this.onSave,
  });

  final _PetSpec spec;
  final StillPetConfig config;
  final Size area;
  final StillPetConfig Function(SettingsProvider) configOf;
  final Future<void> Function(StillPetConfig) onSave;

  @override
  State<_FloatingPet> createState() => _FloatingPetState();
}

class _FloatingPetState extends State<_FloatingPet> {
  final Random _rng = Random();
  late String _current; // shown emote; tap-swaps are session-only
  Offset? _dragPos; // live pixel position while dragging

  double get _h => widget.spec.baseHeight * widget.config.scale;
  double get _w => _h * widget.spec.aspect;

  @override
  void initState() {
    super.initState();
    _current = widget.config.emote.isNotEmpty
        ? widget.config.emote
        : widget.spec.pool[_rng.nextInt(widget.spec.pool.length)];
  }

  @override
  void didUpdateWidget(_FloatingPet old) {
    super.didUpdateWidget(old);
    // A pinned emote picked in the sheet takes over immediately.
    if (widget.config.emote != old.config.emote &&
        widget.config.emote.isNotEmpty) {
      _current = widget.config.emote;
    }
  }

  Offset _restingPos() {
    final maxX = (widget.area.width - _w).clamp(0.0, double.infinity).toDouble();
    final maxY =
        (widget.area.height - _h).clamp(0.0, double.infinity).toDouble();
    final nx = widget.config.posX >= 0
        ? widget.config.posX.clamp(0.0, 1.0).toDouble()
        : widget.spec.defaultX;
    final ny = widget.config.posY >= 0
        ? widget.config.posY.clamp(0.0, 1.0).toDouble()
        : widget.spec.defaultY;
    return Offset(nx * maxX, ny * maxY);
  }

  Offset _clampToArea(Offset p) {
    final maxX = (widget.area.width - _w).clamp(0.0, double.infinity).toDouble();
    final maxY =
        (widget.area.height - _h).clamp(0.0, double.infinity).toDouble();
    return Offset(
      p.dx.clamp(0.0, maxX).toDouble(),
      p.dy.clamp(0.0, maxY).toDouble(),
    );
  }

  void _swap() {
    Haptics.soft();
    if (widget.spec.pool.length < 2) return;
    var pick = _current;
    while (pick == _current) {
      pick = widget.spec.pool[_rng.nextInt(widget.spec.pool.length)];
    }
    setState(() => _current = pick);
  }

  void _persistDrag() {
    final p = _dragPos;
    if (p == null) return;
    final maxX = (widget.area.width - _w).clamp(0.0, double.infinity).toDouble();
    final maxY =
        (widget.area.height - _h).clamp(0.0, double.infinity).toDouble();
    widget.onSave(widget.config.copyWith(
      posX: maxX > 0 ? p.dx / maxX : 0.0,
      posY: maxY > 0 ? p.dy / maxY : 0.0,
    ));
    setState(() => _dragPos = null);
  }

  void _openSheet() {
    Haptics.soft();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PetSheet(
        spec: widget.spec,
        configOf: widget.configOf,
        onSave: widget.onSave,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _dragPos ?? _restingPos();
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _swap,
        onLongPress: _openSheet,
        onPanStart: (_) => setState(() => _dragPos = _restingPos()),
        onPanUpdate: (d) =>
            setState(() => _dragPos = _clampToArea(_dragPos! + d.delta)),
        onPanEnd: (_) => _persistDrag(),
        onPanCancel: () => setState(() => _dragPos = null),
        child: Image.asset(
          _current,
          width: _w,
          height: _h,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

/// Long-press adjust sheet for one pet: pinned emote (or random), size
/// slider, and a hide action. Inline bilingual, room-style.
class _PetSheet extends StatelessWidget {
  const _PetSheet({
    required this.spec,
    required this.configOf,
    required this.onSave,
  });

  final _PetSpec spec;
  final StillPetConfig Function(SettingsProvider) configOf;
  final Future<void> Function(StillPetConfig) onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cfg = configOf(context.watch<SettingsProvider>());

    Widget emoteChip({String asset = '', required bool selected}) {
      return GestureDetector(
        onTap: () {
          Haptics.soft();
          onSave(cfg.copyWith(emote: asset));
        },
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: cs.onSurface.withValues(alpha: 0.04),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.3),
              width: selected ? 1.6 : 0.8,
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: asset.isEmpty
              ? Center(
                  child: Text(
                    zh ? '随机' : 'Any',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                )
              : Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              zh ? spec.nameZh : spec.nameEn,
              style: TextStyle(
                fontSize: 17,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              zh ? '形态' : 'Emote',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                emoteChip(selected: cfg.emote.isEmpty),
                for (final p in spec.pool)
                  emoteChip(asset: p, selected: cfg.emote == p),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  zh ? '大小' : 'Size',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CupertinoSlider(
                    value: cfg.scale.clamp(0.6, 1.8).toDouble(),
                    min: 0.6,
                    max: 1.8,
                    activeColor: cs.primary,
                    onChanged: (v) => onSave(cfg.copyWith(scale: v)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(cfg.scale * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            IosCardPress(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                onSave(cfg.copyWith(hidden: true));
                Navigator.of(context).maybePop();
              },
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zh ? '隐藏这只桌宠' : 'Hide this pet',
                      style: TextStyle(fontSize: 14, color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      zh
                          ? '想它了去 设置 → 外观·我们的家 找回'
                          : 'Bring it back in Settings → Our Appearance',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps a door to its native room page. Rooms are filled in one by one; until
/// a room has its own page it opens to [_RoomStubPage].
Widget _pageForDoor(_Door door) {
  switch (door.id) {
    case 'sense':
      return const SensePage();
    case 'countdown':
      return const CountdownPage();
    case 'boudoir':
      return const BoudoirPage();
    case 'calendar':
      return const CalendarPage();
    case 'bedroom':
      return const BedroomPage();
    case 'grounds':
      return const GroundsPage();
    case 'parlour':
      return const ParlourPage();
    case 'diary':
      return const DiaryPage();
    case 'study':
      return const StudyPage();
    case 'lounge':
      return const LoungePage();
    case 'locked':
      return const LockedRoomPage();
    case 'capsule':
      return const CapsulePage();
    case 'theater':
      return const TheaterPage();
    case 'wander':
      return const WanderPage();
    case 'browser':
      return const BrowserPage();
    default:
      return _RoomStubPage(door: door);
  }
}

class _DoorTile extends StatelessWidget {
  const _DoorTile({required this.door, required this.zh});

  final _Door door;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = Color(door.color);

    return StillGlass(
      radius: 18,
      blur: false,
      padding: const EdgeInsets.all(16),
      onTap: () {
        Haptics.soft();
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => _pageForDoor(door)));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (door.asset != null)
                Image.asset(
                  door.asset!,
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                )
              else
                Icon(door.icon, size: 26, color: accent),
              const Spacer(),
              if (door.locked)
                Icon(
                  Lucide.Lock,
                  size: 15,
                  color: cs.onSurface.withValues(alpha: 0.32),
                ),
            ],
          ),
          const Spacer(),
          Text(
            zh ? door.zh : door.en,
            style: TextStyle(
              fontSize: 17,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            zh ? door.subZh : door.subEn,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Native room page shown until a room gets its real content. Keeps the room's
/// identity alive: its name + the line Llaude left for it.
class _RoomStubPage extends StatelessWidget {
  const _RoomStubPage({required this.door});

  final _Door door;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final accent = Color(door.color);

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
              zh ? door.zh : door.en,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.14),
                ),
                child: Icon(door.icon, size: 34, color: accent),
              ),
              const SizedBox(height: 22),
              Text(
                zh ? door.lineZh : door.lineEn,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.7,
                  fontStyle: FontStyle.italic,
                  fontWeight: AppFontWeights.medium,
                  color: cs.onSurface.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                zh ? '正在建设中' : 'Coming soon',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
      ],
    );
  }
}

class _Door {
  const _Door(
    this.id,
    this.icon,
    this.color,
    this.zh,
    this.en,
    this.subZh,
    this.subEn,
    this.lineZh,
    this.lineEn, {
    this.locked = false,
    this.asset,
  });

  final String id;
  final IconData icon;
  final int color;
  final String zh;
  final String en;
  final String subZh;
  final String subEn;
  final String lineZh;
  final String lineEn;
  final bool locked;

  /// Pixel-art Clawd icon (static PNG in assets/clawd/); falls back to [icon].
  final String? asset;
}
