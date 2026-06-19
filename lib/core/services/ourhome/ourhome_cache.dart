import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, on-device cache for our home's room data — so opening a room shows
/// the last-seen content instantly (no buffering), works offline, and quietly
/// keeps a copy of everything on Cing's phone to treasure.
///
/// Stores the raw JSON response body per endpoint path. Seeded synchronously
/// once [init] has run at startup; writes are fire-and-forget.
class OurHomeCache {
  OurHomeCache._();

  static SharedPreferences? _prefs;
  static const String _prefix = 'ourhome_cache_v1:';

  /// Call once at app startup (before the UI reads the cache).
  static Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[OurHomeCache] init failed: $e');
    }
  }

  /// Synchronous read of the cached raw body for [path] (null if none / not
  /// initialised yet).
  static String? peek(String path) => _prefs?.getString('$_prefix$path');

  /// Fire-and-forget write of the raw body for [path].
  static void put(String path, String body) {
    final p = _prefs;
    if (p == null) return;
    // Don't store oversized payloads (keep the cache lean).
    if (body.length > 600000) return;
    p.setString('$_prefix$path', body);
  }
}
