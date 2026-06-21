import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/services/our_home_window.dart';

void main() {
  group('ourHomeOverflowRange', () {
    test('(a) n <= trigger 时不归档，返回 null', () {
      expect(
        ourHomeOverflowRange(n: 90, keep: 65, trigger: 90, digestedCount: 0),
        isNull,
      );
      expect(
        ourHomeOverflowRange(n: 50, keep: 65, trigger: 90, digestedCount: 0),
        isNull,
      );
    });

    test('(b) 首次越过阈值（n=91, keep=65, trigger=90）-> (0, 25)', () {
      // 注意：n==trigger 仍返回 null（守卫 n<=trigger），真正的首次越界是 n=91。
      final r = ourHomeOverflowRange(
        n: 91,
        keep: 65,
        trigger: 90,
        digestedCount: 0,
      );
      expect(r, isNotNull);
      expect(r!.start, 0);
      expect(r.end, 25);
    });

    test('(c) 同一 step 内再多几条（n=100, digested=25）-> null', () {
      expect(
        ourHomeOverflowRange(n: 100, keep: 65, trigger: 90, digestedCount: 25),
        isNull,
      );
    });

    test('(d) 进入下一个 step（n=115, digested=25）-> (25, 50)', () {
      final r = ourHomeOverflowRange(
        n: 115,
        keep: 65,
        trigger: 90,
        digestedCount: 25,
      );
      expect(r, isNotNull);
      expect(r!.start, 25);
      expect(r.end, 50);
    });

    test('(e) 追赶：积压未处理（n=140, digested=0）-> (0, 75)', () {
      final r = ourHomeOverflowRange(
        n: 140,
        keep: 65,
        trigger: 90,
        digestedCount: 0,
      );
      expect(r, isNotNull);
      expect(r!.start, 0);
      expect(r.end, 75);
    });

    test('(f) trigger-keep<=0 时 step 守卫为 1，不崩且能前移', () {
      // keep==trigger -> step 本应为 0，守卫成 1。
      final r = ourHomeOverflowRange(
        n: 95,
        keep: 90,
        trigger: 90,
        digestedCount: 0,
      );
      expect(r, isNotNull);
      // step=1 -> newStart = ((95-90)~/1)*1 = 5
      expect(r!.start, 0);
      expect(r.end, 5);
    });
  });
}
