// Workgroup (group chat) data models.
//
// These mirror the `/group/*` JSON contract exposed by the home CcCompanion
// `apns-server` (`push.py` + `group_chat.py`) — the same server the CC bridge
// talks to, same `X-Auth-Token` auth. Records are JSONL events keyed by an
// opaque `id` plus an ISO8601 `ts` poll cursor. Parsing is defensive because
// the server may omit fields and legacy records lack newer keys.

/// One workgroup member from `GET /group/roster`.
class GroupMember {
  /// Stable protocol id used by `sender_id` and mentions (e.g. 'amian').
  final String id;
  final String displayName;

  /// 'human' | 'agent'.
  final String kind;

  /// Initials / short label for the avatar bubble.
  final String avatar;

  /// UI color hint: orange / blue / green / purple / slate / neutral.
  final String color;

  /// Model label, display-only (e.g. 'Codex GPT-5.5'). Null for humans.
  final String? model;

  /// Whether this member can receive dispatch (@mention targets).
  final bool canReply;

  const GroupMember({
    required this.id,
    required this.displayName,
    required this.kind,
    this.avatar = '',
    this.color = 'neutral',
    this.model,
    this.canReply = false,
  });

  bool get isHuman => kind == 'human';
  bool get isAgent => kind == 'agent';

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id']?.toString() ?? '',
      displayName: json['display_name']?.toString() ??
          json['name']?.toString() ??
          json['id']?.toString() ??
          '',
      kind: json['kind']?.toString() ?? 'agent',
      avatar: json['avatar']?.toString() ?? '',
      color: json['color']?.toString() ?? 'neutral',
      model: (json['model']?.toString().isNotEmpty ?? false)
          ? json['model'].toString()
          : null,
      canReply: json['can_reply'] == true || json['canReply'] == true,
    );
  }

  static List<GroupMember> listFromJson(dynamic raw) {
    if (raw is! List) return const <GroupMember>[];
    return raw
        .whereType<Map>()
        .map((e) => GroupMember.fromJson(Map<String, dynamic>.from(e)))
        .where((m) => m.id.isNotEmpty)
        .toList(growable: false);
  }
}

/// Per-agent presence from the `status.agents.<id>` snapshot returned by
/// `/group/roster` and `/group/poll`.
class GroupAgentState {
  /// 'online' | 'offline' (derived from tmux session existence at home).
  final String state;
  final bool isTyping;
  final String? statusText;
  final String? lastSeen;

  const GroupAgentState({
    required this.state,
    this.isTyping = false,
    this.statusText,
    this.lastSeen,
  });

  bool get online => state == 'online';

  factory GroupAgentState.fromJson(Map<String, dynamic> json) {
    return GroupAgentState(
      state: json['state']?.toString() ?? 'offline',
      isTyping: json['is_typing'] == true,
      statusText: (json['status_text']?.toString().isNotEmpty ?? false)
          ? json['status_text'].toString()
          : null,
      lastSeen: json['last_seen']?.toString(),
    );
  }

  /// Parses the `{"agents": {id: {...}}}` snapshot; tolerates absent maps.
  static Map<String, GroupAgentState> mapFromStatus(dynamic raw) {
    if (raw is! Map) return const <String, GroupAgentState>{};
    final agents = raw['agents'];
    if (agents is! Map) return const <String, GroupAgentState>{};
    final out = <String, GroupAgentState>{};
    agents.forEach((k, v) {
      if (v is Map) {
        out[k.toString()] =
            GroupAgentState.fromJson(Map<String, dynamic>.from(v));
      }
    });
    return out;
  }
}

/// A single workgroup message from `/group/poll`, `/group/history`,
/// `/group/send`.
class GroupRecord {
  /// Opaque unique id (`grp_<ms>_<hex>`), used for dedupe.
  final String id;

  /// ISO8601 timestamp; also the poll cursor.
  final String ts;
  final String senderId;

  /// Display-only model label recorded at send time.
  final String? senderModel;
  final String text;
  final List<String> mentions;

