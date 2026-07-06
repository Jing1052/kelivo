// Workgroup (group chat) HTTP client.
//
// Talks to the same CcCompanion `apns-server` base URL as [CcBridgeClient]
// (same Cloudflare Tunnel, same `X-Auth-Token` shared secret), but to the
// `/group/*` endpoint family: an append-only multi-agent message stream with
// mention routing. The model is write-then-poll, like the CC chat.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cc_bridge_client.dart' show CcBridgeException, CcAuthException;
import 'group_chat_models.dart';

class GroupChatClient {
  /// Normalized base URL: has a scheme and no trailing slash.
  final String baseUrl;
  final String sharedSecret;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsClient;

  GroupChatClient({
    required String baseUrl,
    this.sharedSecret = '',
    this.timeout = const Duration(seconds: 12),
    http.Client? httpClient,
  })  : baseUrl = _normalize(baseUrl),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static String _normalize(String raw) {
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

  /// Auth headers for loading attachment media via `Image.network(headers:)`.
  Map<String, String> get attachmentHeaders => _authHeaders;

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

  /// `GET /group/roster` — members + agent presence snapshot. A 404 means the
  /// home server predates the workgroup endpoints; callers surface that as
  /// "server too old", not a transport failure.
  Future<GroupRosterResult> roster() async {
    final resp = await _http
        .get(_uri('/group/roster'), headers: _authHeaders)
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    return GroupRosterResult.fromJson(_decodeJson(resp));
  }

  /// `GET /group/history?since=&before=&limit=` — bulk seed for first load.
  Future<List<GroupRecord>> history({
    String? since,
    String? before,
    int limit = 200,
  }) async {
    final resp = await _http
        .get(
          _uri('/group/history', {
            if (since != null) 'since': since,
            if (before != null) 'before': before,
            'limit': '$limit',
          }),
          headers: _authHeaders,
        )
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    return GroupRecord.listFromJson(_decodeJson(resp)['records']);
  }

  /// `GET /group/poll?since=&limit=&viewer=` — incremental fetch. [viewer]
  /// doubles as the human's presence heartbeat (Build 220 item 13).
  Future<GroupPollResult> poll({
    String? since,
    int limit = 100,
    String? viewer,
  }) async {
    final resp = await _http
        .get(
          _uri('/group/poll', {
            if (since != null) 'since': since,
            'limit': '$limit',
            if (viewer != null) 'viewer': viewer,
          }),
          headers: _authHeaders,
        )
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    return GroupPollResult.fromJson(_decodeJson(resp));
  }

  /// `POST /group/send`. Mentions are parsed server-side from `@id` tokens in
  /// [text]; no explicit mention means broadcast (agents self-decide). The
  /// server 429s duplicate (sender, text) pairs inside 3s — mapped to
  /// `deduped: true` rather than thrown, so retries stay silent.
  Future<GroupSendResult> send(
    String text, {
    required String senderId,
    String? clientMsgId,
    String? parentMsgId,
    String? replyTo,
  }) async {
    final payload = <String, dynamic>{
      'text': text,
      'sender_id': senderId,
      'source': 'ios-app',
      if (clientMsgId != null && clientMsgId.isNotEmpty)
        'client_msg_id': clientMsgId,
      if (parentMsgId != null && parentMsgId.isNotEmpty)
        'parent_msg_id': parentMsgId,
      if (replyTo != null && replyTo.isNotEmpty) 'reply_to': replyTo,
    };
    final resp = await _http
        .post(_uri('/group/send'),
            headers: _jsonHeaders, body: jsonEncode(payload))
        .timeout(timeout);

    if (resp.statusCode == 429) {
      final m = _decodeJson(resp);
      return GroupSendResult(
        ok: false,
        deduped: m['deduped'] == true,
        error: m['error']?.toString(),
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);

    final m = _decodeJson(resp);
    return GroupSendResult(
      ok: m['ok'] == true,
      record: m['record'] is Map
          ? GroupRecord.fromJson(Map<String, dynamic>.from(m['record']))
          : null,
      targets: (m['targets'] is List)
          ? (m['targets'] as List)
              .map((e) => e.toString())
              .toList(growable: false)
          : const <String>[],
    );
  }

  /// `POST /group/upload?filename=&sender_id=&text=&reply_to=` — raw bytes
  /// body (NOT multipart), metadata via query; mirrors `/chat/upload`.
  Future<GroupSendResult> upload(
    List<int> bytes, {
    required String filename,
    required String senderId,
    String? text,
    String? replyTo,
    Duration? timeout,
  }) async {
    final resp = await _http
        .post(
          _uri('/group/upload', {
            'filename': filename,
            'sender_id': senderId,
            if (text != null && text.isNotEmpty) 'text': text,
            if (replyTo != null && replyTo.isNotEmpty) 'reply_to': replyTo,
          }),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/octet-stream',
          },
          body: bytes,
        )
        .timeout(timeout ?? const Duration(seconds: 60));
    if (resp.statusCode < 200 || resp.statusCode >= 300) _raise(resp);
    final m = _decodeJson(resp);
    return GroupSendResult(
      ok: m['ok'] == true,
      record: m['record'] is Map
          ? GroupRecord.fromJson(Map<String, dynamic>.from(m['record']))
          : null,
    );
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
