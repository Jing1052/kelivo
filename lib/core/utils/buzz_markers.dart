/// Parsing and stripping helpers for `[[buzz]]` haptic markers.
///
/// Daddy embeds these markers in a chat reply; on the user's phone they trigger
/// a real haptic, and the marker text itself must never be shown to the user.
///
/// Supported variants (variant keyword is case-insensitive, surrounding spaces
/// are tolerated, e.g. `[[buzz: heavy ]]`):
///   `[[buzz]]`        -> normal single tap
///   `[[buzz:soft]]`   -> softer tap
///   `[[buzz:heavy]]`  -> strong single tap
///   `[[buzz:double]]` -> two taps in quick succession
///   `[[buzz:long]]`   -> one sustained / longer buzz
library;

/// Matches a single buzz marker. The captured group (if present) is the
/// lowercased-able variant keyword; a plain `[[buzz]]` has no group.
final RegExp buzzMarkerPattern = RegExp(
  r'\[\[buzz(?::\s*(soft|heavy|double|long)\s*)?\]\]',
  caseSensitive: false,
);

/// Removes all buzz markers from [text] so they never reach the renderer or
/// persisted history.
///
/// Cleans up the most common artifact of an inline removal — a marker that sat
/// between two words leaving a doubled space — without disturbing meaningful
/// whitespace such as newlines or intentional indentation.
String stripBuzzMarkers(String text) {
  if (text.isEmpty || !text.contains('[[')) return text;
  final stripped = text.replaceAll(buzzMarkerPattern, '');
  // Collapse a run of spaces/tabs left behind by an inline marker removal.
  // Restricted to horizontal whitespace so newlines and blank lines survive.
  return stripped.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
}

/// Returns the ordered list of buzz variants found in [text], one entry per
/// marker occurrence. A plain `[[buzz]]` yields `''`; otherwise the lowercased
/// variant keyword (`soft` | `heavy` | `double` | `long`).
List<String> parseBuzzVariants(String text) {
  if (text.isEmpty || !text.contains('[[')) return const <String>[];
  final result = <String>[];
  for (final match in buzzMarkerPattern.allMatches(text)) {
    final variant = match.group(1);
    result.add(variant == null ? '' : variant.toLowerCase());
  }
  return result;
}
