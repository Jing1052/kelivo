// CC bridge HTTP client.
//
// Talks to a single CcCompanion `apns-server` base URL. In production it is
// reached over HTTPS via a Cloudflare Tunnel (cloudflared fronts the local
// 127.0.0.1:8795); auth is the shared secret, not TLS client identity. The
// model is write-then-poll: POST /chat/send, then GET /chat/poll on a cursor.
//
// Endpoint selection across multiple base URLs (ping the live one) lives in the
// provider layer; this client targets exactly one base URL. See
// docs/CC_BRIDGE_INTEGRATION.md §5.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cc_bridge_models.dart';

/// Thrown for transport/protocol errors (non-2xx other than the handled 502).
class CcBridgeException implements Exception {
  final String message;
  final int? statusCode;
  const CcBridgeException(this.message, {this.statusCode});
  @override
  String toString() =>
      'CcBridgeException(${statusCode ?? '-'}): $message';
}

/// Thrown on HTTP 401 (missing/wrong shared secret with strict_auth on).
class CcAuthException extends CcBridgeException {
  const CcAuthException(super.message) : super(statusCode: 401);
}

class CcBridgeClient {
  /// Normalized base URL: has a scheme and no trailing slash.
  final String baseUrl;
  final String sharedSecret;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsClient;

