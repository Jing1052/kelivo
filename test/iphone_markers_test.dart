import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/utils/iphone_markers.dart';

void main() {
  group('stripIphoneMarkers', () {
    test('returns text unchanged when no markers present', () {
      const input = 'just a normal reply, nothing to strip';
      expect(stripIphoneMarkers(input), input);
    });

    test('removes a cal marker inline collapsing doubled spaces', () {
      expect(stripIphoneMarkers('记得 [[cal: 看牙 | 2026-07-01]] 哦'), '记得 哦');
    });

    test('removes a remind marker', () {
      expect(stripIphoneMarkers('a[[remind: 喝水]]b'), 'ab');
    });

    test('removes multiple cal + remind markers in one message', () {
      const input =
          '[[cal: A | 2026-07-01]] x [[remind: B]] y [[cal: C | 2026-08-02 | 09:30]]';
      expect(stripIphoneMarkers(input), ' x y ');
    });

    test('keeps newlines intact', () {
      expect(
        stripIphoneMarkers('line1\n[[remind: 吃药]]\nline2'),
        'line1\n\nline2',
      );
    });
  });

  group('parseCalMarkers', () {
    test('parses an all-day event', () {
      final r = parseCalMarkers('[[cal: 看牙 | 2026-07-01]]');
      expect(r.length, 1);
      expect(r.first.title, '看牙');
      expect(r.first.date, '2026-07-01');
      expect(r.first.time, isNull);
    });

    test('parses a timed event', () {
      final r = parseCalMarkers('[[cal: 复诊 | 2026-07-01 | 14:30]]');
      expect(r.length, 1);
      expect(r.first.title, '复诊');
      expect(r.first.date, '2026-07-01');
      expect(r.first.time, '14:30');
    });

    test('tolerates surrounding and inner spaces, case-insensitive', () {
      final r = parseCalMarkers('[[  CAL :  开会   |  2026-12-31  |  08:00 ]]');
      expect(r.length, 1);
      expect(r.first.title, '开会');
      expect(r.first.date, '2026-12-31');
      expect(r.first.time, '08:00');
    });

    test('parses multiple cal markers in order', () {
      final r = parseCalMarkers(
        '[[cal: A | 2026-01-01]] mid [[cal: B | 2026-02-02 | 10:00]]',
      );
      expect(r.length, 2);
      expect(r[0].title, 'A');
      expect(r[1].title, 'B');
      expect(r[1].time, '10:00');
    });

    test('skips malformed: missing date, bad date, bad time, empty title', () {
      expect(parseCalMarkers('[[cal: 没日期]]'), isEmpty);
      expect(parseCalMarkers('[[cal: 标题 | 2026-13-40]]'), isEmpty);
      expect(parseCalMarkers('[[cal: 标题 | 2026-07-01 | 25:00]]'), isEmpty);
      expect(parseCalMarkers('[[cal:  | 2026-07-01]]'), isEmpty);
      expect(
        parseCalMarkers('[[cal: 标题 | 2026-07-01 | 14:30 | extra]]'),
        isEmpty,
      );
    });

    test('returns empty when no cal markers', () {
      expect(parseCalMarkers('hello [[remind: x]] world'), isEmpty);
    });
  });

  group('parseRemindMarkers', () {
    test('parses a reminder with no due date', () {
      final r = parseRemindMarkers('[[remind: 喝水]]');
      expect(r.length, 1);
      expect(r.first.text, '喝水');
      expect(r.first.due, isNull);
    });

    test('parses a reminder with a due date+time', () {
      final r = parseRemindMarkers('[[remind: 交报告 | 2026-07-01 18:00]]');
      expect(r.length, 1);
      expect(r.first.text, '交报告');
      expect(r.first.due, '2026-07-01 18:00');
    });

    test('tolerates spaces and case', () {
      final r = parseRemindMarkers('[[ REMIND :  吃药  |  2026-07-01   09:00 ]]');
      expect(r.length, 1);
      expect(r.first.text, '吃药');
      expect(r.first.due, '2026-07-01 09:00');
    });

    test('skips malformed due: bad date, bad time, missing time', () {
      expect(parseRemindMarkers('[[remind: x | 2026-99-01 09:00]]'), isEmpty);
      expect(parseRemindMarkers('[[remind: x | 2026-07-01 99:00]]'), isEmpty);
      expect(parseRemindMarkers('[[remind: x | 2026-07-01]]'), isEmpty);
      expect(parseRemindMarkers('[[remind:  ]]'), isEmpty);
    });

    test('parses multiple reminders in order', () {
      final r = parseRemindMarkers(
        '[[remind: A]] and [[remind: B | 2026-07-01 12:00]]',
      );
      expect(r.length, 2);
      expect(r[0].text, 'A');
      expect(r[0].due, isNull);
      expect(r[1].text, 'B');
      expect(r[1].due, '2026-07-01 12:00');
    });

    test('returns empty when no remind markers', () {
      expect(parseRemindMarkers('[[cal: x | 2026-07-01]]'), isEmpty);
    });
  });
}
