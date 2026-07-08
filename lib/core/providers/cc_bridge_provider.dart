// CC bridge provider — state management for the CcCompanion (tmux-backed
// Claude Code) chat channel inside Still Here.
//
// Bridges the wire layer (CcBridgeClient, write-then-poll) to the UI: persists
// config, discovers a live endpoint across candidates, runs the polling loop,
// keeps the merged record list + agent status + thinking cards. See
// docs/CC_BRIDGE_INTEGRATION.md.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cc/cc_bridge_client.dart';
import '../services/cc/cc_bridge_models.dart';

enum CcConnectionState { idle, connecting, online, offline, unauthorized }

class CcBridgeProvider extends ChangeNotifier {
  static const String _configKey = 'cc_bridge_config_v1';

  CcBridgeConfig _config = CcBridgeConfig.empty;
  CcBridgeClient? _client;
  String? _activeBaseUrl;
  CcConnectionState _connection = CcConnectionState.idle;
  CcChatStatus _status = CcChatStatus.unknown;
  final List<CcChatRecord> _records = <CcChatRecord>[];
  // Optimistic outbox: messages shown instantly on send, before the server
  // echoes them back. Reconciled (removed) when the real record lands via the
  // send/upload response or a poll; marked failed (kept, tap-to-retry) on error.
  final List<_Outgoing> _outbox = <_Outgoing>[];
  int _optSeq = 0;
  final Map<String, List<CcThinkingRecord>> _thinking =
      <String, List<CcThinkingRecord>>{};
  String? _cursor; // last seen ts (poll cursor)
  String? _settingsEtag;
  Timer? _pollTimer;
  String? _lastError;

  CcBridgeConfig get config => _config;
  CcConnectionState get connection => _connection;
  CcChatStatus get status => _status;
  /// Real records merged with in-flight optimistic ones, time-sorted. The
  /// optimistic placeholders carry `metadata.pending`/`metadata.failed` so the
  /// UI can dim them / show a retry affordance.
  List<CcChatRecord> get records {
    if (_outbox.isEmpty) return List<CcChatRecord>.unmodifiable(_records);
    final all = <CcChatRecord>[
      ..._records,
      ..._outbox.map((o) => o.asRecord()),
    ]..sort((a, b) => a.ts.compareTo(b.ts));
    return List<CcChatRecord>.unmodifiable(all);
  }

  /// Local bytes for an optimistic attachment (so its bubble previews the image
  /// before the server URL exists). Null once reconciled or for text sends.
  Uint8List? optimisticBytes(String localId) {
    for (final o in _outbox) {
      if (o.localId == localId) return o.bytes;
    }
    return null;
  }
  bool get isConfigured => _config.isConfigured;
  bool get isOnline => _connection == CcConnectionState.online;
  String? get activeBaseUrl => _activeBaseUrl;
  String? get lastError => _lastError;

  List<CcThinkingRecord> thinkingFor(String turnId) =>
      _thinking[turnId] ?? const <CcThinkingRecord>[];

