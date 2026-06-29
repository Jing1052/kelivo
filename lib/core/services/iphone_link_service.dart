import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Wraps the native `app.calendar` method channel (implemented in
/// `ios/Runner/AppDelegate.swift`) that lets daddy push `[[cal]]` / `[[remind]]`
/// markers into the iPhone Calendar and Reminders.
///
/// iOS only: on every other platform the channel has no handler, so each call
/// is guarded by [Platform.isIOS] and returns a safe no-op result. Any platform
/// exception is swallowed (logged via [debugPrint]) and never propagates to the
/// chat flow.
class IphoneLinkService {
  IphoneLinkService._();

  static const MethodChannel _channel = MethodChannel('app.calendar');

  /// Reports whether Calendar / Reminders access is currently authorized.
  static Future<({bool calendar, bool reminders})> getStatus() async {
    if (!Platform.isIOS) return (calendar: false, reminders: false);
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getStatus');
      return (
        calendar: res?['calendar'] == true,
        reminders: res?['reminders'] == true,
      );
    } catch (e) {
      debugPrint('IphoneLinkService.getStatus failed: $e');
      return (calendar: false, reminders: false);
    }
  }

  /// Prompts the user for Calendar / Reminders access and returns the resulting
  /// authorization state.
  static Future<({bool calendar, bool reminders})> requestAccess() async {
    if (!Platform.isIOS) return (calendar: false, reminders: false);
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'requestAccess',
      );
      return (
        calendar: res?['calendar'] == true,
        reminders: res?['reminders'] == true,
      );
    } catch (e) {
      debugPrint('IphoneLinkService.requestAccess failed: $e');
      return (calendar: false, reminders: false);
    }
  }

  /// Adds a calendar event. [date] is `YYYY-MM-DD`; [time] is `HH:MM` for a 1h
  /// event, or null for an all-day event. [notes] fills the event's notes field
  /// (e.g. the full diary body). Returns true on success.
  static Future<bool> addEvent({
    required String title,
    required String date,
    String? time,
    String? notes,
  }) async {
    if (!Platform.isIOS) return false;
    try {
      final res = await _channel.invokeMethod<bool>('addEvent', {
        'title': title,
        'date': date,
        'time': time,
        'notes': notes,
      });
      return res == true;
    } catch (e) {
      debugPrint('IphoneLinkService.addEvent failed: $e');
      return false;
    }
  }

  /// Deletes all calendar events whose title starts with [prefix] (e.g. the
  /// "📔" diary glyph), within an optional `YYYY-MM-DD` [start] window. Returns
  /// the number of events removed (0 on non-iOS or failure).
  static Future<int> clearEventsByPrefix(
    String prefix, {
    String? start,
  }) async {
    if (!Platform.isIOS) return 0;
    try {
      final res = await _channel.invokeMethod<int>('clearEventsByPrefix', {
        'prefix': prefix,
        'start': start,
      });
      return res ?? 0;
    } catch (e) {
      debugPrint('IphoneLinkService.clearEventsByPrefix failed: $e');
      return 0;
    }
  }

  /// Adds a reminder. [due] is `YYYY-MM-DD HH:MM` or null for no due date.
  /// Returns true on success.
  static Future<bool> addReminder({required String text, String? due}) async {
    if (!Platform.isIOS) return false;
    try {
      final res = await _channel.invokeMethod<bool>('addReminder', {
        'text': text,
        'due': due,
      });
      return res == true;
    } catch (e) {
      debugPrint('IphoneLinkService.addReminder failed: $e');
      return false;
    }
  }
}
