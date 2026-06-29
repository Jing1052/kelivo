import 'package:flutter/material.dart';

import '../../theme/app_font_weights.dart';

/// Result of [showBubbleColorPicker].
/// - [reset] true  → caller should clear the custom color (follow theme).
/// - [color] non-null → caller should apply this color.
/// - returning null from the sheet (dismissed) → no change.
class BubbleColorPickResult {
  const BubbleColorPickResult({this.color, this.reset = false});
  final Color? color;
  final bool reset;
}

/// A small, dependency-free HSV color picker as a modal bottom sheet.
/// Three gradient sliders (hue / saturation / value) + a live preview, plus a
/// "follow theme" reset. Opacity is handled separately (shared), so the picked
/// color is always fully opaque here.
Future<BubbleColorPickResult?> showBubbleColorPicker(
  BuildContext context, {
  Color? initial,
  required String title,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<BubbleColorPickResult>(
    context: context,
    backgroundColor: cs.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _BubbleColorPickerSheet(initial: initial, title: title),
  );
}

class _BubbleColorPickerSheet extends StatefulWidget {
  const _BubbleColorPickerSheet({this.initial, required this.title});
  final Color? initial;
  final String title;

  @override
  State<_BubbleColorPickerSheet> createState() =>
      _BubbleColorPickerSheetState();
}

class _BubbleColorPickerSheetState extends State<_BubbleColorPickerSheet> {
  late HSVColor _hsv;

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    final base = widget.initial ?? const Color(0xFFFFB6C1); // soft pink default
    _hsv = HSVColor.fromColor(base).withAlpha(1.0);
  }

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isZh = _isZh;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            // Live preview
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _channel(
              label: isZh ? '色相' : 'Hue',
              value: _hsv.hue,
              max: 360,
              gradient: [
                for (double h = 0; h <= 360; h += 30)
                  HSVColor.fromAHSV(1, h, 1, 1).toColor(),
              ],
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
            ),
            _channel(
              label: isZh ? '饱和度' : 'Saturation',
              value: _hsv.saturation,
              max: 1,
              gradient: [
                HSVColor.fromAHSV(1, _hsv.hue, 0, _hsv.value).toColor(),
                HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor(),
              ],
              onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            ),
            _channel(
              label: isZh ? '明度' : 'Brightness',
              value: _hsv.value,
              max: 1,
              gradient: [
                HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 0).toColor(),
                HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor(),
              ],
              onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const BubbleColorPickResult(reset: true),
                  ),
                  child: Text(isZh ? '恢复默认' : 'Default'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    BubbleColorPickResult(color: _color),
                  ),
                  child: Text(isZh ? '完成' : 'Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _channel({
    required String label,
    required double value,
    required double max,
    required List<Color> gradient,
    required ValueChanged<double> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: AppFontWeights.medium,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          // Gradient track behind a transparent-track slider.
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 0,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 9),
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: value.clamp(0, max),
                  min: 0,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
