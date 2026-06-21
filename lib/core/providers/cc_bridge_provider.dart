// CC bridge provider — state management for the CcCompanion (tmux-backed
// Claude Code) chat channel inside Still Here.
//
// Bridges the wire layer (CcBridgeClient, write-then-poll) to the UI: persists
// config, discovers a live endpoint across candidates, runs the polling loop,
// keeps the merged record list + agent status + thinking cards. See
// docs/CC_BRIDGE_INTEGRATION.md.

import 'dart:async';
import 'dart:convert';

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
  final Map<String, List<CcThinkingRecord>> _thinking =
      <String, List<CcThinkingRecord>>{};
  String? _cursor; // last seen ts (poll cursor)
  String? _settingsEtag;
  Timer? _pollTimer;
  String? _lastError;

  CcBridgeConfig get config => _config;
  CcConnectionState get connection => _connection;
  CcChatStatus get status => _status;
  List<CcChatRecord> get records => List<CcChatRecord>.unmodifiable(_records);
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
  }

  /// Send a message. Returns the result so the UI can surface the 502
  /// "agent unreachable" case distinctly.
  Future<CcSendResult?> sendText(String text, {String? quotedTs}) async {
    final c = _client;
    final trimmed = text.trim();
    if (c == null || trimmed.isEmpty) return null;
    try {
      final res = await c.send(trimmed, quotedTs: quotedTs);
      if (res.record != null) {
        _mergeRecords(<CcChatRecord>[res.record!]);
        if (res.record!.ts.isNotEmpty) _cursor = res.record!.ts;
      }
      _lastError = res.agentUnreachable ? 'agent_unreachable' : null;
      notifyListeners();
      unawaited(_pollOnce()); // pull soon so the reply shows up fast
      return res;
    } on CcAuthException {
      _connection = CcConnectionState.unauthorized;
      notifyListeners();
      rethrow;
    }
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

  @override
  void dispose() {
    _pollTimer?.cancel();
    _client?.dispose();
    super.dispose();
  }
}