  CcBridgeClient({
    required String baseUrl,
    this.sharedSecret = '',
    this.timeout = const Duration(seconds: 12),
    http.Client? httpClient,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// Adds a scheme if missing (bare `100.x:8795` -> `http://100.x:8795`) and
  /// strips a trailing slash.
  static String normalizeBaseUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.contains('://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Map<String, String> get _authHeaders =>
      sharedSecret.isEmpty ? const {} : {'X-Auth-Token': sharedSecret};

  Map<String, String> get _jsonHeaders => {
        ..._authHeaders,
        'Content-Type': 'application/json; charset=utf-8',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    final q = <String, String>{
      for (final e in (query ?? const {}).entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
    return base.replace(
      path: '${base.path}$path',
      queryParameters: q.isEmpty ? null : q,
    );
  }

  Map<String, dynamic> _decodeJson(http.Response resp) {
    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (body.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(body);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
  }

  Never _raise(http.Response resp) {
    if (resp.statusCode == 401) {
      throw const CcAuthException('unauthorized: check shared secret');
    }
    String msg = 'HTTP ${resp.statusCode}';
    try {
      final m = _decodeJson(resp);
      if (m['error'] != null) msg = m['error'].toString();
    } catch (_) {}
    throw CcBridgeException(msg, statusCode: resp.statusCode);
  }

  /// `GET /health` — true when the server answers 2xx.
  Future<bool> health() async {
    try {
      final resp =
          await _http.get(_uri('/health')).timeout(timeout);
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// `GET /version` — server version string, or null if unavailable.
  Future<String?> version() async {
    try {
      final resp = await _http.get(_uri('/version')).timeout(timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final m = _decodeJson(resp);
      return (m['version'] ?? m['name'])?.toString();
    } catch (_) {
      return null;
    }
  }

  /// `GET /chat/history?limit=` — bulk seed for first load.
  Future<List<CcChatRecord>> history({int limit = 10000}) async {
    final resp = await _http
        .get(_uri('/chat/history', {'limit': '$limit'}), headers: _authHeaders)
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    return CcChatRecord.listFromJson(_decodeJson(resp)['records']);
  }

  /// `POST /chat/send`. Returns a [CcSendResult]; HTTP 502 is mapped to
  /// `agentUnreachable` (stored to history but tmux injection failed) rather
  /// than thrown.
  Future<CcSendResult> send(
    String text, {
    String? quotedTs,
    Map<String, dynamic>? location,
  }) async {
    final payload = <String, dynamic>{
      'text': text,
      if (quotedTs != null && quotedTs.isNotEmpty) 'quoted_ts': quotedTs,
      if (location != null) 'location': location,
    };
    final resp = await _http
        .post(_uri('/chat/send'),
            headers: _jsonHeaders, body: jsonEncode(payload))
        .timeout(timeout);

    if (resp.statusCode == 502) {
      final m = _decodeJson(resp);
      final rec = m['record'] is Map
          ? CcChatRecord.fromJson(Map<String, dynamic>.from(m['record']))
          : null;
      return CcSendResult(
        ok: false,
        agentUnreachable: true,
        record: rec,
        error: m['error']?.toString(),
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);

    final m = _decodeJson(resp);
    final rec = m['record'] is Map
        ? CcChatRecord.fromJson(Map<String, dynamic>.from(m['record']))
        : null;
    return CcSendResult(ok: m['ok'] == true, record: rec);
  }

  /// `POST /chat/upload?filename=&role=&text=` — raw bytes body (NOT multipart),
  /// metadata via query. ≤50MB. Like [send], HTTP 502 maps to `agentUnreachable`
  /// (stored to history but tmux injection failed) rather than thrown.
  Future<CcSendResult> upload(
    List<int> bytes, {
    required String filename,
    String role = 'user',
    String? text,
    Duration? timeout,
  }) async {
    final resp = await _http
        .post(
          _uri('/chat/upload', {
            'filename': filename,
            'role': role,
            if (text != null && text.isNotEmpty) 'text': text,
          }),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/octet-stream',
          },
          body: bytes,
        )
        .timeout(timeout ?? const Duration(seconds: 60));

    if (resp.statusCode == 502) {
      final m = _decodeJson(resp);
      final rec = m['record'] is Map
          ? CcChatRecord.fromJson(Map<String, dynamic>.from(m['record']))
          : null;
      return CcSendResult(
        ok: false,
        agentUnreachable: true,
        record: rec,
        error: m['error']?.toString(),
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);

    final m = _decodeJson(resp);
    final rec = m['record'] is Map
        ? CcChatRecord.fromJson(Map<String, dynamic>.from(m['record']))
        : null;
    return CcSendResult(ok: m['ok'] == true, record: rec);
  }

  /// `GET /chat/poll?since=&etag=&limit=` — incremental fetch.
  Future<CcPollResult> poll({
    String? since,
    String? etag,
    int limit = 50,
  }) async {
    final resp = await _http
        .get(
          _uri('/chat/poll', {
            if (since != null) 'since': since,
            if (etag != null) 'etag': etag,
            'limit': '$limit',
          }),
          headers: _authHeaders,
        )
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    return CcPollResult.fromJson(_decodeJson(resp));
  }

  /// `GET /chat/status` — lightweight presence.
  Future<CcChatStatus> status() async {
    final resp = await _http
        .get(_uri('/chat/status'), headers: _authHeaders)
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    return CcChatStatus.fromJson(_decodeJson(resp));
  }

  /// `GET /v1/thinking?turn_id=&limit=` — thinking-card records for a turn.
  Future<List<CcThinkingRecord>> thinking(
    String turnId, {
    int limit = 50,
  }) async {
    final resp = await _http
        .get(
          _uri('/v1/thinking', {'turn_id': turnId, 'limit': '$limit'}),
          headers: _authHeaders,
        )
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    return CcThinkingRecord.listFromJson(_decodeJson(resp)['records']);
  }

  // ---- Remote control: terminal mirror + slash commands ----
  //
  // These endpoints require the server to run with `allow_remote_control=true`.
  // The provider gates them on [CcBridgeConfig.remoteControlEnabled]; the
  // client itself stays a thin HTTP layer. `/chain/clear` is the documented
  // exception that needs no remote control. See docs/CC_BRIDGE_INTEGRATION.md §5.

  /// Special keys accepted by [tmuxSend]'s `key` argument (server whitelist).
  static const Set<String> tmuxSpecialKeys = <String>{
    'Escape',
    'Up',
    'Down',
    'Enter',
    'Tab',
    'C-c',
    'C-l',
  };

  /// `GET /tmux/capture?session=&lines=` — snapshot the tmux pane.
  Future<CcTmuxCapture> tmuxCapture({
    required String session,
    int lines = 120,
  }) async {
    final resp = await _http
        .get(
          _uri('/tmux/capture', {'session': session, 'lines': '$lines'}),
          headers: _authHeaders,
        )
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    return CcTmuxCapture.fromJson(_decodeJson(resp));
  }

  /// `POST /tmux/send` — inject literal text and/or one special key. Provide
  /// [keys] for literal text (optionally followed by Enter via [enter]) or
  /// [key] for a whitelisted special key ([tmuxSpecialKeys]).
  Future<void> tmuxSend({
    required String session,
    String? keys,
    bool enter = false,
    String? key,
  }) async {
    if (key != null && !tmuxSpecialKeys.contains(key)) {
      throw CcBridgeException('unsupported tmux key: $key');
    }
    await _postExpectOk('/tmux/send', <String, dynamic>{
      'session': session,
      if (keys != null) 'keys': keys,
      'enter': enter,
      if (key != null) 'key': key,
    });
  }

  /// `GET /chain/sessions` — list tmux/claude sessions and the active one.
  Future<CcChainSessions> chainSessions() async {
    final resp = await _http
        .get(_uri('/chain/sessions'), headers: _authHeaders)
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    return CcChainSessions.fromJson(_decodeJson(resp));
  }

  /// `POST /chain/new_session` — create a new tmux+claude session (no switch).
  Future<void> chainNewSession() =>
      _postExpectOk('/chain/new_session', const <String, dynamic>{});

  /// `POST /chain/switch {sid}` — make [sid] the active session.
  Future<void> chainSwitch(String sid) =>
      _postExpectOk('/chain/switch', <String, dynamic>{'sid': sid});

  /// `POST /chain/abort {session}` — interrupt the agent (3× Escape).
  Future<void> chainAbort(String session) =>
      _postExpectOk('/chain/abort', <String, dynamic>{'session': session});

  /// `POST /chain/clear {session}` — clear context. The documented exception
  /// that does NOT require remote control.
  Future<void> chainClear(String session) =>
      _postExpectOk('/chain/clear', <String, dynamic>{'session': session});

  /// `POST /chain/restart {session}` — `C-c C-c` then `claude --resume`.
  Future<void> chainRestart(String session) =>
      _postExpectOk('/chain/restart', <String, dynamic>{'session': session});

  Future<void> _postExpectOk(String path, Map<String, dynamic> payload) async {
    final resp = await _http
        .post(_uri(path), headers: _jsonHeaders, body: jsonEncode(payload))
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
  }

  /// Absolute URL for an attachment relative path (`/attachments/<name>`).
  String attachmentUrl(String relativePath) {
    if (relativePath.startsWith('http')) return relativePath;
    final p = relativePath.startsWith('/') ? relativePath : '/$relativePath';
    return '$baseUrl$p';
  }

  void dispose() {
    if (_ownsClient) _http.close();
  }
}