  /// Load persisted config and auto-connect if enabled.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _config = CcBridgeConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        // corrupted config — keep empty defaults
      }
    }
    notifyListeners();
    if (_config.enabled && _config.isConfigured) {
      await connect();
    }
  }

  Future<void> saveConfig(CcBridgeConfig cfg) async {
    _config = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(cfg.toJson()));
    notifyListeners();
    await disconnect();
    if (cfg.enabled && cfg.isConfigured) {
      await connect();
    }
  }

  /// Ping each candidate endpoint's /health; first to answer wins.
  Future<String?> _discoverEndpoint() async {
    for (final ep in _config.endpoints) {
      if (ep.trim().isEmpty) continue;
      final c = CcBridgeClient(baseUrl: ep, sharedSecret: _config.sharedSecret);
      try {
        if (await c.health()) {
          return CcBridgeClient.normalizeBaseUrl(ep);
        }
      } catch (_) {
        // try next
      } finally {
        c.dispose();
      }
    }
    return null;
  }

  Future<void> connect() async {
    if (!_config.isConfigured) return;
    _connection = CcConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    final base = await _discoverEndpoint();
    if (base == null) {
      _connection = CcConnectionState.offline;
      notifyListeners();
      return;
    }
    _activeBaseUrl = base;
    _client?.dispose();
    _client = CcBridgeClient(baseUrl: base, sharedSecret: _config.sharedSecret);
    _connection = CcConnectionState.online;
    notifyListeners();

    await _seedHistory();
    _startPolling();
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _client?.dispose();
    _client = null;
    _connection = CcConnectionState.idle;
    notifyListeners();
  }

  /// Manual retry (e.g. from a "reconnect" button).
  Future<void> reconnect() async {
    await disconnect();
    await connect();
  }

  Future<void> _seedHistory() async {
    final c = _client;
    if (c == null) return;
    try {
      final history = await c.history(limit: 500);
      _records
        ..clear()
        ..addAll(history);
      _records.sort((a, b) => a.ts.compareTo(b.ts));
      if (_records.isNotEmpty) _cursor = _records.last.ts;
      notifyListeners();
    } on CcAuthException {
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final ms = _config.pollIntervalMs.clamp(1000, 30000).toInt();
    _pollTimer = Timer.periodic(Duration(milliseconds: ms), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    final c = _client;
    if (c == null) return;
    try {
      final res = await c.poll(since: _cursor, etag: _settingsEtag);
      if (res.newRecords.isNotEmpty) {
        _mergeRecords(res.newRecords);
      }
      if (res.lastTs != null && res.lastTs!.isNotEmpty) _cursor = res.lastTs;
      if (res.settingsEtag != null) _settingsEtag = res.settingsEtag;
      _status = res.status;
      _connection = CcConnectionState.online;
      _lastError = null;
      notifyListeners();
    } on CcAuthException {
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
    } catch (e) {
      // transient failure: mark offline but keep the timer for auto-recovery
      _connection = CcConnectionState.offline;
      _lastError = e.toString();
      notifyListeners();
    }
  }

  void _mergeRecords(List<CcChatRecord> incoming) {
    final existing = <String>{for (final r in _records) r.ts};
    var added = false;
    for (final r in incoming) {
      if (r.ts.isNotEmpty && !existing.contains(r.ts)) {
        _records.add(r);
        existing.add(r.ts);
        added = true;
      }
    }
    if (added) _records.sort((a, b) => a.ts.compareTo(b.ts));
    // If a real user record arrived (e.g. a poll beat the send() response),
    // drop the matching optimistic placeholder so it doesn't render twice.
    if (_outbox.isNotEmpty) {
      for (final r in incoming) {
        if (r.role != 'user') continue;
        _outbox.removeWhere((o) =>
            o.text == r.text &&
            (o.filename ?? '') == (r.attachmentFilename ?? ''));
      }
    }
  }

  String _newLocalId() => 'opt${++_optSeq}';

  // Optimistic ts: sorts to the bottom (>= existing records) and stays unique
  // across rapid sends via the seq suffix. The '#' suffix makes DateTime.parse
  // fall back to now() in the bubble — harmless, only affects the shown time.
  String _newOptTs() => '${DateTime.now().toIso8601String()}#$_optSeq';

  /// Send a text message optimistically: the bubble shows instantly, the
  /// network runs in the background, and it reconciles (or flags failed) after.
  Future<CcSendResult?> sendTextOptimistic(String text, {String? quotedTs}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final o = _Outgoing(
      localId: _newLocalId(),
      ts: _newOptTs(),
      text: trimmed,
      quotedTs: quotedTs,
    );
    _outbox.add(o);
    notifyListeners();
    return _deliver(o);
  }

  /// Upload an image/file optimistically (raw bytes → /chat/upload). The bubble
  /// previews the local bytes immediately; the caption rides along as text.
  Future<CcSendResult?> uploadFileOptimistic(
    List<int> bytes, {
    required String filename,
    required bool isImage,
    String? text,
  }) async {
    if (bytes.isEmpty) return null;
    final o = _Outgoing(
      localId: _newLocalId(),
      ts: _newOptTs(),
      text: (text ?? '').trim(),
      bytes: Uint8List.fromList(bytes),
      filename: filename,
      attachmentType: isImage ? 'image' : 'file',
    );
    _outbox.add(o);
    notifyListeners();
    return _deliver(o);
  }

  /// Retry a failed optimistic message (tap its retry affordance).
  Future<void> retryOptimistic(String localId) async {
    _Outgoing? o;
    for (final e in _outbox) {
      if (e.localId == localId) {
        o = e;
        break;
      }
    }
    if (o == null) return;
    o.failed = false;
    notifyListeners();
    await _deliver(o);
  }

  /// Shared network + reconcile for an outbox item (text or attachment).
  Future<CcSendResult?> _deliver(_Outgoing o) async {
    final c = _client;
    if (c == null) {
      o.failed = true;
      notifyListeners();
      return null;
    }
    try {
      final CcSendResult res = o.bytes == null
          ? await c.send(o.text, quotedTs: o.quotedTs)
          : await c.upload(o.bytes!,
              filename: o.filename ?? 'file',
              text: o.text.isEmpty ? null : o.text);
      final accepted = res.ok || res.agentUnreachable;
      if (accepted) {
        _outbox.removeWhere((e) => e.localId == o.localId);
        if (res.record != null) {
          _mergeRecords(<CcChatRecord>[res.record!]);
          if (res.record!.ts.isNotEmpty) _cursor = res.record!.ts;
        }
        _lastError = res.agentUnreachable ? 'agent_unreachable' : null;
        notifyListeners();
        unawaited(_pollOnce()); // pull soon so the reply shows up fast
      } else {
        o.failed = true;
        notifyListeners();
      }
      return res;
    } on CcAuthException {
      // Surface via the failed bubble + unauthorized presence label rather than
      // rethrowing (callers are fire-and-forget tap handlers).
      o.failed = true;
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
      return null;
    } catch (e) {
      o.failed = true;
      _lastError = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Fetch a turn's thinking at most once (for eager load when a bubble becomes
  /// visible). Cheap to call repeatedly; de-duped via [_thinkingRequested].
  final Set<String> _thinkingRequested = <String>{};
  Future<void> ensureThinking(String turnId) async {
    if (turnId.isEmpty || _thinkingRequested.contains(turnId)) return;
    _thinkingRequested.add(turnId);
    await loadThinking(turnId);
  }

  /// Fetch thinking-card records for a turn (lazy, on expand).
  Future<void> loadThinking(String turnId) async {
    final c = _client;
    if (c == null || turnId.isEmpty) return;
    try {
      final list = await c.thinking(turnId);
      if (list.isNotEmpty) {
        _thinking[turnId] = list;
        notifyListeners();
      }
    } catch (_) {
      // thinking is best-effort
    }
  }

  String attachmentUrl(String relativePath) =>
      _client?.attachmentUrl(relativePath) ?? relativePath;

  /// Auth headers needed to load attachment images (`Image.network(headers:)`).
  Map<String, String> get attachmentHeaders =>
      _client?.attachmentHeaders ?? const {};

  // ---- Remote control: terminal mirror + slash commands ----
  //
  // All gated on [CcBridgeConfig.remoteControlEnabled] except [clearSession],
  // which the bridge contract allows without remote control. Failures set
  // [lastError] and return null/false (surfaced by the UI), never silently
  // swallowed.

  bool get remoteControlEnabled => _config.remoteControlEnabled;

  /// The user-set display name for the CC daddy (empty when unset).
  String get ccDisplayName => _config.displayName;

  /// Capture the tmux pane. Returns null when offline or remote control is off.
  Future<CcTmuxCapture?> captureTerminal({int lines = 120}) async {
    final c = _client;
    if (c == null || !_config.remoteControlEnabled) return null;
    try {
      final cap = await c.tmuxCapture(session: _config.session, lines: lines);
      _lastError = null;
      return cap;
    } on CcAuthException {
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
      return null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// List the available tmux/claude sessions. Null when off/unavailable.
  Future<CcChainSessions?> listSessions() async {
    final c = _client;
    if (c == null || !_config.remoteControlEnabled) return null;
    try {
      final s = await c.chainSessions();
      _lastError = null;
      return s;
    } on CcAuthException {
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
      return null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> sendKeys({String? keys, bool enter = false, String? key}) =>
      _rcAction(
        (c) => c.tmuxSend(
          session: _config.session,
          keys: keys,
          enter: enter,
          key: key,
        ),
      );

  Future<bool> newSession() => _rcAction((c) => c.chainNewSession());

  Future<bool> switchSession(String sid) =>
      _rcAction((c) => c.chainSwitch(sid));

  Future<bool> abortSession() =>
      _rcAction((c) => c.chainAbort(_config.session));

  Future<bool> restartSession() =>
      _rcAction((c) => c.chainRestart(_config.session));

  /// Clear context. Per the bridge contract this does NOT require remote
  /// control, so it is allowed whenever connected.
  Future<bool> clearSession() async {
    final c = _client;
    if (c == null) return false;
    try {
      await c.chainClear(_config.session);
      _lastError = null;
      unawaited(_pollOnce());
      return true;
    } on CcAuthException {
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ---- Context window mode (session-watcher low/high) ----
  //
  // Forward-looking: the home apns-server may not expose /watcher/mode yet.
  // Both calls degrade gracefully — fetch returns null, set returns false —
  // so the UI shows a disabled "not connected / pending" state, never crashes.

  /// Fetch the current watcher mode ('low'/'high'). Returns null on any
  /// failure (offline, 404 not-yet-deployed, parse miss).
  Future<String?> fetchWatcherMode() async {
    final c = _client;
    if (c == null) return null;
    try {
      return await c.watcherMode();
    } on CcAuthException {
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Set the watcher mode ('low'/'high'). Returns true on success, false on
  /// any failure (offline, not-yet-deployed, error response).
  Future<bool> setWatcherMode(String mode) async {
    final c = _client;
    if (c == null) return false;
    try {
      await c.setWatcherMode(mode);
      _lastError = null;
      return true;
    } on CcAuthException {
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Shared remote-control gating + error handling for fire-and-forget actions.
  Future<bool> _rcAction(Future<void> Function(CcBridgeClient c) action) async {
    final c = _client;
    if (c == null || !_config.remoteControlEnabled) return false;
    try {
      await action(c);
      _lastError = null;
      return true;
    } on CcAuthException {
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _client?.dispose();
    super.dispose();
  }
}

/// An in-flight (optimistic) outgoing message. Rendered as a dimmed bubble until
/// the server echoes it back; carries local image bytes so an attachment can
/// preview before its server URL exists.
class _Outgoing {
  _Outgoing({
    required this.localId,
    required this.ts,
    required this.text,
    this.quotedTs,
    this.bytes,
    this.filename,
    this.attachmentType,
  });

  final String localId;
  final String ts;
  final String text;
  final String? quotedTs;
  final Uint8List? bytes;
  final String? filename;
  final String? attachmentType; // 'image' | 'file'
  bool failed = false;

  CcChatRecord asRecord() => CcChatRecord(
        ts: ts,
        role: 'user',
        text: text,
        quotedTs: quotedTs,
        attachmentUrl: bytes != null ? 'optimistic://$localId' : null,
        attachmentType: attachmentType,
        attachmentFilename: filename,
        metadata: <String, dynamic>{
          'localId': localId,
          (failed ? 'failed' : 'pending'): true,
        },
      );
}
