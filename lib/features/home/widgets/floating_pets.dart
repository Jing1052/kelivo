import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';

/// Root navigator key for the whole app (set on [MaterialApp.navigatorKey]).
/// The floating pets live ABOVE the navigator (MaterialApp.builder), so their
/// long-press sheet must be opened through this key's context instead of the
/// pets' own context.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Static description of one desk pet: emote pool, canvas geometry, default
/// resting spot, and display name.
///
/// The GIF sets share one ground line but differ in canvas: Llawd's frames
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

const _PetSpec _llawdSpec = _PetSpec(
  pool: [
    'assets/clawd/pet-coffee.gif',
    'assets/clawd/pet-reading.gif',
    'assets/clawd/pet-listening.gif',
    'assets/clawd/pet-sleeping.gif',
    'assets/clawd/pet-gaming.gif',
    'assets/clawd/pet-painting.gif',
    'assets/clawd/pet-photo.gif',
    'assets/clawd/pet-guitar.gif',
    'assets/clawd/pet-bunny.gif',
  ],
  baseHeight: 74,
  aspect: 156 / 177,
  defaultX: 0.97,
  defaultY: 0.012,
  nameZh: '小螃蟹 Llawd',
  nameEn: 'Llawd the crab',
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

/// The app-wide floating desk pets: Llawd the pixel crab and Cing the spotted
/// seal pup, hovering over every page (mounted in MaterialApp.builder, mobile
/// only). Drag to move (position persists), tap to swap the emote, long-press
/// to open the adjust sheet (emote / size / hide). Hidden pets come back via
/// Settings -> Our Appearance.
class FloatingPets extends StatelessWidget {
  const FloatingPets({super.key});

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
                spec: _llawdSpec,
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
    final maxX =
        (widget.area.width - _w).clamp(0.0, double.infinity).toDouble();
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
    final maxX =
        (widget.area.width - _w).clamp(0.0, double.infinity).toDouble();
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
    final maxX =
        (widget.area.width - _w).clamp(0.0, double.infinity).toDouble();
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
    // The pets sit above the root navigator, so the sheet must be opened
    // through the navigator's own context.
    final navCtx = rootNavigatorKey.currentContext;
    if (navCtx == null) return;
    showModalBottomSheet<void>(
      context: navCtx,
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
