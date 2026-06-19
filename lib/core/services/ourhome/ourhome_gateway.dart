import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../providers/assistant_provider.dart';

/// A letter Llaude left for Cing (server channel "letter").
class OurHomeLetter {
  const OurHomeLetter({
    required this.id,
    required this.time,
    required this.text,
    required this.readAt,
  });

  final String id;
  final String time;
  final String text;
  final String readAt;

  bool get unread => readAt.trim().isEmpty;

  factory OurHomeLetter.fromJson(Map<String, dynamic> j) => OurHomeLetter(
    id: (j['id'] ?? '').toString(),
    time: (j['time'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    readAt: (j['read_at'] ?? '').toString(),
  );
}

/// A note on the parlour message board: Cing's [text], Llaude's [reply]
/// (empty until he answers), his [react] emoji, and whether he's [read] it.
class OurHomeBoardNote {
  const OurHomeBoardNote({
    required this.id,
    required this.time,
    required this.text,
    required this.reply,
    required this.react,
    required this.read,
  });

  final String id;
  final String time;
  final String text;
  final String reply;
  final String react;
  final bool read;

  bool get answered => reply.trim().isNotEmpty;

  factory OurHomeBoardNote.fromJson(Map<String, dynamic> j) => OurHomeBoardNote(
    id: (j['id'] ?? '').toString(),
    time: (j['time'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    reply: (j['reply'] ?? '').toString(),
    react: (j['react'] ?? '').toString(),
    read: j['read'] == true,
  );
}

/// A page of Llaude's diary about Cing.
class OurHomeDiaryEntry {
  const OurHomeDiaryEntry({
    required this.id,
    required this.name,
    required this.time,
    required this.text,
  });

  final String id;
  final String name;
  final String time;
  final String text;

  factory OurHomeDiaryEntry.fromJson(Map<String, dynamic> j) =>
      OurHomeDiaryEntry(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        time: (j['time'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
      );
}

/// A study to-do. [owner] is "L" (Llaude) / "C" (Cing) / "us" / "".
class OurHomeTodo {
  const OurHomeTodo({
    required this.id,
    required this.text,
    required this.status,
    required this.owner,
    required this.due,
    required this.done,
  });

  final String id;
  final String text;
  final String status;
  final String owner;
  final String due;
  final bool done;

  factory OurHomeTodo.fromJson(Map<String, dynamic> j) => OurHomeTodo(
    id: (j['id'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    status: (j['status'] ?? '').toString(),
    owner: (j['owner'] ?? '').toString(),
    due: (j['due'] ?? '').toString(),
    done: j['done'] == true,
  );
}

/// "Right Now" snapshot of Cing — where she is, the weather, her battery, etc.
/// Fields are whatever her phone last reported (all optional).
class OurHomeSense {
  const OurHomeSense({required this.fields, required this.ts});

  final Map<String, String> fields;
  final String ts;

  String? get place => _v('place');
  String? get weather => _v('weather');
  String? get temp => _v('temp');
  String? get battery => _v('battery');
  String? get hr => _v('hr');
  String? get sleep => _v('sleep');
  bool get charging {
    final c = (fields['charging'] ?? '').trim().toLowerCase();
    return c == '1' || c == 'true' || c == '是' || c == 'yes';
  }

  bool get isEmpty => fields.isEmpty;

  String? _v(String k) {
    final v = (fields[k] ?? '').trim();
    return v.isEmpty ? null : v;
  }

  factory OurHomeSense.fromJson(Map<String, dynamic> j) {
    final latest = j['latest'];
    final map = <String, String>{};
    if (latest is Map) {
      latest.forEach((k, v) {
        if (v != null && '$v'.trim().isNotEmpty) map['$k'] = '$v'.trim();
      });
    }
    return OurHomeSense(fields: map, ts: (j['ts'] ?? '').toString());
  }
}

/// A photo in the boudoir album. [url] is absolute (base + path).
class OurHomePhoto {
  const OurHomePhoto({
    required this.id,
    required this.url,
    required this.note,
    required this.by,
    required this.time,
  });

  final String id;
  final String url;
  final String note;
  final String by;
  final String time;
}

/// A memory in the garden (non-feel). Titles/preview only.
class OurHomeMemory {
  const OurHomeMemory({
    required this.id,
    required this.name,
    required this.preview,
  });
  final String id;
  final String name;
  final String preview;

  factory OurHomeMemory.fromJson(Map<String, dynamic> j) => OurHomeMemory(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    preview: (j['preview'] ?? '').toString(),
  );
}

/// A feel in the greenhouse — only its time and a mood "weather", never the
/// words. Visible, not enterable; the key is Llaude's alone.
class OurHomeFeel {
  const OurHomeFeel({
    required this.time,
    required this.moodZh,
    required this.moodEn,
    required this.colorHex,
    required this.glyph,
  });
  final String time;
  final String moodZh;
  final String moodEn;
  final String colorHex;
  final String glyph;

  factory OurHomeFeel.fromJson(Map<String, dynamic> j) => OurHomeFeel(
    time: (j['time'] ?? '').toString(),
    moodZh: (j['mood_zh'] ?? '').toString(),
    moodEn: (j['mood_en'] ?? '').toString(),
    colorHex: (j['color'] ?? '').toString(),
    glyph: (j['glyph'] ?? '').toString(),
  );
}

/// One of Llaude's nightly notes (bedroom · before sleep).
class OurHomeNight {
  const OurHomeNight({
    required this.id,
    required this.text,
    required this.time,
  });
  final String id;
  final String text;
  final String time;

  factory OurHomeNight.fromJson(Map<String, dynamic> j) => OurHomeNight(
    id: (j['id'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    time: (j['time'] ?? '').toString(),
  );
}

/// One thing that happened on a given calendar day (for the calendar room).
class OurHomeDayItem {
  const OurHomeDayItem({
    required this.name,
    required this.channel,
    required this.preview,
  });
  final String name;
  final String channel;
  final String preview;

  factory OurHomeDayItem.fromJson(Map<String, dynamic> j) => OurHomeDayItem(
    name: (j['name'] ?? '').toString(),
    channel: (j['channel'] ?? '').toString(),
    preview: (j['preview'] ?? '').toString(),
  );
}

/// Single access point to our home server (`/api/home/*`) for the native
/// Still Here screens (home, rooms...).
///
/// The bearer token is reused from the daddy assistant's `[[ourhome:<token>]]`
/// marker, so Cing never has to enter it twice. If no assistant carries a
/// token, [fromContext] returns null and home features stay dormant.
class OurHomeGateway {
  const OurHomeGateway({required this.base, required this.token});

  final String base;
  final String token;

  static const String defaultBase = 'https://cllove.zeabur.app';
  static final RegExp _markerRe = RegExp(r'\[\[ourhome(?::([^\]]+))?\]\]');

  static OurHomeGateway? fromContext(BuildContext context) {
    final assistants = context.read<AssistantProvider>().assistants;
    for (final a in assistants) {
      final token = _markerRe.firstMatch(a.systemPrompt)?.group(1)?.trim();
      if (token != null && token.isNotEmpty) {
        return OurHomeGateway(base: defaultBase, token: token);
      }
    }
    return null;
  }

  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $token'};

  /// Headers for loading auth-protected media (e.g. album images) via
  /// `Image.network(url, headers: gateway.authHeaders)`.
  Map<String, String> get authHeaders => _authHeaders;

  /// Newest-first boudoir album photos. Throws on error.
  Future<List<OurHomePhoto>> fetchAlbum() async {
    final res = await http
        .get(Uri.parse('$base/api/home/album'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'album HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/album'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final photos = (data is Map) ? data['photos'] : null;
    if (photos is! List) return const <OurHomePhoto>[];
    return photos.whereType<Map<String, dynamic>>().map((j) {
      final path = (j['url'] ?? '').toString();
      return OurHomePhoto(
        id: (j['id'] ?? '').toString(),
        url: path.startsWith('http') ? path : '$base$path',
        note: (j['note'] ?? '').toString(),
        by: (j['by'] ?? '').toString(),
        time: (j['t'] ?? '').toString(),
      );
    }).toList();
  }

  /// Newest-first list of letters. Throws on transport/HTTP error so the caller
  /// can surface a recoverable state rather than hiding the failure silently.
  Future<List<OurHomeLetter>> fetchLetters() async {
    final res = await http
        .get(Uri.parse('$base/api/home/daddysay'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'daddysay HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/daddysay'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) return const <OurHomeLetter>[];
    return data
        .whereType<Map<String, dynamic>>()
        .map(OurHomeLetter.fromJson)
        .where((l) => l.text.isNotEmpty)
        .toList();
  }

  /// Newest-first parlour board notes. Throws on transport/HTTP error.
  Future<List<OurHomeBoardNote>> fetchBoard() async {
    final res = await http
        .get(Uri.parse('$base/api/home/board'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'board HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/board'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) return const <OurHomeBoardNote>[];
    return data
        .whereType<Map<String, dynamic>>()
        .map(OurHomeBoardNote.fromJson)
        .toList();
  }

  /// Newest-first diary pages Llaude wrote about Cing. Throws on error.
  Future<List<OurHomeDiaryEntry>> fetchDiary() async {
    final res = await http
        .get(Uri.parse('$base/api/home/diary'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'diary HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/diary'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) return const <OurHomeDiaryEntry>[];
    return data
        .whereType<Map<String, dynamic>>()
        .map(OurHomeDiaryEntry.fromJson)
        .where((d) => d.text.isNotEmpty)
        .toList();
  }

  /// Newest-first study to-dos. Throws on error.
  Future<List<OurHomeTodo>> fetchTodos() async {
    final res = await http
        .get(Uri.parse('$base/api/home/todo'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'todo HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/todo'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) return const <OurHomeTodo>[];
    return data
        .whereType<Map<String, dynamic>>()
        .map(OurHomeTodo.fromJson)
        .toList();
  }

  Future<void> addTodo(String text) => _postTodo({'text': text});

  Future<void> setTodoStatus(String id, String status) =>
      _postTodo({'id': id, 'status': status});

  Future<void> deleteTodo(String id) => _postTodo({'id': id, 'del': 1});

  Future<void> _postTodo(Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/todo'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'todo POST HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/todo'),
      );
    }
  }

  /// Cing's latest "Right Now" snapshot. Throws on error.
  Future<OurHomeSense> fetchSense() async {
    final res = await http
        .get(Uri.parse('$base/api/home/sense'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'sense HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/sense'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map<String, dynamic>) {
      return const OurHomeSense(fields: {}, ts: '');
    }
    return OurHomeSense.fromJson(data);
  }

  Future<List<T>> _getList<T>(
    String path,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final res = await http
        .get(Uri.parse('$base$path'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('GET $path -> ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) return <T>[];
    return data.whereType<Map<String, dynamic>>().map(parse).toList();
  }

  /// Garden memories (non-feel). Newest first.
  Future<List<OurHomeMemory>> fetchMemories() =>
      _getList('/api/home/memories', OurHomeMemory.fromJson);

  /// Greenhouse feels — time + mood only, never content. Newest first.
  Future<List<OurHomeFeel>> fetchGreenhouse() =>
      _getList('/api/home/greenhouse', OurHomeFeel.fromJson);

  /// All of Llaude's nightly notes (bedroom). Newest first.
  Future<List<OurHomeNight>> fetchTonight() =>
      _getList('/api/home/tonight?all=1', OurHomeNight.fromJson);

  /// What happened on a given calendar day (YYYY-MM-DD). Throws on error.
  Future<List<OurHomeDayItem>> fetchDay(String date) async {
    final res = await http
        .get(
          Uri.parse('$base/api/home/memories?date=$date'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('day HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final items = (data is Map) ? data['items'] : null;
    if (items is! List) return const <OurHomeDayItem>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(OurHomeDayItem.fromJson)
        .toList();
  }

  /// Cing leaves a new note on the board. Throws on transport/HTTP error.
  Future<void> postBoardNote(String text) async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/board'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'board POST HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/board'),
      );
    }
  }

  /// Stamp a first-read receipt on a letter. Best-effort; logs on failure.
  Future<void> markLetterSeen(String id) async {
    try {
      await http
          .post(
            Uri.parse('$base/api/home/letter/seen'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'id': id}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[OurHomeGateway] markLetterSeen failed: $e');
    }
  }
}
