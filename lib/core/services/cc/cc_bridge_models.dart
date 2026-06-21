// CC bridge (CcCompanion apns-server) data models.
//
// These mirror the JSON contract exposed by `apns-server/push.py`. They are
// intentionally kept independent from the Hive `ChatMessage` model: the bridge
// speaks its own wire format (records keyed by ISO8601 `ts`, write-then-poll),
// and the UI layer maps these into the app's chat models. Parsing is defensive
// because the server may omit fields.
//
// See docs/CC_BRIDGE_INTEGRATION.md §5 for the full contract.

/// A single chat record as returned by `/chat/history`, `/chat/poll`,
/// `/chat/send`.
class CcChatRecord {
  /// ISO8601 timestamp with milliseconds and tz offset. Primary id / poll cursor.
  final String ts;

  /// 'user' | 'assistant' | 'task' | 'move'.
  final String role;

  /// Message body.
  final String text;

  /// Origin, e.g. 'ios-app', 'system'.
  final String? source;

  /// Links a turn to its thinking cards (see [CcThinkingRecord]).
  final String? turnId;

  final String? quotedTs;
  final String? quotedText;

  /// `/attachments/<uuid>.<ext>` relative path, if any.
  final String? attachmentUrl;

  /// 'image' | 'file'.
  final String? attachmentType;
  final String? attachmentFilename;

  /// `{lat, lon, label?, accuracy?}` if present.
  final Map<String, dynamic>? location;

  final Map<String, dynamic>? metadata;

