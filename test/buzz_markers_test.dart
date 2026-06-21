import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/utils/buzz_markers.dart';

void main() {
  group('stripBuzzMarkers', () {
    test('returns text unchanged when no markers present', () {
      const input = 'hello there, no markers here';
      expect(stripBuzzMarkers(input), input);
    });

    test('removes a single plain marker', () {
      expect(stripBuzzMarkers('come [[buzz]] here'), 'come here');
    });

    test('removes each variant marker', () {
      expect(stripBuzzMarkers('a[[buzz:soft]]b'), 'ab');
      expect(stripBuzzMarkers('a[[buzz:heavy]]b'), 'ab');
      expect(stripBuzzMarkers('a[[buzz:double]]b'), 'ab');
      expect(stripBuzzMarkers('a[[buzz:long]]b'), 'ab');
    });

    test('removes multiple markers in one message', () {
      expect(
        stripBuzzMarkers('feel [[buzz]] this [[buzz:heavy]] too'),
        'feel this too',
      );
    });

    test('tolerates case and inner spaces', () {
      expect(stripBuzzMarkers('x[[BUZZ]]y'), 'xy');
      expect(stripBuzzMarkers('x[[Buzz: Heavy ]]y'), 'xy');
    });

    test('collapses doubled spaces left by inline removal', () {
      expect(stripBuzzMarkers('hold [[buzz]] me'), 'hold me');
    });

    test('preserves newlines and meaningful whitespace', () {
      const input = 'line one\n[[buzz]]\nline two';
      expect(stripBuzzMarkers(input), 'line one\n\nline two');
    });

    test('strips markers around multi-bubble separator', () {
      expect(
        stripBuzzMarkers('first[[buzz]]|||second[[buzz:long]]'),
        'first|||second',
      );
    });
  });

  group('parseBuzzVariants', () {
    test('returns empty list when no markers', () {
      expect(parseBuzzVariants('nothing here'), isEmpty);
    });

    test('plain marker yields empty-string variant', () {
      expect(parseBuzzVariants('[[buzz]]'), <String>['']);
    });

    test('each named variant is captured', () {
      expect(parseBuzzVariants('[[buzz:soft]]'), <String>['soft']);
      expect(parseBuzzVariants('[[buzz:heavy]]'), <String>['heavy']);
      expect(parseBuzzVariants('[[buzz:double]]'), <String>['double']);
      expect(parseBuzzVariants('[[buzz:long]]'), <String>['long']);
    });

    test('preserves order across multiple markers', () {
      expect(
        parseBuzzVariants('[[buzz:heavy]] x [[buzz]] y [[buzz:soft]]'),
        <String>['heavy', '', 'soft'],
      );
    });

    test('is case-insensitive and normalizes to lowercase', () {
      expect(parseBuzzVariants('[[BUZZ:HEAVY]]'), <String>['heavy']);
    });

    test('tolerates spaces inside the variant', () {
      expect(parseBuzzVariants('[[buzz: long ]]'), <String>['long']);
    });
  });
}
