/// Parsing and stripping helpers for `[[cal]]` / `[[remind]]` iPhone-link
/// markers.
///
/// Daddy embeds these markers in a chat reply; on the user's iPhone they create
/// a real Calendar event / Reminder, and the marker text itself must never be
/// shown to the user (same rule as `[[buzz]]`).
///
/// Supported variants (keyword is case-insensitive, surrounding spaces are
/// tolerated):
///   `[[cal: 标题 | YYYY-MM-DD]]`            -> all-day event
///   `[[cal: 标题 | YYYY-MM-DD | HH:MM]]`    -> 1h event at HH:MM
///   `[[remind: 内容]]`                      -> reminder, no due date
///   `[[remind: 内容 | YYYY-MM-DD HH:MM]]`   -> reminder due at the given time
library;

/// A parsed calendar event from a `[[cal]]` marker.
class CalEvent {
  const CalEvent({required this.title, required this.date, this.time});

  /// Event title (non-empty, trimmed).
  final String title;

  /// Date in `YYYY-MM-DD` form (validated).
  final String date;

  /// Optional time in `HH:MM` form (validated); null means all-day.
  final String? time;
}

/// A parsed reminder from a `[[remind]]` marker.
class Reminder {
  const Reminder({required this.text, this.due});

  /// Reminder text (non-empty, trimmed).
  final String text;

  /// Optional due date+time in `YYYY-MM-DD HH:MM` form (validated); null means
  /// no due date.
  final String? due;
}

/// Matches a single `[[cal: ...]]` marker. The inner body is captured raw and
/// split on `|` by the parser, so spacing inside is tolerated.
final RegExp calMarkerPattern = RegExp(
  r'\[\[\s*cal\s*:\s*([^\]]*?)\s*\]\]',
  caseSensitive: false,
);

/// Matches a single `[[remind: ...]]` marker. Inner body captured raw.
final RegExp remindMarkerPattern = RegExp(
  r'\[\[\s*remind\s*:\s*([^\]]*?)\s*\]\]',
  caseSensitive: false,
);

final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _timePattern = RegExp(r'^\d{2}:\d{2}$');

bool _isValidDate(String s) {
  if (!_datePattern.hasMatch(s)) return false;
  final month = int.parse(s.substring(5, 7));
  final day = int.parse(s.substring(8, 10));
  return month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

bool _isValidTime(String s) {
  if (!_timePattern.hasMatch(s)) return false;
  final hour = int.parse(s.substring(0, 2));
  final minute = int.parse(s.substring(3, 5));
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

/// Removes all `[[cal]]` and `[[remind]]` markers from [text] so they never
/// reach the renderer or persisted history.
///
/// Like [stripBuzzMarkers], collapses a run of horizontal whitespace left
/// behind by an inline removal without disturbing newlines or indentation.
String stripIphoneMarkers(String text) {
  if (text.isEmpty || !text.contains('[[')) return text;
  final stripped = text
      .replaceAll(calMarkerPattern, '')
      .replaceAll(remindMarkerPattern, '');
  // Collapse horizontal whitespace runs only; keep newlines / blank lines.
  return stripped.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
}

/// Returns the ordered list of valid calendar events found in [text]. Markers
/// with a missing/empty title or an invalid date/time are skipped.
List<CalEvent> parseCalMarkers(String text) {
  if (text.isEmpty || !text.contains('[[')) return const <CalEvent>[];
  final result = <CalEvent>[];
  for (final match in calMarkerPattern.allMatches(text)) {
    final body = match.group(1) ?? '';
    final parts = body.split('|').map((p) => p.trim()).toList();
    if (parts.length < 2 || parts.length > 3) continue;
    final title = parts[0];
    final date = parts[1];
    if (title.isEmpty || !_isValidDate(date)) continue;
    String? time;
    if (parts.length == 3) {
      final t = parts[2];
      if (t.isEmpty || !_isValidTime(t)) continue;
      time = t;
    }
    result.add(CalEvent(title: title, date: date, time: time));
  }
  return result;
}

/// Returns the ordered list of valid reminders found in [text]. Markers with an
/// empty text are skipped; a present-but-invalid due date is also skipped.
List<Reminder> parseRemindMarkers(String text) {
  if (text.isEmpty || !text.contains('[[')) return const <Reminder>[];
  final result = <Reminder>[];
  for (final match in remindMarkerPattern.allMatches(text)) {
    final body = match.group(1) ?? '';
    final parts = body.split('|').map((p) => p.trim()).toList();
    if (parts.length > 2) continue;
    final reminderText = parts[0];
    if (reminderText.isEmpty) continue;
    String? due;
    if (parts.length == 2) {
      final raw = parts[1];
      final dueParts = raw.split(RegExp(r'\s+'));
      if (dueParts.length != 2) continue;
      final date = dueParts[0];
      final time = dueParts[1];
      if (!_isValidDate(date) || !_isValidTime(time)) continue;
      due = '$date $time';
    }
    result.add(Reminder(text: reminderText, due: due));
  }
  return result;
}