  const CcChatRecord({
    required this.ts,
    required this.role,
    required this.text,
    this.source,
    this.turnId,
    this.quotedTs,
    this.quotedText,
    this.attachmentUrl,
    this.attachmentType,
    this.attachmentFilename,
    this.location,
    this.metadata,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get hasAttachment => (attachmentUrl ?? '').isNotEmpty;

  static String _asString(dynamic v) => v == null ? '' : v.toString();

  static String? _asStringOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static Map<String, dynamic>? _asMapOrNull(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  factory CcChatRecord.fromJson(Map<String, dynamic> json) {
    return CcChatRecord(
      ts: _asString(json['ts']),
      role: _asString(json['role']),
      text: _asString(json['text']),
      source: _asStringOrNull(json['source']),
      turnId: _asStringOrNull(json['turn_id']),
      quotedTs: _asStringOrNull(json['quoted_ts']),
      quotedText: _asStringOrNull(json['quoted_text']),
      attachmentUrl: _asStringOrNull(json['attachment_url']),
      attachmentType: _asStringOrNull(json['attachment_type']),
      attachmentFilename: _asStringOrNull(json['attachment_filename']),
      location: _asMapOrNull(json['location']),
      metadata: _asMapOrNull(json['metadata']),
    );
  }

  static List<CcChatRecord> listFromJson(dynamic raw) {
    if (raw is! List) return const <CcChatRecord>[];
    return raw
        .whereType<Map>()
        .map((e) => CcChatRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}

/// Agent presence / typing state from `/chat/poll` and `/chat/status`.
enum CcAgentStatus { typing, online, sleeping, unknown }

CcAgentStatus _statusFromString(String? s) {
  switch (s) {
    case 'typing':
      return CcAgentStatus.typing;
    case 'online':
      return CcAgentStatus.online;
    case 'sleeping':
      return CcAgentStatus.sleeping;
    default:
      return CcAgentStatus.unknown;
  }
}

class CcChatStatus {
  final CcAgentStatus status;
  final bool isTyping;
  final String? since;
  final String? lastTurn;

  const CcChatStatus({
    required this.status,
    required this.isTyping,
    this.since,
    this.lastTurn,
  });

  static const CcChatStatus unknown = CcChatStatus(
    status: CcAgentStatus.unknown,
    isTyping: false,
  );

  factory CcChatStatus.fromJson(Map<String, dynamic> json) {
    return CcChatStatus(
      status: _statusFromString(json['status']?.toString()),
      isTyping: json['is_typing'] == true,
      since: json['since']?.toString(),
      lastTurn: json['last_turn']?.toString(),
    );
  }
}

/// Result of `GET /chat/poll`. The incremental fetch unit.
class CcPollResult {
  final String? now;
  final List<CcChatRecord> newRecords;

  /// Pass back as the next `since` cursor.
  final String? lastTs;
  final int count;
  final CcChatStatus status;

  /// Settings etag from the piggy-backed diff; null when unchanged/absent.
  final String? settingsEtag;
  final bool settingsChanged;
  final Map<String, dynamic>? settingsValues;

  const CcPollResult({
    this.now,
    required this.newRecords,
    this.lastTs,
    required this.count,
    required this.status,
    this.settingsEtag,
    this.settingsChanged = false,
    this.settingsValues,
  });

  factory CcPollResult.fromJson(Map<String, dynamic> json) {
    final chat = (json['chat'] is Map)
        ? Map<String, dynamic>.from(json['chat'])
        : const <String, dynamic>{};
    final statusRaw = (json['status'] is Map)
        ? Map<String, dynamic>.from(json['status'])
        : const <String, dynamic>{};
    final settings = (json['settings'] is Map)
        ? Map<String, dynamic>.from(json['settings'])
        : const <String, dynamic>{};

    final unchanged = settings['unchanged'] == true;

    return CcPollResult(
      now: json['now']?.toString(),
      newRecords: CcChatRecord.listFromJson(chat['new_records']),
      lastTs: chat['last_ts']?.toString(),
      count: (chat['count'] is int)
          ? chat['count'] as int
          : int.tryParse('${chat['count']}') ?? 0,
      status: CcChatStatus.fromJson(statusRaw),
      settingsEtag: settings['etag']?.toString(),
      settingsChanged: !unchanged && settings.isNotEmpty,
      settingsValues: (settings['values'] is Map)
          ? Map<String, dynamic>.from(settings['values'])
          : null,
    );
  }
}

/// One thinking chunk for a turn, from `GET /v1/thinking?turn_id=`.
class CcThinkingRecord {
  final String turnId;
  final String thinking;
  final String? timestamp;
  final String? sessionId;

  const CcThinkingRecord({
    required this.turnId,
    required this.thinking,
    this.timestamp,
    this.sessionId,
  });

  factory CcThinkingRecord.fromJson(Map<String, dynamic> json) {
    return CcThinkingRecord(
      turnId: json['turn_id']?.toString() ?? '',
      thinking: json['thinking']?.toString() ?? '',
      timestamp: json['timestamp']?.toString(),
      sessionId: json['session_id']?.toString(),
    );
  }

  static List<CcThinkingRecord> listFromJson(dynamic raw) {
    if (raw is! List) return const <CcThinkingRecord>[];
    return raw
        .whereType<Map>()
        .map((e) => CcThinkingRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}

/// Outcome of `POST /chat/send`. Distinguishes the important 502 case where the
/// message was stored to history but tmux injection failed (agent unreachable),
/// which must NOT be surfaced as a plain failure.
class CcSendResult {
  final bool ok;

  /// True on HTTP 502: stored to history but agent could not be reached.
  final bool agentUnreachable;

  /// The stored chat record, present on 200 and on 502.
  final CcChatRecord? record;

  final String? error;

  const CcSendResult({
    required this.ok,
    this.agentUnreachable = false,
    this.record,
    this.error,
  });
}

/// Persisted configuration for the CC bridge connection.
class CcBridgeConfig {
  /// Candidate server base URLs (e.g. the Cloudflare Tunnel subdomain + a LAN
  /// fallback). The first that answers `/health` is used. Stored without
  /// trailing slash.
  final List<String> endpoints;

  /// Shared secret sent as `X-Auth-Token` on every request. May be empty when
  /// the server runs with auth disabled.
  final String sharedSecret;

  /// tmux session to target; matches the server's `default_session` (e.g. 'cc').
  final String session;

  /// Poll interval in milliseconds.
  final int pollIntervalMs;

  /// Whether the server has `allow_remote_control=true` (terminal + slash).
  final bool remoteControlEnabled;

  /// Whether the bridge is turned on by the user.
  final bool enabled;

  const CcBridgeConfig({
    this.endpoints = const <String>[],
    this.sharedSecret = '',
    this.session = 'cc',
    this.pollIntervalMs = 2500,
    this.remoteControlEnabled = false,
    this.enabled = false,
  });

  static const CcBridgeConfig empty = CcBridgeConfig();

  bool get isConfigured => endpoints.isNotEmpty;

  CcBridgeConfig copyWith({
    List<String>? endpoints,
    String? sharedSecret,
    String? session,
    int? pollIntervalMs,
    bool? remoteControlEnabled,
    bool? enabled,
  }) {
    return CcBridgeConfig(
      endpoints: endpoints ?? this.endpoints,
      sharedSecret: sharedSecret ?? this.sharedSecret,
      session: session ?? this.session,
      pollIntervalMs: pollIntervalMs ?? this.pollIntervalMs,
      remoteControlEnabled: remoteControlEnabled ?? this.remoteControlEnabled,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'endpoints': endpoints,
        'shared_secret': sharedSecret,
        'session': session,
        'poll_interval_ms': pollIntervalMs,
        'remote_control_enabled': remoteControlEnabled,
        'enabled': enabled,
      };

  factory CcBridgeConfig.fromJson(Map<String, dynamic> json) {
    final eps = json['endpoints'];
    return CcBridgeConfig(
      endpoints: (eps is List)
          ? eps.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      sharedSecret: json['shared_secret']?.toString() ?? '',
      session: (json['session']?.toString().isNotEmpty ?? false)
          ? json['session'].toString()
          : 'cc',
      pollIntervalMs: (json['poll_interval_ms'] is int)
          ? json['poll_interval_ms'] as int
          : int.tryParse('${json['poll_interval_ms']}') ?? 2500,
      remoteControlEnabled: json['remote_control_enabled'] == true,
      enabled: json['enabled'] == true,
    );
  }
}

/// Snapshot of the tmux pane from `GET /tmux/capture` (terminal mirror).
///
/// The server may key the pane text under any of `content` / `text` / `output`
/// / `pane`; parsing is defensive and falls back across them.
class CcTmuxCapture {
  /// The captured pane text (monospace).
  final String content;
  final String? session;
  final int? lines;

  const CcTmuxCapture({required this.content, this.session, this.lines});

  factory CcTmuxCapture.fromJson(Map<String, dynamic> json) {
    final raw =
        json['content'] ?? json['text'] ?? json['output'] ?? json['pane'];
    return CcTmuxCapture(
      content: raw?.toString() ?? '',
      session: json['session']?.toString(),
      lines: (json['lines'] is int)
          ? json['lines'] as int
          : int.tryParse('${json['lines']}'),
    );
  }
}

/// One tmux/claude session entry from `GET /chain/sessions`.
class CcChainSession {
  final String sid;
  final bool active;

  const CcChainSession({required this.sid, required this.active});

  factory CcChainSession.fromJson(Map<String, dynamic> json) => CcChainSession(
        sid: json['sid']?.toString() ?? '',
        active: json['active'] == true,
      );
}

/// Result of `GET /chain/sessions`: the session list plus the active sid.
class CcChainSessions {
  final List<CcChainSession> sessions;
  final String? activeSid;

  const CcChainSessions({required this.sessions, this.activeSid});

  static const CcChainSessions empty =
      CcChainSessions(sessions: <CcChainSession>[]);

  factory CcChainSessions.fromJson(Map<String, dynamic> json) {
    final raw = json['sessions'];
    final list = (raw is List)
        ? raw
            .whereType<Map>()
            .map((e) => CcChainSession.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : const <CcChainSession>[];
    return CcChainSessions(
      sessions: list,
      activeSid: json['active_sid']?.toString(),
    );
  }
}
