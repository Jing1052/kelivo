import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../utils/app_directories.dart';

/// Local, on-device cache for our home's room data — so opening a room shows
/// the last-seen content instantly (no buffering), works offline, and quietly
/// keeps a copy of everything on Cing's phone to treasure.
///
/// Stores each endpoint's raw JSON body as a file under
/// `<appData>/ourhome_cache/`, so it shows up in Settings → Storage as its own
/// category. The on-disk format is one header line (the original request path)
/// followed by the raw body, which lets [init] rebuild the in-memory index
/// without depending on how the filename was encoded.
///
/// Reads are served synchronously from the in-memory map once [init] has run at
/// startup; writes are fire-and-forget.
class OurHomeCache {
  OurHomeCache._();

  /// Top-level directory name under appData. Must match the storage scanner's
  /// `case 'ourhome_cache'` so usage is attributed to our own category.
  static const String _dirName = 'ourhome_cache';

  /// Don't store oversized payloads (keep the cache lean).
  static const int _maxBodyLength = 600000;

  static Directory? _dir;
  static final Map<String, String> _mem = <String, String>{};

  /// Call once at app startup (before the UI reads the cache).
  static Future<void> init() async {
    try {
      final root = await AppDirectories.getAppDataDirectory();
      final dir = Directory('${root.path}/$_dirName');
      _dir = dir;
      if (await dir.exists()) {
        await for (final ent in dir.list(followLinks: false)) {
          if (ent is! File) continue;
          if (!ent.path.endsWith('.json')) continue;
          try {
            final raw = await ent.readAsString();
            final sep = raw.indexOf('\n');
            if (sep <= 0) continue;
            final path = raw.substring(0, sep);
            final body = raw.substring(sep + 1);
            _mem[path] = body;
          } catch (_) {
            // Skip unreadable entries; they'll be rewritten on next fetch.
          }
        }
      }
    } catch (e) {
      debugPrint('[OurHomeCache] init failed: $e');
    }
  }

  /// Synchronous read of the cached raw body for [path] (null if none / not
  /// initialised yet).
  static String? peek(String path) => _mem[path];

  /// Fire-and-forget write of the raw body for [path].
  static void put(String path, String body) {
    if (body.length > _maxBodyLength) return;
    _mem[path] = body;
    final dir = _dir;
    if (dir == null) return;
    unawaited(() async {
      try {
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('${dir.path}/${_fileNameFor(path)}');
        await file.writeAsString('$path\n$body');
      } catch (e) {
        debugPrint('[OurHomeCache] put failed: $e');
      }
    }());
  }

  /// Deterministic, collision-resistant filename for [path]: a readable
  /// sanitized suffix plus a stable FNV-1a hash so re-fetching the same
  /// endpoint overwrites the same file.
  static String _fileNameFor(String path) {
    int hash = 0x811c9dc5;
    for (final c in path.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final safe = path.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final suffix = safe.length > 48 ? safe.substring(safe.length - 48) : safe;
    return '${suffix}_${hash.toRadixString(16)}.json';
  }
}
