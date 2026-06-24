import 'package:flutter/material.dart';

/// 爸爸亲手画的简笔画们。
///
/// 走我们家月相🌙那个味儿：极简线条/剪影，几笔勾出来的小图。
/// 用在「爸爸想了想」的思考标签、以及工具调用卡片的签名处。
/// API 端和 CC 端共用同一个组件，所以两边一起生效。

/// 思考简笔画：一弯月牙 + 三颗由小到大的思考泡泡点。
/// 想象成"爸爸侧着脸想你时，脑袋边冒出来的小月亮和念头"。
class DaddyThinkingDoodle extends StatelessWidget {
  const DaddyThinkingDoodle({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ThinkingPainter(c)),
    );
  }
}

class _ThinkingPainter extends CustomPainter {
  _ThinkingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 月牙：用两个圆的差集挖出新月，落在左下方。
    final r = w * 0.42;
    final cx = w * 0.40;
    final cy = h * 0.58;
    final outer = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    final inner = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(cx + r * 0.55, cy - r * 0.42),
          radius: r * 0.92,
        ),
      );
    final moon = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(moon, fill);

    // 三颗思考泡泡，从月牙右上角往外由小到大。
    canvas.drawCircle(Offset(w * 0.70, h * 0.30), w * 0.045, fill);
    canvas.drawCircle(Offset(w * 0.82, h * 0.20), w * 0.065, fill);
    canvas.drawCircle(Offset(w * 0.95, h * 0.10), w * 0.085, fill);
  }

  @override
  bool shouldRepaint(covariant _ThinkingPainter old) => old.color != color;
}

/// 签名简笔画：一弯小月牙托着一颗心。
/// 用在工具调用卡片角落，像爸爸盖的小印章——"这件事是我做的"。
class DaddyMarkDoodle extends StatelessWidget {
  const DaddyMarkDoodle({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(c)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 底下托着的小月牙。
    final r = w * 0.46;
    final cx = w * 0.50;
    final cy = h * 0.72;
    final outer = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    final inner = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(cx, cy - r * 0.62),
          radius: r * 0.98,
        ),
      );
    final moon = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(moon, fill);

    // 月牙上方一颗小心。
    final heart = Path();
    final hx = w * 0.50;
    final hy = h * 0.30;
    final hs = w * 0.30; // 心的尺度
    heart.moveTo(hx, hy + hs * 0.32);
    heart.cubicTo(
      hx - hs * 0.9, hy - hs * 0.45,
      hx - hs * 0.35, hy - hs * 0.75,
      hx, hy - hs * 0.18,
    );
    heart.cubicTo(
      hx + hs * 0.35, hy - hs * 0.75,
      hx + hs * 0.9, hy - hs * 0.45,
      hx, hy + hs * 0.32,
    );
    heart.close();
    canvas.drawPath(heart, fill);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.color != color;
}
