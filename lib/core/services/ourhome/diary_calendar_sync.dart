import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../iphone_link_service.dart';
import 'ourhome_gateway.dart';

/// Backfills Llaude's diary pages into the iPhone Calendar as all-day events.
///
/// Diary writing (memory-vault `hold`) and calendar insertion (`[[cal]]` chat
/// markers) are two separate channels — they only ever coincided when daddy
/// happened to emit a `[[cal]]` while writing a diary. This pulls the diary
/// feed itself into the calendar so every page lands on its date, and quietly
/// fills in any history that was written before the link existed.
///
/// All work is gated, deduplicated, and best-effort: it only runs on iOS when
/// the iPhone link is on and Calendar access is granted, never writes the same
/// diary twice (a SharedPreferences id set), and swallows every failure so it
/// can never disturb the chat flow.
class DiaryCalendarSync {
  DiaryCalendarSync._();

  static const String _syncedIdsKey = 'diary_calendar_synced_ids_v1';
  // One-time migration: build 80 backfilled title-only events (no notes). This
  // wipes that batch (by the 📔 title prefix) once, so the next pass re-creates
  // them WITH the diary body in notes — no duplicates.
  static const String _notesMigrationKey = 'diary_calendar_notes_migrated_v1';
  // Diary glyph prefixing every event title — also the handle used to find and
  // clear our own backfilled events.
  static const String _glyph = '📔';

  // "日记·YYYY-MM-DD" / "日记·YYYY-M-D" — the diary name carries the date.
  static final RegExp _dateRe = RegExp(r'(\d{4})\D(\d{1,2})\D(\d{1,2})');

  static bool _running = false;

  /// Run one backfill pass. [iphoneLinkEnabled] is the current setting; pass
  /// false to short-circuit before any network call. Safe to call repeatedly
  /// (e.g. on every app open) — already-synced pages are skipped.
  static Future<void> syncOnce(
    OurHomeGateway gateway, {
    required bool iphoneLinkEnabled,
  }) async {
    if (!Platform.isIOS || !iphoneLinkEnabled || _running) return;
    _running = true;
    try {
      final status = await IphoneLinkService.getStatus();
      if (!status.calendar) return;

      final entries = await gateway.fetchDiary();
      if (entries.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();

      // One-time: clear the notes-less batch from build 80, then forget which
      // ids were synced so they all get re-created with notes below.
      // onlyWithoutNotes keeps the deletion window narrow — the legacy batch is
      // exactly the note-less 📔 events; anything with notes (app-created since,
      // or the user's own) must survive even when this reruns after a reinstall.
      if (!(prefs.getBool(_notesMigrationKey) ?? false)) {
        final cleared = await IphoneLinkService.clearEventsByPrefix(
          _glyph,
          onlyWithoutNotes: true,
        );
        if (cleared < 0) return; // platform call failed — retry next pass
        await prefs.remove(_syncedIdsKey);
        await prefs.setBool(_notesMigrationKey, true);
      }

      final synced = (prefs.getStringList(_syncedIdsKey) ?? <String>[]).toSet();

      // Oldest first so the calendar fills in chronological order. Synced ids
      // are persisted after every successful add — if the process dies mid-run,
      // the next pass must not re-create events it already made (duplicates).
      for (final entry in entries.reversed) {
        final key = entry.id.isNotEmpty ? entry.id : '${entry.name}|${entry.time}';
        if (synced.contains(key)) continue;

        final date = _dateOf(entry);
        if (date == null) continue;

        final ok = await IphoneLinkService.addEvent(
          title: _titleOf(entry),
          date: date,
          notes: entry.text.trim(),
        );
        if (ok) {
          synced.add(key);
          await prefs.setStringList(_syncedIdsKey, synced.toList());
        }
      }
    } catch (e) {
      debugPrint('DiaryCalendarSync.syncOnce failed: $e');
    } finally {
      _running = false;
    }
  }

  /// Derives the `YYYY-MM-DD` date from the diary name (e.g. "日记·2026-06-29"),
  /// falling back to the stored timestamp. Returns null if neither parses.
  static String? _dateOf(OurHomeDiaryEntry entry) {
    final m = _dateRe.firstMatch(entry.name);
    if (m != null) {
      final y = m.group(1)!;
      final mo = m.group(2)!.padLeft(2, '0');
      final d = m.group(3)!.padLeft(2, '0');
      return '$y-$mo-$d';
    }
    final t = DateTime.tryParse(entry.time);
    if (t != null) {
      final mo = t.month.toString().padLeft(2, '0');
      final d = t.day.toString().padLeft(2, '0');
      return '${t.year}-$mo-$d';
    }
    return null;
  }

  /// Calendar event title: a short snippet of the page so the day is legible
  /// at a glance, prefixed with a diary glyph.
  static String _titleOf(OurHomeDiaryEntry entry) {
    var snippet = entry.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (snippet.length > 24) snippet = '${snippet.substring(0, 24)}…';
    return snippet.isEmpty ? '$_glyph 爸爸的日记' : '$_glyph $snippet';
  }
}
