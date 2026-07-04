import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';

/// A song in the eryu music world.
///
/// eryu returns two id conventions — search/daily results carry `id`, while
/// stored playlist/recent/room songs carry `songId`. We normalize to a single
/// `songId` on the way in and always emit `songId` on the way out (room events,
/// memory, recent), matching the web client's `s.id || s.songId` rule.
class EryuSong {
  const EryuSong({
    required this.songId,
    required this.name,
    required this.artist,
    required this.cover,
    this.album = '',
  });

  final String songId;
  final String name;
  final String artist;
  final String cover;
  final String album;

  static String _readId(Map<String, dynamic> j) {
    final v = j['id'] ?? j['songId'];
    return v == null ? '' : v.toString();
  }

  factory EryuSong.fromJson(Map<String, dynamic> j) => EryuSong(
        songId: _readId(j),
        name: (j['name'] ?? '').toString(),
        artist: (j['artist'] ?? '').toString(),
        cover: (j['cover'] ?? '').toString(),
        album: (j['album'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'name': name,
        'artist': artist,
        'cover': cover,
        'album': album,
      };
}

class EryuPlaylist {
  const EryuPlaylist({
    required this.id,
    required this.name,
    required this.count,
    required this.cover,
  });

  final String id;
  final String name;
  final int count;
  final String cover;

  factory EryuPlaylist.fromJson(Map<String, dynamic> j) => EryuPlaylist(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        count: j['count'] is num ? (j['count'] as num).toInt() : 0,
        cover: (j['cover'] ?? '').toString(),
      );
}

/// Wrap a fetch so one source's failure can't veto the others
/// (kelivo AGENTS §8 2026-07-02 rule). Returns null on failure.
Future<T?> eryuSoft<T>(Future<T> f, String what) => f.then<T?>((v) => v).catchError((Object e) {
      debugPrint('[eryu] $what failed: $e');
      return null;
    });

/// HTTP client for the self-hosted eryu music backend (clmusic).
///
/// Immutable value object built per-use from [SettingsProvider]; a separate
/// service with its own key from 老家's gateway — do not merge the two.
class EryuClient {
  const EryuClient({required this.base, required this.token});

  final String base;
  final String token;

  static const String defaultBase = 'https://clmusic.zeabur.app';

  /// Build from settings; null when no token is set yet (room shows setup).
  static EryuClient? fromContext(BuildContext context) {
    final s = context.read<SettingsProvider>();
    final token = s.eryuToken.trim();
    if (token.isEmpty) return null;
    final override = s.eryuBaseUrl.trim();
    return EryuClient(base: override.isEmpty ? defaultBase : override, token: token);
  }

  Map<String, String> get _headers => {'X-Auth-Token': token};

  /// Join a server-relative media path (e.g. `/music/file/x.mp3`) onto [base].
  String mediaUrl(String path) => path.startsWith('http') ? path : '$base$path';

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$base$path');
    return (query == null || query.isEmpty) ? u : u.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
  ]) async {
    final uri = _uri(path, query);
    final res = await http.get(uri, headers: _headers).timeout(timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('eryu GET $path HTTP ${res.statusCode}', uri);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw http.ClientException('eryu GET $path: unexpected body', uri);
    }
    return data;
  }

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body) async {
    final uri = _uri(path);
    final res = await http
        .post(uri, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw http.ClientException('eryu POST $path HTTP ${res.statusCode}', uri);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  List<EryuSong> _songs(Map<String, dynamic> d) => (d['songs'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(EryuSong.fromJson)
      .toList();

  // ── Library ──
  Future<List<EryuSong>> search(String q) async => _songs(await _getJson('/music/search', {'q': q}));

  Future<List<EryuSong>> recent() async => _songs(await _getJson('/music/recent'));

  Future<List<EryuSong>> daily() async => _songs(await _getJson('/music/daily'));

  Future<List<EryuSong>> roam([String? songId]) async =>
      _songs(await _getJson('/music/roam', songId != null && songId.isNotEmpty ? {'id': songId} : null));

  Future<List<EryuSong>> playlistSongs(String id) async =>
      _songs(await _getJson('/music/playlists/songs', {'id': id}));

  Future<List<EryuPlaylist>> playlists() async {
    final d = await _getJson('/music/playlists');
    return (d['playlists'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EryuPlaylist.fromJson)
        .toList();
  }

  /// Full, streamable audio URL for a song. The file endpoint is auth-free and
  /// Range-capable, so it can be handed straight to the audio player.
  Future<String?> songUrl(String songId) async {
    final d = await _getJson('/music/url', {'id': songId});
    final u = d['url'];
    if (u is! String || u.isEmpty) return null;
    return mediaUrl(u);
  }

  Future<Map<String, dynamic>> lyric(String songId) async => _getJson('/music/lyric', {'id': songId});

  Future<Map<String, dynamic>> memory(String songId) async => _getJson('/music/memory', {'id': songId});

  Future<void> favLine(String songId, String line) =>
      _postJson('/music/memory', {'songId': songId, 'action': 'fav_line', 'line': line});

  Future<void> recentAdd(EryuSong song) => _postJson('/music/recent/add', song.toJson());

  Future<void> listenComplete(String songId, {bool together = false}) => _postJson(
        '/music/listen-complete',
        {'songId': songId, if (together) 'source': 'together'},
      );

  // ── Listen-together room (Step 2 wires the UI; the transport lives here) ──
  Future<Map<String, dynamic>> roomInfo(String user) async => _getJson('/music/room', {'user': user});

  /// 25s server-side long-poll; give it headroom before the client timeout.
  Future<Map<String, dynamic>> roomPoll(int since, String user) async => _getJson(
        '/music/room/poll',
        {'since': since.toString(), 'user': user},
        const Duration(seconds: 35),
      );

  Future<void> roomEvent(Map<String, dynamic> event) => _postJson('/music/room/event', event);
}