  /// chat / task / decision / ship / block / progress.
  final String messageType;
  final String? taskId;
  final String? parentTaskId;
  final String? owner;
  final String? parentMsgId;
  final String? replyTo;
  final String? source;

  /// `/attachments/<name>` relative path (shared with the CC chat), if any.
  final String? attachmentUrl;
  final String? attachmentFilename;

  /// 'image' | 'file'.
  final String? attachmentType;

  const GroupRecord({
    required this.id,
    required this.ts,
    required this.senderId,
    this.senderModel,
    required this.text,
    this.mentions = const <String>[],
    this.messageType = 'chat',
    this.taskId,
    this.parentTaskId,
    this.owner,
    this.parentMsgId,
    this.replyTo,
    this.source,
    this.attachmentUrl,
    this.attachmentFilename,
    this.attachmentType,
  });

  bool get hasAttachment => (attachmentUrl ?? '').isNotEmpty;
  bool get isChat => messageType == 'chat';

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  factory GroupRecord.fromJson(Map<String, dynamic> json) {
    final rawMentions = json['mentions'];
    return GroupRecord(
      id: json['id']?.toString() ?? '',
      ts: json['ts']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderModel: _str(json['sender_model']),
      text: json['text']?.toString() ?? '',
      mentions: (rawMentions is List)
          ? rawMentions
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      messageType: (json['message_type']?.toString().isNotEmpty ?? false)
          ? json['message_type'].toString()
          : 'chat',
      taskId: _str(json['task_id']),
      parentTaskId: _str(json['parent_task_id']),
      owner: _str(json['owner']),
      parentMsgId: _str(json['parent_msg_id']),
      replyTo: _str(json['reply_to']),
      source: _str(json['source']),
      attachmentUrl: _str(json['attachment_url']),
      attachmentFilename: _str(json['attachment_filename']),
      attachmentType: _str(json['attachment_type']),
    );
  }

  static List<GroupRecord> listFromJson(dynamic raw) {
    if (raw is! List) return const <GroupRecord>[];
    return raw
        .whereType<Map>()
        .map((e) => GroupRecord.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.id.isNotEmpty)
        .toList(growable: false);
  }
}

/// Result of `GET /group/poll`.
class GroupPollResult {
  final List<GroupRecord> records;

  /// Pass back as the next `since`. Echoes the request cursor when empty.
  final String? lastTs;
  final Map<String, GroupAgentState> agentStates;

  const GroupPollResult({
    required this.records,
    this.lastTs,
    this.agentStates = const <String, GroupAgentState>{},
  });

  factory GroupPollResult.fromJson(Map<String, dynamic> json) {
    return GroupPollResult(
      records: GroupRecord.listFromJson(json['records']),
      lastTs: json['last_ts']?.toString(),
      agentStates: GroupAgentState.mapFromStatus(json['status']),
    );
  }
}

/// Result of `GET /group/roster`.
class GroupRosterResult {
  final List<GroupMember> members;
  final Map<String, GroupAgentState> agentStates;

  const GroupRosterResult({
    required this.members,
    this.agentStates = const <String, GroupAgentState>{},
  });

  factory GroupRosterResult.fromJson(Map<String, dynamic> json) {
    return GroupRosterResult(
      members: GroupMember.listFromJson(json['roster']),
      agentStates: GroupAgentState.mapFromStatus(json['status']),
    );
  }

  /// The human member's id, used as `sender_id` for everything the app sends.
  /// Falls back to 'amian' (the server default) when the roster is unusual.
  String get humanSenderId {
    for (final m in members) {
      if (m.isHuman) return m.id;
    }
    return 'amian';
  }
}

/// Outcome of `POST /group/send` / `POST /group/upload`. The server 429s
/// duplicates inside a 3s window ("dedupe storm guard") — surfaced as
/// [deduped] so the UI can drop the retry silently instead of erroring.
class GroupSendResult {
  final bool ok;
  final GroupRecord? record;
  final List<String> targets;
  final bool deduped;
  final String? error;

  const GroupSendResult({
    required this.ok,
    this.record,
    this.targets = const <String>[],
    this.deduped = false,
    this.error,
  });
}
