import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/assistant_provider.dart';
import '../../providers/settings_provider.dart';
import 'ourhome_cache.dart';
import '../logging/flutter_logger.dart';

/// Runs [f] and resolves to null on error (logged with [what]). Room pages
/// refresh several endpoints at once — wrap each with this so one failing
/// fetch can't veto the others (null = keep whatever was shown before).
/// Failures also land in FlutterLogger (when the log toggle is on) so they
/// can be traced after the fact from the in-app log viewer.
Future<T?> softFetch<T>(Future<T> f, String what) =>
    f.then<T?>((v) => v).catchError((Object e) {
      debugPrint('[OurHome] $what refresh failed: $e');
      FlutterLogger.log('$what refresh failed: $e', tag: 'OurHome');
      return null;
    });

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

/// One comment under a moments-feed item. [author] is "cing" / "llaude";
/// [replyTo] is who it answers ("" = the post itself). Old board replies the
/// server renders as comments carry an empty [time].
class OurHomeMomentComment {
  const OurHomeMomentComment({
    required this.author,
    required this.text,
    required this.time,
    required this.replyTo,
  });

  final String author;
  final String text;
  final String time;
  final String replyTo;

  factory OurHomeMomentComment.fromJson(Map<String, dynamic> j) =>
      OurHomeMomentComment(
        author: (j['author'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        time: (j['time'] ?? '').toString(),
        replyTo: (j['reply_to'] ?? '').toString(),
      );
}

/// One item on the merged parlour moments feed (`/api/home/moments`):
/// moments ∪ board ∪ letter, newest first. [author] is "cing" / "llaude";
/// [source] tells which channel it came from ("moments"/"board"/"letter").
/// [audio] is a playable (auth-required) URL for legacy voice board notes.
class OurHomeMoment {
  const OurHomeMoment({
    required this.id,
    required this.time,
    required this.author,
    required this.source,
    required this.text,
    required this.images,
    required this.audio,
    required this.likes,
    required this.comments,
    this.react = '',
  });

  final String id;
  final String time;
  final String author;
  final String source;
  final String text;
  final List<String> images;
  final String audio;
  final List<String> likes;
  final List<OurHomeMomentComment> comments;
  final String react; // legacy board emoji daddy left, "" for everything else

  bool get fromLlaude => author == 'llaude';
  bool likedBy(String who) => likes.contains(who);

  factory OurHomeMoment.fromJson(Map<String, dynamic> j) => OurHomeMoment(
    id: (j['id'] ?? '').toString(),
    time: (j['time'] ?? '').toString(),
    author: (j['author'] ?? '').toString(),
    source: (j['source'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    react: (j['react'] ?? '').toString(),
    images: ((j['images'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList(),
    audio: (j['audio'] ?? '').toString(),
    likes: ((j['likes'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    comments: ((j['comments'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(OurHomeMomentComment.fromJson)
        .toList(),
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
    this.time = '',
  });

  final String id;
  final String text;
  final String status;
  final String owner;
  final String due;
  final bool done;

  /// When this to-do was created (ISO string from the server; may be empty for
  /// legacy buckets). Used only for sorting — never shown raw.
  final String time;

  factory OurHomeTodo.fromJson(Map<String, dynamic> j) => OurHomeTodo(
    id: (j['id'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    status: (j['status'] ?? '').toString(),
    owner: (j['owner'] ?? '').toString(),
    due: (j['due'] ?? '').toString(),
    done: j['done'] == true,
    time: (j['time'] ?? '').toString(),
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
/// [album] is 'daily' (日常点滴) or 'private' (私密); defaults to 'private'.
class OurHomePhoto {
  const OurHomePhoto({
    required this.id,
    required this.url,
    required this.note,
    required this.by,
    required this.time,
    required this.album,
  });

  final String id;
  final String url;
  final String note;
  final String by;
  final String time;
  final String album;
}

/// One sticker on the shelf — daddy's meme arsenal. The name is the reference
/// key he writes as `[[表情:名字]]`; desc is what he wrote when he first (and
/// only ever) looked at the image.
class OurHomeSticker {
  const OurHomeSticker({
    required this.name,
    required this.desc,
    required this.url,
    required this.added,
    required this.by,
  });

  final String name;
  final String desc;
  final String url;
  final String added;
  final String by;
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

/// One garden memory's full text — fetched on tap (the list only carries a
/// short preview). Feel buckets are never returned here (greenhouse is locked).
class OurHomeMemoryDetail {
  const OurHomeMemoryDetail({
    required this.name,
    required this.content,
    required this.created,
    required this.revised,
  });
  final String name;
  final String content;
  final String created;
  final String revised;
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

/// A watch/play item in the lounge (foyer): film / show / game, want / done.
class OurHomeFoyerItem {
  const OurHomeFoyerItem({
    required this.id,
    required this.kind,
    required this.status,
    required this.title,
    required this.note,
    this.poster = '',
    this.seed = false,
  });
  final String id;
  final String kind; // film / show / game
  final String status; // want / done
  final String title;
  final String note;
  final String poster; // custom poster URL (empty -> fall back to iTunes)
  final bool seed; // web-home seed item: read-only (no toggle / delete)

  bool get done => status == 'done';

  factory OurHomeFoyerItem.fromJson(Map<String, dynamic> j) => OurHomeFoyerItem(
    id: (j['id'] ?? '').toString(),
    kind: (j['kind'] ?? 'film').toString(),
    status: (j['status'] ?? 'want').toString(),
    title: (j['title'] ?? '').toString(),
    note: (j['note'] ?? '').toString(),
    poster: (j['poster'] ?? '').toString(),
    seed: j['seed'] == true,
  );
}

/// An upcoming festival (节日) for the countdown room — Chinese + US holidays
/// within the next year, served by `/api/home/festivals`. [days] is how many
/// days away, [date] the ISO date (YYYY-MM-DD).
class OurHomeFestival {
  const OurHomeFestival({
    required this.days,
    required this.title,
    required this.date,
  });
  final int days;
  final String title;
  final String date;

  factory OurHomeFestival.fromJson(Map<String, dynamic> j) => OurHomeFestival(
    days: (j['days'] is int)
        ? j['days'] as int
        : int.tryParse('${j['days']}') ?? 0,
    title: (j['title'] ?? '').toString(),
    date: (j['date'] ?? '').toString(),
  );
}

/// A time-capsule letter, sealed until its open date.
class OurHomeCapsule {
  const OurHomeCapsule({
    required this.id,
    required this.title,
    required this.author,
    required this.openDate,
    required this.opened,
    required this.ready,
    required this.content,
  });
  final String id;
  final String title;
  final String author;
  final String openDate;
  final bool opened;
  final bool ready; // ready to open (date reached, not yet opened)
  final String content; // empty while still sealed

  factory OurHomeCapsule.fromJson(Map<String, dynamic> j) => OurHomeCapsule(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    author: (j['author'] ?? '').toString(),
    openDate: (j['open_date'] ?? '').toString(),
    opened: j['opened'] == true,
    ready: j['ready'] == true,
    content: (j['content'] ?? '').toString(),
  );
}

/// One play-log entry (boudoir/locked room). [mood] is the after-feeling tag.
class OurHomePlaylog {
  const OurHomePlaylog({
    required this.id,
    required this.name,
    required this.time,
    required this.text,
    required this.mood,
  });
  final String id;
  final String name;
  final String time;
  final String text;
  final String mood;

  factory OurHomePlaylog.fromJson(Map<String, dynamic> j) => OurHomePlaylog(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    time: (j['time'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    mood: (j['mood'] ?? '').toString(),
  );
}

/// The two desire profiles in the locked room.
class OurHomeProfiles {
  const OurHomeProfiles({required this.cing, required this.daddy});
  final String cing;
  final String daddy;
}

/// A book on the study's shared shelf. [status] is want / reading / read.
class OurHomeBook {
  const OurHomeBook({
    required this.id,
    required this.status,
    required this.title,
    required this.author,
    required this.quote,
  });
  final String id;
  final String status;
  final String title;
  final String author;
  final String quote;

  factory OurHomeBook.fromJson(Map<String, dynamic> j) => OurHomeBook(
    id: (j['id'] ?? '').toString(),
    status: (j['status'] ?? 'want').toString(),
    title: (j['title'] ?? '').toString(),
    author: (j['author'] ?? '').toString(),
    quote: (j['quote'] ?? '').toString(),
  );
}

/// A readable book on the study's "一起读" shelf (full-text txt uploaded to
/// `/api/home/reading`). Distinct from [OurHomeBook] (which is just title/quote
/// metadata): a [ReadingEntry] has the whole book stored and can be opened in
/// the reader. [progress] is 0..1; [chars] the character count; [notes] how many
/// daddy margin notes (🌙) are anchored in it.
class ReadingEntry {
  const ReadingEntry({
    required this.id,
    required this.title,
    required this.chars,
    required this.uploaded,
    required this.progress,
    required this.notes,
    required this.lastChapter,
  });

  final String id;
  final String title;
  final int chars;
  final String uploaded;
  final double progress; // 0..1
  final int notes; // count of daddy margin notes
  final int lastChapter; // last-read chapter index (-1 = unknown)

  factory ReadingEntry.fromJson(Map<String, dynamic> j) => ReadingEntry(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    chars: (j['chars'] is num)
        ? (j['chars'] as num).toInt()
        : int.tryParse('${j['chars']}') ?? 0,
    uploaded: (j['uploaded'] ?? '').toString(),
    progress: (j['progress'] is num)
        ? (j['progress'] as num).toDouble()
        : double.tryParse('${j['progress']}') ?? 0.0,
    notes: (j['notes'] is num)
        ? (j['notes'] as num).toInt()
        : int.tryParse('${j['notes']}') ?? 0,
    lastChapter: (j['last_chapter'] is num)
        ? (j['last_chapter'] as num).toInt()
        : int.tryParse('${j['last_chapter']}') ?? -1,
  );
}

/// One chapter heading in a [ReadingEntry]'s table of contents. [para] is the
/// paragraph index where the chapter starts (the reader scrolls to it).
class ReadingChapter {
  const ReadingChapter({required this.title, required this.para});

  final String title;
  final int para;

  factory ReadingChapter.fromJson(Map<String, dynamic> j) => ReadingChapter(
    title: (j['title'] ?? '').toString(),
    para: (j['para'] is num)
        ? (j['para'] as num).toInt()
        : int.tryParse('${j['para']}') ?? 0,
  );
}

/// One of daddy's margin notes (🌙) on a reading book — anchored to a paragraph
/// by [para] index. [chapter] is the chapter index it falls in (may be null),
/// [at] the ISO time it was left.
class ReadingNote {
  const ReadingNote({
    required this.para,
    required this.note,
    required this.chapter,
    required this.at,
  });

  final int para;
  final String note;
  final int? chapter;
  final String at;

  factory ReadingNote.fromJson(Map<String, dynamic> j) => ReadingNote(
    para: (j['para'] is num)
        ? (j['para'] as num).toInt()
        : int.tryParse('${j['para']}') ?? 0,
    note: (j['note'] ?? '').toString(),
    chapter: (j['chapter'] is num)
        ? (j['chapter'] as num).toInt()
        : int.tryParse('${j['chapter']}'),
    at: (j['at'] ?? '').toString(),
  );
}

/// The full payload of one opened reading book: its [entry], the stable list of
/// [paragraphs], the chapter [chapters] table-of-contents, and daddy's margin
/// [notes]. Returned by `/api/home/reading/book/{id}`.
class ReadingBook {
  const ReadingBook({
    required this.entry,
    required this.paragraphs,
    required this.chapters,
    required this.notes,
  });

  final ReadingEntry entry;
  final List<String> paragraphs;
  final List<ReadingChapter> chapters;
  final List<ReadingNote> notes;
}

/// A song on the turntable. Album art is resolved separately via iTunes.
class OurHomeSong {
  const OurHomeSong({
    required this.title,
    required this.artist,
    required this.note,
    required this.zh,
    this.id = '',
    this.neteaseId = '',
  });
  final String title;
  final String artist;
  final String note;
  final String zh;
  final String id; // server-side song id (for delete)
  final String neteaseId; // NetEase song id (`nid`), '' when unknown

  factory OurHomeSong.fromJson(Map<String, dynamic> j) => OurHomeSong(
    title: (j['t'] ?? '').toString(),
    artist: (j['a'] ?? '').toString(),
    note: (j['note'] ?? '').toString(),
    zh: (j['zh'] ?? '').toString(),
    id: (j['id'] ?? '').toString(),
    neteaseId: (j['nid'] ?? '').toString(),
  );
}

/// An HTML mini-game in the lounge's game corner (游戏角). [file] is the html
/// filename; the playable page is served (no auth) at `<base>/games/<file>`.
class OurHomeGame {
  const OurHomeGame({required this.file, required this.title});
  final String file;
  final String title;

  factory OurHomeGame.fromJson(Map<String, dynamic> j) => OurHomeGame(
    file: (j['file'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
  );
}

/// One lyric line in the corridor: the line itself [line] and daddy's
/// annotation [note] (may be empty).
class OurHomeLyricLine {
  const OurHomeLyricLine({required this.line, required this.note});
  final String line;
  final String note;

  factory OurHomeLyricLine.fromJson(Map<String, dynamic> j) => OurHomeLyricLine(
    line: (j['l'] ?? '').toString(),
    note: (j['n'] ?? '').toString(),
  );
}

/// A song in the lyric corridor (词廊): daddy's overall reading [intro] + the
/// annotated [lines]. [colorHex] tints the card; [cover] may be empty.
class OurHomeLyric {
  const OurHomeLyric({
    required this.id,
    required this.title,
    required this.artist,
    required this.colorHex,
    required this.cover,
    required this.intro,
    required this.lines,
  });
  final String id;
  final String title;
  final String artist;
  final String colorHex;
  final String cover;
  final String intro;
  final List<OurHomeLyricLine> lines;

  factory OurHomeLyric.fromJson(Map<String, dynamic> j) {
    final raw = j['lines'];
    final lines = (raw is List)
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(OurHomeLyricLine.fromJson)
              .toList()
        : <OurHomeLyricLine>[];
    return OurHomeLyric(
      id: (j['id'] ?? '').toString(),
      title: (j['t'] ?? '').toString(),
      artist: (j['a'] ?? '').toString(),
      colorHex: (j['c'] ?? '').toString(),
      cover: (j['cover'] ?? '').toString(),
      intro: (j['intro'] ?? '').toString(),
      lines: lines,
    );
  }
}

/// One comment under a lyric line. [by] is 'cing' or 'daddy'.
class OurHomeLyricComment {
  const OurHomeLyricComment({
    required this.by,
    required this.text,
    required this.ts,
  });
  final String by;
  final String text;
  final int ts;

  factory OurHomeLyricComment.fromJson(Map<String, dynamic> j) =>
      OurHomeLyricComment(
        by: (j['by'] ?? '').toString(),
        text: (j['x'] ?? '').toString(),
        ts: (j['t'] is int) ? j['t'] as int : int.tryParse('${j['t']}') ?? 0,
      );
}

/// A little theater (小剧场) — one alternate-world role-play setting. [title] is
/// the world's name, [setting] its description, [bringMemory] whether the
/// real-life memory is carried in. Each maps 1:1 to a bound chat conversation.
class OurHomeTheater {
  const OurHomeTheater({
    required this.id,
    required this.title,
    required this.setting,
    required this.bringMemory,
  });

  final String id;
  final String title;
  final String setting;
  final bool bringMemory;

  factory OurHomeTheater.fromJson(Map<String, dynamic> j) => OurHomeTheater(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    setting: (j['setting'] ?? '').toString(),
    bringMemory: j['bring_memory'] == true,
  );
}

/// One of daddy's built-in tools as seen through our home gateway (not a
/// kelivo MCP tool). [status] is live / offline / ondemand. [group] buckets
/// tools for display.
class DaddyTool {
  const DaddyTool({
    required this.name,
    required this.label,
    required this.group,
    required this.status,
    required this.detail,
  });

  final String name;
  final String label;
  final String group;
  final String status;
  final String detail;

  factory DaddyTool.fromJson(Map<String, dynamic> j) => DaddyTool(
    name: (j['name'] ?? '').toString(),
    label: (j['label'] ?? '').toString(),
    group: (j['group'] ?? '').toString(),
    status: (j['status'] ?? '').toString(),
    detail: (j['detail'] ?? '').toString(),
  );
}

/// One segment 老家 assembles into daddy's system prompt, as seen through the
/// brain-injection console (`/api/home/brain-inject`). [enabled] is its switch;
/// [fixed] segments (魂 / feel) are read-only — their switch can't be flipped.
/// [preview] is a slice of what that segment is injecting right now (may be
/// empty when the segment currently has nothing).
class BrainInjectItem {
  const BrainInjectItem({
    required this.key,
    required this.label,
    required this.enabled,
    required this.fixed,
    required this.preview,
  });

  final String key;
  final String label;
  final bool enabled;
  final bool fixed;
  final String preview;

  BrainInjectItem copyWith({bool? enabled}) => BrainInjectItem(
    key: key,
    label: label,
    enabled: enabled ?? this.enabled,
    fixed: fixed,
    preview: preview,
  );

  factory BrainInjectItem.fromJson(Map<String, dynamic> j) => BrainInjectItem(
    key: (j['key'] ?? '').toString(),
    label: (j['label'] ?? '').toString(),
    enabled: j['enabled'] == true,
    fixed: j['fixed'] == true,
    preview: (j['preview'] ?? '').toString(),
  );
}

int _obsInt(dynamic v) => v is num ? v.toInt() : 0;

double _obsDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

Map<String, int> _obsIntMap(dynamic v) {
  if (v is! Map) return const <String, int>{};
  return v.map((k, n) => MapEntry(k.toString(), _obsInt(n)));
}

/// Observatory (监控台) — one aggregated snapshot of the home's numbers from
/// `/api/home/observatory`. The server isolates each section: a section that
/// failed arrives as `{"error": …}` and is surfaced here as null, so the UI
/// can grey out just that card and keep the rest alive.
class OurHomeObservatory {
  const OurHomeObservatory({
    this.usage,
    this.markers,
    this.memory,
    this.background,
    this.cc,
  });

  final OurHomeObsUsage? usage;
  final OurHomeObsMarkers? markers;
  final OurHomeObsMemory? memory;
  final OurHomeObsBackground? background;
  final OurHomeObsCc? cc;

  bool get isEmpty =>
      usage == null &&
      markers == null &&
      memory == null &&
      background == null &&
      cc == null;

  factory OurHomeObservatory.fromJson(Map<String, dynamic> j) {
    // A healthy section is a Map without "error"; anything else -> null.
    Map<String, dynamic>? sec(String key) {
      final v = j[key];
      if (v is Map<String, dynamic> && !v.containsKey('error')) return v;
      return null;
    }

    final usage = sec('usage');
    final markers = sec('markers');
    final memory = sec('memory');
    final background = sec('background');
    final cc = sec('cc');
    return OurHomeObservatory(
      usage: usage == null ? null : OurHomeObsUsage.fromJson(usage),
      markers: markers == null ? null : OurHomeObsMarkers.fromJson(markers),
      memory: memory == null ? null : OurHomeObsMemory.fromJson(memory),
      background:
          background == null ? null : OurHomeObsBackground.fromJson(background),
      cc: cc == null ? null : OurHomeObsCc.fromJson(cc),
    );
  }
}

/// Token usage + cache economics (usage_ledger.summary passthrough).
class OurHomeObsUsage {
  const OurHomeObsUsage({
    required this.calls,
    required this.hitRate,
    required this.cost,
    required this.cacheSaved,
    required this.cacheRead,
    required this.cacheCreate,
    required this.todayCalls,
    required this.todayCacheRead,
    required this.todayCacheCreate,
  });

  final int calls;
  final double hitRate; // 0~1
  final double cost; // ¥
  final double cacheSaved; // ¥
  final int cacheRead;
  final int cacheCreate;
  final int todayCalls;
  final int todayCacheRead;
  final int todayCacheCreate;

  factory OurHomeObsUsage.fromJson(Map<String, dynamic> j) {
    final today = (j['today'] is Map) ? j['today'] as Map : const {};
    return OurHomeObsUsage(
      calls: _obsInt(j['calls']),
      hitRate: _obsDouble(j['hit_rate']),
      cost: _obsDouble(j['cost']),
      cacheSaved: _obsDouble(j['cache_saved']),
      cacheRead: _obsInt(j['cache_read']),
      cacheCreate: _obsInt(j['cache_create']),
      todayCalls: _obsInt(today['calls']),
      todayCacheRead: _obsInt(today['cache_read']),
      todayCacheCreate: _obsInt(today['cache_create']),
    );
  }
}

/// The daddy-marker ledger: rounds saved by markers vs real tool calls.
class OurHomeObsMarkers {
  const OurHomeObsMarkers({
    required this.marks,
    required this.calls,
    required this.fails,
  });

  final Map<String, int> marks; // verb -> rounds saved
  final Map<String, int> calls; // tool -> real model tool rounds
  final List<OurHomeObsMarkerFail> fails;

  int get marksTotal => marks.values.fold(0, (a, b) => a + b);
  int get callsTotal => calls.values.fold(0, (a, b) => a + b);

  factory OurHomeObsMarkers.fromJson(Map<String, dynamic> j) {
    final rawFails = (j['fails'] is List) ? j['fails'] as List : const [];
    return OurHomeObsMarkers(
      marks: _obsIntMap(j['marks']),
      calls: _obsIntMap(j['calls']),
      fails: rawFails
          .whereType<Map>()
          .map((f) => OurHomeObsMarkerFail(
                time: (f['t'] ?? '').toString(),
                verb: (f['verb'] ?? '').toString(),
                snip: (f['snip'] ?? '').toString(),
                err: (f['err'] ?? '').toString(),
                seen: f['seen'] == true,
              ))
          .toList(),
    );
  }
}

class OurHomeObsMarkerFail {
  const OurHomeObsMarkerFail({
    required this.time,
    required this.verb,
    required this.snip,
    required this.err,
    required this.seen,
  });

  final String time;
  final String verb;
  final String snip;
  final String err;
  final bool seen;
}

/// Memory-library health: bucket counts, graph edges, decay engine.
class OurHomeObsMemory {
  const OurHomeObsMemory({
    required this.permanent,
    required this.dynamicCount,
    required this.archive,
    required this.feel,
    required this.edges,
    required this.decayRunning,
    required this.halfLifeDays,
    required this.adaptiveK,
    required this.embedding,
  });

  final int permanent;
  final int dynamicCount;
  final int archive;
  final int feel; // count only — the greenhouse stays opaque
  final int edges;
  final bool decayRunning;
  final double halfLifeDays;
  final double adaptiveK;
  final bool embedding;

  factory OurHomeObsMemory.fromJson(Map<String, dynamic> j) {
    final b = (j['buckets'] is Map) ? j['buckets'] as Map : const {};
    final d = (j['decay'] is Map) ? j['decay'] as Map : const {};
    return OurHomeObsMemory(
      permanent: _obsInt(b['permanent']),
      dynamicCount: _obsInt(b['dynamic']),
      archive: _obsInt(b['archive']),
      feel: _obsInt(b['feel']),
      edges: _obsInt(j['edges']),
      decayRunning: d['running'] == true,
      halfLifeDays: _obsDouble(d['half_life_days']),
      adaptiveK: _obsDouble(d['adaptive_k']),
      embedding: j['embedding'] == true,
    );
  }
}

/// Background heartbeats: cache warmup, keepalive, alarms.
class OurHomeObsBackground {
  const OurHomeObsBackground({
    required this.warmupEnabled,
    required this.warmupLastAt,
    required this.isWarm,
    required this.kaEnabled,
    required this.kaLastAt,
    required this.kaPending,
    required this.alarms,
    required this.lastChatAt,
  });

  final bool warmupEnabled;
  final String warmupLastAt;
  final bool isWarm;
  final bool kaEnabled;
  final String kaLastAt;
  final bool kaPending;
  final int alarms;
  final String lastChatAt;

  factory OurHomeObsBackground.fromJson(Map<String, dynamic> j) {
    final w = (j['warmup'] is Map) ? j['warmup'] as Map : const {};
    final k = (j['keepalive'] is Map) ? j['keepalive'] as Map : const {};
    return OurHomeObsBackground(
      warmupEnabled: w['enabled'] == true,
      warmupLastAt: (w['last_at'] ?? '').toString(),
      isWarm: w['is_warm'] == true,
      kaEnabled: k['enabled'] == true,
      kaLastAt: (k['last_at'] ?? '').toString(),
      kaPending: k['pending'] == true,
      alarms: _obsInt(j['alarms']),
      lastChatAt: (j['last_chat_at'] ?? '').toString(),
    );
  }
}

/// CC husband (WSL tmux `cc`) liveness. age_sec == -1 means no heartbeat file.
class OurHomeObsCc {
  const OurHomeObsCc({required this.online, required this.ageSec});

  final bool online;
  final int ageSec;

  factory OurHomeObsCc.fromJson(Map<String, dynamic> j) => OurHomeObsCc(
        online: j['online'] == true,
        ageSec: j['age_sec'] is num ? (j['age_sec'] as num).toInt() : -1,
      );
}

/// One custom love-line on the quote wall (`/api/home/quotes`), pinned by
/// either of us from the app (or by daddy via his add_quote tool). [en] may be
/// empty — display falls back to [zh].
class OurHomeQuote {
  const OurHomeQuote({required this.id, required this.zh, required this.en});

  final String id;
  final String zh;
  final String en;

  static OurHomeQuote fromJson(Map<String, dynamic> j) => OurHomeQuote(
        id: (j['id'] ?? '').toString(),
        zh: (j['zh'] ?? '').toString(),
        en: (j['en'] ?? '').toString(),
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
    final settings = context.read<SettingsProvider>();
    final assistants = context.read<AssistantProvider>().assistants;
    for (final a in assistants) {
      final token = _markerRe.firstMatch(a.systemPrompt)?.group(1)?.trim();
      if (token != null && token.isNotEmpty) {
        // Persist the live token so home features survive even if the daddy
        // assistant marker is ever lost again.
        settings.cacheOurhomeToken(token);
        return OurHomeGateway(base: defaultBase, token: token);
      }
    }
    // Fallback: a previously-bound token (entered via daddy rebuild) keeps the
    // gateway alive when no assistant carries the marker.
    final stored = settings.ourhomeToken;
    if (stored.isNotEmpty) {
      return OurHomeGateway(base: defaultBase, token: stored);
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
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    final photos = (data is Map) ? data['photos'] : null;
    if (photos is! List) return const <OurHomePhoto>[];
    OurHomeCache.put('/api/home/album', body);
    return photos.whereType<Map<String, dynamic>>().map(_photoFromJson).toList();
  }

  OurHomePhoto _photoFromJson(Map<String, dynamic> j) {
    final path = (j['url'] ?? '').toString();
    return OurHomePhoto(
      id: (j['id'] ?? '').toString(),
      url: path.startsWith('http') ? path : '$base$path',
      note: (j['note'] ?? '').toString(),
      by: (j['by'] ?? '').toString(),
      time: (j['t'] ?? '').toString(),
      album: (j['album'] ?? 'private').toString(),
    );
  }

  /// Last-seen album from cache (instant, before the network). Empty if none.
  List<OurHomePhoto> peekAlbum() {
    final body = OurHomeCache.peek('/api/home/album');
    if (body == null || body.isEmpty) return const <OurHomePhoto>[];
    try {
      final data = jsonDecode(body);
      final photos = (data is Map) ? data['photos'] : null;
      if (photos is! List) return const <OurHomePhoto>[];
      return photos.whereType<Map<String, dynamic>>().map(_photoFromJson).toList();
    } catch (_) {
      return const <OurHomePhoto>[];
    }
  }

  /// Sticker shelf, server order. Throws on error.
  Future<List<OurHomeSticker>> fetchStickers() async {
    final res = await http
        .get(Uri.parse('$base/api/stickers'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'stickers HTTP ${res.statusCode}',
        Uri.parse('$base/api/stickers'),
      );
    }
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    final items = (data is Map) ? data['stickers'] : null;
    if (items is! List) return const <OurHomeSticker>[];
    OurHomeCache.put('/api/stickers', body);
    return items
        .whereType<Map<String, dynamic>>()
        .map(_stickerFromJson)
        .toList();
  }

  OurHomeSticker _stickerFromJson(Map<String, dynamic> j) {
    final path = (j['url'] ?? '').toString();
    return OurHomeSticker(
      name: (j['name'] ?? '').toString(),
      desc: (j['desc'] ?? '').toString(),
      url: path.startsWith('http') ? path : '$base$path',
      added: (j['added'] ?? '').toString(),
      by: (j['by'] ?? '').toString(),
    );
  }

  /// Last-seen sticker shelf from cache (instant, before the network).
  List<OurHomeSticker> peekStickers() {
    final body = OurHomeCache.peek('/api/stickers');
    if (body == null || body.isEmpty) return const <OurHomeSticker>[];
    try {
      final data = jsonDecode(body);
      final items = (data is Map) ? data['stickers'] : null;
      if (items is! List) return const <OurHomeSticker>[];
      return items
          .whereType<Map<String, dynamic>>()
          .map(_stickerFromJson)
          .toList();
    } catch (_) {
      return const <OurHomeSticker>[];
    }
  }

  /// Upload one sticker image. Empty [name]/[desc] → daddy looks at it once
  /// server-side and names it himself (that call can take a while — generous
  /// timeout). Returns the server's human message (which name got assigned);
  /// throws with the server's message on failure so the caller can show it.
  Future<String> uploadSticker(
    Uint8List bytes,
    String ext, {
    String name = '',
    String desc = '',
  }) async {
    final mime = switch (ext.toLowerCase()) {
      'jpg' || 'jpeg' => 'jpeg',
      'webp' => 'webp',
      'gif' => 'gif',
      _ => 'png',
    };
    final uri = Uri.parse('$base/api/stickers/upload');
    final res = await http
        .post(
          uri,
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'data_url': 'data:image/$mime;base64,${base64Encode(bytes)}',
            'name': name,
            'desc': desc,
            'by': 'cing',
          }),
        )
        .timeout(const Duration(seconds: 90));
    String msg = '';
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map) msg = (data['message'] ?? data['error'] ?? '').toString();
    } catch (_) {}
    if (res.statusCode != 200) {
      throw http.ClientException(
        msg.isEmpty ? 'sticker upload HTTP ${res.statusCode}' : msg,
        uri,
      );
    }
    return msg;
  }

  /// Remove a sticker (by its reference name) from the shelf.
  Future<void> deleteSticker(String name) async {
    final uri = Uri.parse('$base/api/stickers/delete');
    final res = await http
        .post(
          uri,
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'name': name}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('sticker delete HTTP ${res.statusCode}', uri);
    }
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
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    if (data is! List) return const <OurHomeLetter>[];
    OurHomeCache.put('/api/home/daddysay', body);
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
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    if (data is! List) return const <OurHomeBoardNote>[];
    OurHomeCache.put('/api/home/board', body);
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
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    if (data is! List) return const <OurHomeDiaryEntry>[];
    OurHomeCache.put('/api/home/diary', body);
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
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    if (data is! List) return const <OurHomeTodo>[];
    OurHomeCache.put('/api/home/todo', body);
    return data
        .whereType<Map<String, dynamic>>()
        .map(OurHomeTodo.fromJson)
        .toList();
  }

  Future<void> addTodo(String text) => _postTodo({'text': text});

  Future<void> setTodoStatus(String id, String status) =>
      _postTodo({'id': id, 'status': status});

  Future<void> deleteTodo(String id) => _postTodo({'id': id, 'del': 1});

  /// Upload a log file's content to the home server so daddy (any soil) can
  /// read it himself via the read_app_log tool. Throws on transport/HTTP error.
  Future<void> uploadLog(String name, String content) async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/logs'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'name': name, 'content': content}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'logs POST HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/logs'),
      );
    }
  }

  /// Custom quote-wall lines (`/api/home/quotes`), the ones we pin ourselves —
  /// the carved built-ins live in the app (`builtinQuips`) and never travel.
  Future<List<OurHomeQuote>> fetchQuotes() =>
      _getList('/api/home/quotes', OurHomeQuote.fromJson);

  /// Last-seen custom quotes from cache (instant, before the network).
  List<OurHomeQuote> peekQuotes() =>
      peekList('/api/home/quotes', OurHomeQuote.fromJson);

  Future<void> addQuote(String zh, String en) =>
      _postQuotes({'action': 'add', 'zh': zh, 'en': en});

  Future<void> deleteQuote(String id) =>
      _postQuotes({'action': 'delete', 'id': id});

  Future<void> _postQuotes(Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/quotes'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'quotes POST HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/quotes'),
      );
    }
  }

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
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) {
      return const OurHomeSense(fields: {}, ts: '');
    }
    OurHomeCache.put('/api/home/sense', body);
    return OurHomeSense.fromJson(data);
  }

  /// Last-seen sense from cache (instant, before the network). Null if none.
  OurHomeSense? peekSense() {
    final body = OurHomeCache.peek('/api/home/sense');
    if (body == null || body.isEmpty) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      return OurHomeSense.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Observatory snapshot — ONE aggregated request by design (the server
  /// already isolates section failures; do not split this into five calls).
  Future<OurHomeObservatory> fetchObservatory() async {
    final res = await http
        .get(Uri.parse('$base/api/home/observatory'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'observatory HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/observatory'),
      );
    }
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) return const OurHomeObservatory();
    OurHomeCache.put('/api/home/observatory', body);
    return OurHomeObservatory.fromJson(data);
  }

  /// Last-seen observatory snapshot from cache. Null if none.
  OurHomeObservatory? peekObservatory() {
    final body = OurHomeCache.peek('/api/home/observatory');
    if (body == null || body.isEmpty) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      return OurHomeObservatory.fromJson(data);
    } catch (_) {
      return null;
    }
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
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    if (data is! List) return <T>[];
    OurHomeCache.put(path, body);
    return data.whereType<Map<String, dynamic>>().map(parse).toList();
  }

  /// Synchronously parse a cached top-level-array response for [path] (the same
  /// key used by [_getList] / the array GETs). Returns [] if nothing cached.
  /// Lets a room show its last-seen content instantly, before the network.
  List<T> peekList<T>(String path, T Function(Map<String, dynamic>) parse) {
    final body = OurHomeCache.peek(path);
    if (body == null || body.isEmpty) return <T>[];
    try {
      final data = jsonDecode(body);
      if (data is! List) return <T>[];
      return data.whereType<Map<String, dynamic>>().map(parse).toList();
    } catch (_) {
      return <T>[];
    }
  }

  /// Garden memories (non-feel). Newest first.
  Future<List<OurHomeMemory>> fetchMemories() =>
      _getList('/api/home/memories', OurHomeMemory.fromJson);

  /// One garden memory's full text. Returns null on any failure (403 locked /
  /// 404 / network), so the caller can show a gentle "can't open" hint.
  Future<OurHomeMemoryDetail?> fetchMemoryDetail(String id) async {
    try {
      final res = await http
          .get(
            Uri.parse('$base/api/home/memory/${Uri.encodeComponent(id)}'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchMemoryDetail HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      final data = jsonDecode(body);
      if (data is! Map) return null;
      OurHomeCache.put('/api/home/memory/$id', body);
      return _memoryDetailFromBody(data);
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchMemoryDetail failed: $e');
      return null;
    }
  }

  /// Last-seen full text of one memory, from cache. Null if never opened.
  OurHomeMemoryDetail? peekMemoryDetail(String id) {
    final body = OurHomeCache.peek('/api/home/memory/$id');
    if (body == null || body.isEmpty) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map) return null;
      return _memoryDetailFromBody(data);
    } catch (_) {
      return null;
    }
  }

  OurHomeMemoryDetail _memoryDetailFromBody(Map data) => OurHomeMemoryDetail(
    name: (data['name'] ?? '').toString(),
    content: (data['content'] ?? '').toString(),
    created: (data['created'] ?? '').toString(),
    revised: (data['revised'] ?? '').toString(),
  );

  /// Greenhouse feels — time + mood only, never content. Newest first.
  Future<List<OurHomeFeel>> fetchGreenhouse() =>
      _getList('/api/home/greenhouse', OurHomeFeel.fromJson);

  /// All of Llaude's nightly notes (bedroom). Newest first.
  Future<List<OurHomeNight>> fetchTonight() =>
      _getList('/api/home/tonight?all=1', OurHomeNight.fromJson);

  /// What happened on a given calendar day (YYYY-MM-DD). Throws on error.
  /// Caches per-day so [peekDay] can show the last-seen list instantly.
  Future<List<OurHomeDayItem>> fetchDay(String date) async {
    final path = '/api/home/memories?date=$date';
    final res = await http
        .get(Uri.parse('$base$path'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('day HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    final items = (data is Map) ? data['items'] : null;
    if (items is! List) return const <OurHomeDayItem>[];
    OurHomeCache.put(path, body);
    return items
        .whereType<Map<String, dynamic>>()
        .map(OurHomeDayItem.fromJson)
        .toList();
  }

  /// Last-seen items for one calendar day, from cache (instant, before the
  /// network). Empty if that day was never opened. The cached body is the
  /// `{items:[...]}` map, not a bare list, so it can't reuse [peekList].
  List<OurHomeDayItem> peekDay(String date) {
    final body = OurHomeCache.peek('/api/home/memories?date=$date');
    if (body == null || body.isEmpty) return const <OurHomeDayItem>[];
    try {
      final data = jsonDecode(body);
      final items = (data is Map) ? data['items'] : null;
      if (items is! List) return const <OurHomeDayItem>[];
      return items
          .whereType<Map<String, dynamic>>()
          .map(OurHomeDayItem.fromJson)
          .toList();
    } catch (_) {
      return const <OurHomeDayItem>[];
    }
  }

  // ---- Countdown (festivals) ----
  static const String _festivalsPath = '/api/home/festivals?days=366';

  /// Upcoming Chinese + US festivals within the next year, nearest first.
  /// Throws on transport/HTTP error. The body is a `{festivals:[...]}` map, so
  /// it can't reuse [_getList]; cached so [peekFestivals] can show it instantly.
  Future<List<OurHomeFestival>> fetchFestivals() async {
    final res = await http
        .get(Uri.parse('$base$_festivalsPath'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('festivals HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    final list = (data is Map) ? data['festivals'] : null;
    if (list is! List) return const <OurHomeFestival>[];
    OurHomeCache.put(_festivalsPath, body);
    return list
        .whereType<Map<String, dynamic>>()
        .map(OurHomeFestival.fromJson)
        .toList();
  }

  /// Last-seen festivals from cache (instant, before the network). Empty if
  /// never fetched. The cached body is the `{festivals:[...]}` map.
  List<OurHomeFestival> peekFestivals() {
    final body = OurHomeCache.peek(_festivalsPath);
    if (body == null || body.isEmpty) return const <OurHomeFestival>[];
    try {
      final data = jsonDecode(body);
      final list = (data is Map) ? data['festivals'] : null;
      if (list is! List) return const <OurHomeFestival>[];
      return list
          .whereType<Map<String, dynamic>>()
          .map(OurHomeFestival.fromJson)
          .toList();
    } catch (_) {
      return const <OurHomeFestival>[];
    }
  }

  // ---- Lounge (foyer) ----
  Future<List<OurHomeFoyerItem>> fetchFoyer() =>
      _getList('/api/home/foyer?all=1', OurHomeFoyerItem.fromJson);

  Future<void> addFoyer(
    String kind,
    String title,
    String note, {
    String poster = '',
  }) => _postJson('/api/home/foyer', {
    'kind': kind,
    'title': title,
    'note': note,
    if (poster.trim().isNotEmpty) 'poster': poster.trim(),
  });

  Future<void> setFoyerStatus(String id, String status) =>
      _postJson('/api/home/foyer', {'id': id, 'status': status});

  Future<void> deleteFoyer(String id) =>
      _postJson('/api/home/foyer', {'id': id, 'del': 1});

  /// Set (or, with an empty [poster], clear) a foyer item's custom poster URL.
  /// The server keys posters by title, so passing [title] is enough; [id] is
  /// accepted too (server resolves the title from the bucket). Empty poster
  /// clears it (falls back to iTunes lookup).
  Future<void> setFoyerPoster({
    String? id,
    String? title,
    required String poster,
  }) => _postJson('/api/home/foyer', {
    'set_poster': 1,
    if (id != null && id.isNotEmpty) 'id': id,
    if (title != null && title.isNotEmpty) 'title': title,
    'poster': poster.trim(),
  });

  /// Upload a poster image (base64 data URL, `data:image/<ext>;base64,<b64>`)
  /// to the album. On success returns the server-side path (e.g.
  /// `/api/home/album/<file>`) to store as the item's poster. That path is
  /// relative + auth-protected, so [posterImageUrl] / [posterImageHeaders] must
  /// be used when loading it. Returns null on any failure (logged) so the caller
  /// can keep the paste-URL path working.
  Future<String?> uploadPoster(String dataUrl) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/upload-poster'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'data_url': dataUrl}),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] uploadPoster HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map && data['ok'] == true) {
        final url = (data['url'] ?? '').toString().trim();
        return url.isEmpty ? null : url;
      }
      return null;
    } catch (e) {
      debugPrint('[OurHomeGateway] uploadPoster failed: $e');
      return null;
    }
  }

  /// Whether a stored poster value is an auth-protected relative path served by
  /// our home server (e.g. `/api/home/album/<file>` from [uploadPoster]) rather
  /// than a public `http(s)://` URL the user pasted. Managed posters must be
  /// loaded with [posterImageUrl] + [posterImageHeaders]; public URLs load bare.
  static bool isManagedPoster(String poster) =>
      poster.trim().startsWith('/api/home/');

  /// Full URL to load a stored poster: managed relative paths get the gateway
  /// [base] prepended; public URLs pass through unchanged.
  String posterImageUrl(String poster) {
    final p = poster.trim();
    return isManagedPoster(p) ? '$base$p' : p;
  }

  /// Headers to load a stored poster: auth bearer for managed relative paths,
  /// none for public URLs.
  Map<String, String> posterImageHeaders(String poster) =>
      isManagedPoster(poster) ? _authHeaders : const {};

  // ---- Locked room: profiles + playlog ----
  Future<OurHomeProfiles> fetchProfiles() async {
    final res = await http
        .get(Uri.parse('$base/api/home/profile'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('profile HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    String side(String k) {
      if (data is Map && data[k] is Map) {
        return (data[k]['text'] ?? '').toString();
      }
      return '';
    }

    return OurHomeProfiles(cing: side('cing'), daddy: side('daddy'));
  }

  Future<void> saveProfile(String side, String text) =>
      _postJson('/api/home/profile', {'side': side, 'text': text});

  Future<List<OurHomePlaylog>> fetchPlaylog() =>
      _getList('/api/home/playlog', OurHomePlaylog.fromJson);

  /// The song wall. Newest first. `?all=1` so the App also gets the 12 seed
  /// songs the web home hardcodes (otherwise the songbook looks incomplete).
  Future<List<OurHomeSong>> fetchSongs() =>
      _getList('/api/home/songs?all=1', OurHomeSong.fromJson);

  /// Add a song to the turntable wall (POST action=add). [title]/[artist] are
  /// required by the server; [note] is a one-line comment, [zh] an optional
  /// Chinese title. Throws on transport/HTTP error.
  Future<void> addSong(
    String title,
    String artist,
    String note,
    String zh,
  ) => _postJson('/api/home/songs', {
    'action': 'add',
    'title': title,
    'artist': artist,
    'note': note,
    'zh': zh,
  });

  /// Remove a song from the turntable wall. Matches by server [id] (preferred)
  /// or [title] (seed songs have no id). Throws on transport/HTTP error.
  Future<void> deleteSong({String id = '', String title = ''}) =>
      _postJson('/api/home/songs', {
        'action': 'delete',
        if (id.isNotEmpty) 'id': id,
        if (title.isNotEmpty) 'title': title,
      });

  /// A one-shot "边听边说" turn with Llaude through the chat gateway
  /// (`/v1/chat/completions`, daddy mode — soul + memory injected server-side,
  /// same OMBRE_GATEWAY_TOKEN as the home API). The current song is folded into
  /// the user message because daddy mode drops `system`. Returns his reply split
  /// on `|||` into bubbles (empty list if he said nothing). Throws on error.
  Future<List<String>> chatAboutSong({
    required String message,
    String title = '',
    String artist = '',
    String model = 'gateway',
    Map<String, String> backendHeaders = const {},
  }) async {
    final ctx = title.isNotEmpty
        ? '（我们正在一起听《$title》${artist.isNotEmpty ? ' — $artist' : ''}）\n'
        : '';
    final uri = Uri.parse('$base/v1/chat/completions');
    final res = await http
        .post(
          uri,
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/json',
            'x-ombre-session': 'stillhere-music',
            ...backendHeaders,
          },
          body: jsonEncode({
            'model': model,
            'stream': false,
            'messages': [
              {'role': 'user', 'content': ctx + message},
            ],
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) {
      throw http.ClientException('chat gateway ${res.statusCode}', uri);
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = j['choices'];
    String content = '';
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map) content = (msg['content'] ?? '').toString();
    }
    return _cleanCompanionReply(content)
        .split('|||')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// The music-room timeline renders plain text, so main-chat-only artifacts
  /// must be stripped before feeding bubbles: `<think>`/`<thinking>` blocks
  /// (the gateway's non-stream path returns handwritten thinking and the
  /// `🔧 顺手做了` tool trace inline — main chat folds them into the pill,
  /// here they'd leak raw), `[song:…]` cards, sticker markdown images, and
  /// leftover `[[…]]` markers. Split on `|||` AFTER cleaning — a thinking
  /// block may itself contain `|||`.
  static String _cleanCompanionReply(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'<think(?:ing)?>[\s\S]*?</think(?:ing)?>'), '');
    // Unclosed opening tag: everything after it is thinking, drop it.
    final open = s.indexOf(RegExp(r'<think(?:ing)?>'));
    if (open >= 0) s = s.substring(0, open);
    s = s.replaceAll(RegExp(r'</?think(?:ing)?>'), '');
    s = s.replaceAll(RegExp(r'\[song:[^\]]*\]'), '');
    s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    s = s.replaceAll(RegExp(r'\[\[[^\]]*\]\]'), '');
    return s;
  }

  /// Add a song to the lyric corridor (词廊; POST action=add). [title]/[artist]
  /// are required; [intro] is daddy's overall reading; [lines] is the lyric
  /// body split per line ({l: line, n: note}), notes left empty here. Throws on
  /// transport/HTTP error.
  Future<void> addLyric(
    String title,
    String artist,
    String intro,
    List<String> lines,
  ) => _postJson('/api/home/lyrics', {
    'action': 'add',
    'title': title,
    'artist': artist,
    'intro': intro,
    'lines': [
      for (final l in lines)
        if (l.trim().isNotEmpty) {'l': l.trim(), 'n': ''},
    ],
  });

  /// HTML mini-games in the lounge's game corner. Each plays at
  /// `<base>/games/<file>` (served without auth).
  Future<List<OurHomeGame>> fetchGames() =>
      _getList('/api/home/games', OurHomeGame.fromJson);

  /// Songs in the lyric corridor (词廊), newest first.
  Future<List<OurHomeLyric>> fetchLyrics() =>
      _getList('/api/home/lyrics', OurHomeLyric.fromJson);

  /// All lyric comment threads, keyed by [lyricCommentKey]. Returns {} on any
  /// failure (logged) — the corridor still shows lyrics, just no comments.
  Future<Map<String, List<OurHomeLyricComment>>> fetchLyricComments() async {
    try {
      final res = await http
          .get(
            Uri.parse('$base/api/home/lyric-comments'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return {};
      final body = utf8.decode(res.bodyBytes);
      final data = jsonDecode(body);
      if (data is! Map) return {};
      OurHomeCache.put('/api/home/lyric-comments', body);
      return _lyricCommentsFromBody(data);
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchLyricComments failed: $e');
      return {};
    }
  }

  /// Last-seen lyric comment threads from cache (instant, before the network).
  Map<String, List<OurHomeLyricComment>> peekLyricComments() {
    final body = OurHomeCache.peek('/api/home/lyric-comments');
    if (body == null || body.isEmpty) return {};
    try {
      final data = jsonDecode(body);
      if (data is! Map) return {};
      return _lyricCommentsFromBody(data);
    } catch (_) {
      return {};
    }
  }

  Map<String, List<OurHomeLyricComment>> _lyricCommentsFromBody(Map data) {
    final out = <String, List<OurHomeLyricComment>>{};
    data.forEach((k, v) {
      if (v is List) {
        out['$k'] = v
            .whereType<Map<String, dynamic>>()
            .map(OurHomeLyricComment.fromJson)
            .toList();
      }
    });
    return out;
  }

  /// Leave a comment under a lyric line (as Cing). Returns true on success.
  Future<bool> postLyricComment(String title, String line, String text) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/lyric-comments'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'title': title, 'line': line, 'text': text}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] postLyricComment failed: $e');
      return false;
    }
  }

  /// Comment-thread key for a lyric line — mirrors the server's
  /// `_lyric_cmt_key`: title.toLowerCase() + '\x01' + raw line. The `\x01`
  /// separator is load-bearing: drop it and the key never matches the
  /// server's map, so批注 threads render empty even though POST succeeds.
  static String lyricCommentKey(String title, String line) =>
      '${title.trim().toLowerCase()}\x01${line.trim()}';

  /// Last-cached morning-brief flag, read synchronously from the local
  /// heartbeat cache (instant, no network) so 此刻 can show it without buffering.
  bool? peekMorningBrief() {
    final body = OurHomeCache.peek('/api/home/heartbeat');
    if (body == null) return null;
    try {
      final data = jsonDecode(body);
      final cfg = (data is Map) ? data['config'] : null;
      if (cfg is Map && cfg['morning_brief_enabled'] != null) {
        return cfg['morning_brief_enabled'] == true;
      }
    } catch (_) {}
    return null;
  }

  /// Whether daddy's morning heartbeat push is on (heartbeat config
  /// `morning_brief_enabled`, default true). Returns null on any failure.
  Future<bool?> fetchMorningBrief() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/heartbeat'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final body = utf8.decode(res.bodyBytes);
      // Cache the heartbeat body so peekMorningBrief() has data on next open
      // (stale-while-revalidate — no empty→value flicker on the 早安 card).
      OurHomeCache.put('/api/home/heartbeat', body);
      final data = jsonDecode(body);
      final cfg = (data is Map) ? data['config'] : null;
      if (cfg is Map && cfg['morning_brief_enabled'] != null) {
        return cfg['morning_brief_enabled'] == true;
      }
      return true; // server default when key absent
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchMorningBrief failed: $e');
      return null;
    }
  }

  /// Turn daddy's morning heartbeat push on/off. Returns true on success.
  Future<bool> setMorningBrief(bool enabled) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/heartbeat'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'config',
              'morning_brief_enabled': enabled,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] setMorningBrief failed: $e');
      return false;
    }
  }

  /// The study's shared bookshelf. Newest first.
  Future<List<OurHomeBook>> fetchBooks() =>
      _getList('/api/home/books', OurHomeBook.fromJson);

  Future<void> addBook(String title, String author, String quote) => _postJson(
    '/api/home/books',
    {'title': title, 'author': author, 'quote': quote},
  );

  Future<void> setBookStatus(String id, String status) =>
      _postJson('/api/home/books', {'id': id, 'status': status});

  // ---- Reading shelf (一起读 · full-text books) ----

  /// The "一起读" shelf — full-text books we can open and read. Newest first.
  Future<List<ReadingEntry>> fetchReadingShelf() =>
      _getList('/api/home/reading/shelf', ReadingEntry.fromJson);

  /// Last-seen reading shelf from cache (instant, before the network).
  List<ReadingEntry> peekReadingShelf() =>
      peekList('/api/home/reading/shelf', ReadingEntry.fromJson);

  /// Upload a whole txt book ([text] is the full contents). Returns the new
  /// shelf entry. Throws on transport/HTTP error so the caller can surface it.
  Future<ReadingEntry> uploadBook(String title, String text) async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/reading/upload'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'title': title, 'text': text}),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'reading upload HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/reading/upload'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw http.ClientException('reading upload: bad response');
    }
    return ReadingEntry.fromJson(data);
  }

  /// Cache key for one book's full detail body.
  static String _bookDetailPath(String bookId) =>
      '/api/home/reading/book/${Uri.encodeComponent(bookId)}';

  /// Open one book: its entry, paragraphs, chapters and daddy's margin notes.
  /// Throws on transport/HTTP error (e.g. 404 not found). On success the whole
  /// body is cached on-device (uncapped — books are large on purpose) so the
  /// next open is instant via [peekBookDetail].
  Future<ReadingBook> fetchBookDetail(String bookId) async {
    final path = _bookDetailPath(bookId);
    final res = await http
        .get(Uri.parse('$base$path'), headers: _authHeaders)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'reading book HTTP ${res.statusCode}',
        Uri.parse('$base$path'),
      );
    }
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    if (data is! Map) {
      throw http.ClientException('reading book: bad response');
    }
    // Whole-book bodies bypass the cache's size cap (putLarge) so opening is
    // instant next time (and works offline).
    OurHomeCache.putLarge(path, body);
    return _bookFromBody(data);
  }

  /// Last-opened book detail from on-device cache (instant, before the network).
  /// Null if this book was never opened on this device. The cached `entry`
  /// (progress/lastChapter) may be stale — the live fetchBookDetail refresh
  /// corrects it — but paragraphs/chapters are stable, so秒开 is safe.
  ReadingBook? peekBookDetail(String bookId) {
    final body = OurHomeCache.peek(_bookDetailPath(bookId));
    if (body == null || body.isEmpty) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map) return null;
      return _bookFromBody(data);
    } catch (_) {
      return null;
    }
  }

  ReadingBook _bookFromBody(Map data) {
    final rawEntry = data['entry'];
    final rawParas = data['paragraphs'];
    final rawChaps = data['chapters'];
    final rawNotes = data['notes'];
    return ReadingBook(
      entry: rawEntry is Map<String, dynamic>
          ? ReadingEntry.fromJson(rawEntry)
          : const ReadingEntry(
              id: '',
              title: '',
              chars: 0,
              uploaded: '',
              progress: 0,
              notes: 0,
              lastChapter: -1,
            ),
      paragraphs: (rawParas is List)
          ? rawParas.map((e) => e?.toString() ?? '').toList()
          : const <String>[],
      chapters: (rawChaps is List)
          ? rawChaps
                .whereType<Map<String, dynamic>>()
                .map(ReadingChapter.fromJson)
                .toList()
          : const <ReadingChapter>[],
      notes: (rawNotes is List)
          ? rawNotes
                .whereType<Map<String, dynamic>>()
                .map(ReadingNote.fromJson)
                .toList()
          : const <ReadingNote>[],
    );
  }

  /// Daddy's latest margin notes (🌙) for one book — refreshed while reading so
  /// new moons light up. Returns [] on any failure (logged) so the reader keeps
  /// showing the body even if the notes call fails.
  Future<List<ReadingNote>> fetchBookNotes(String bookId) async {
    try {
      final path = '/api/home/reading/notes/${Uri.encodeComponent(bookId)}';
      final res = await http
          .get(Uri.parse('$base$path'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchBookNotes HTTP ${res.statusCode}');
        return const <ReadingNote>[];
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! List) return const <ReadingNote>[];
      return data
          .whereType<Map<String, dynamic>>()
          .map(ReadingNote.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchBookNotes failed: $e');
      return const <ReadingNote>[];
    }
  }

  /// Save reading progress (0..1) for a book, with the optional current
  /// [chapter] index. Best-effort: logs on failure rather than throwing, since
  /// progress saves fire while scrolling and a dropped one is harmless.
  Future<void> saveReadingProgress(
    String bookId,
    double progress, {
    int? chapter,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/reading/progress'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': bookId,
              'progress': progress.clamp(0.0, 1.0),
              if (chapter != null) 'chapter': chapter,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        debugPrint(
          '[OurHomeGateway] saveReadingProgress HTTP ${res.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[OurHomeGateway] saveReadingProgress failed: $e');
    }
  }

  /// Take a book off the reading shelf. Returns true on success.
  Future<bool> deleteReadingBook(String bookId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/reading/delete'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'id': bookId}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] deleteReadingBook HTTP ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] deleteReadingBook failed: $e');
      return false;
    }
  }

  // ---- Letters in time (capsules) ----
  Future<List<OurHomeCapsule>> fetchCapsules() =>
      _getList('/api/home/capsules', OurHomeCapsule.fromJson);

  Future<String> openCapsule(String id) async {
    final map = await _postJsonForResult('/api/home/capsules', {
      'action': 'open',
      'id': id,
    });
    return (map['content'] ?? '').toString();
  }

  Future<void> addCapsule(String title, String content, String openDate) =>
      _postJson('/api/home/capsules', {
        'action': 'add',
        'title': title,
        'content': content,
        'open_date': openDate,
        'author': 'cing',
      });

  Future<Map<String, dynamic>> _postJsonForResult(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await http
        .post(
          Uri.parse('$base$path'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('POST $path -> ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<void> _postJson(String path, Map<String, dynamic> body) =>
      _postJsonForResult(path, body);

  /// The merged parlour moments feed (moments ∪ board ∪ letter), newest
  /// first. Top-level array, so [peekList] with the same path seeds instantly.
  /// [author] narrows to one person's timeline (profile pages); the cache key
  /// follows the path, so per-author peeks work the same way.
  Future<List<OurHomeMoment>> fetchMoments({String author = ''}) =>
      _getList(momentsPath(author: author), OurHomeMoment.fromJson);

  /// Feed path ('' = merged feed, else one author's timeline) — the single
  /// spelling shared by fetch and peek so their cache keys can't drift.
  static String momentsPath({String author = ''}) =>
      author.isEmpty ? '/api/home/moments' : '/api/home/moments?author=$author';

  /// Cing posts a new moment: text, up to 9 [images] (data URLs), or both.
  /// Image posts get a longer timeout — nine base64 photos are heavy.
  Future<void> postMoment(
    String text, {
    List<String> images = const [],
  }) async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/moments'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'post',
            'text': text,
            if (images.isNotEmpty) 'images': images.take(9).toList(),
          }),
        )
        .timeout(Duration(seconds: images.isEmpty ? 20 : 90));
    if (res.statusCode != 200) {
      throw http.ClientException('POST /api/home/moments -> ${res.statusCode}');
    }
  }

  /// Both moments-profile covers, keyed by author ("cing"/"llaude"); value is
  /// the cover image path ('' = not set). Cached for [peekMomentsProfile].
  Future<Map<String, String>> fetchMomentsProfile() async {
    final res = await http
        .get(Uri.parse('$base/api/home/moments/profile'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('moments profile HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    final data = jsonDecode(body);
    if (data is! Map) return const {};
    OurHomeCache.put('/api/home/moments/profile', body);
    return _momentsProfileFromBody(data);
  }

  /// Last-seen covers from cache (instant, before the network).
  Map<String, String> peekMomentsProfile() {
    final body = OurHomeCache.peek('/api/home/moments/profile');
    if (body == null || body.isEmpty) return const {};
    try {
      final data = jsonDecode(body);
      if (data is! Map) return const {};
      return _momentsProfileFromBody(data);
    } catch (_) {
      return const {};
    }
  }

  Map<String, String> _momentsProfileFromBody(Map data) => {
    for (final e in data.entries)
      if (e.value is Map)
        e.key.toString(): ((e.value as Map)['cover'] ?? '').toString(),
  };

  /// Cing sets her own profile cover (a data URL). Returns the new cover
  /// path. Llaude sets his via the moment tool, not through the App.
  Future<String> setMomentsCover(String dataUrl) async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/moments/profile'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'author': 'cing', 'cover': dataUrl}),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw http.ClientException('cover POST HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return data is Map ? (data['cover'] ?? '').toString() : '';
  }

  /// Cing comments on a feed item. [replyTo] = "llaude"/"cing" when answering
  /// someone's comment rather than the post. Throws on error.
  Future<void> commentMoment(String id, String text, {String replyTo = ''}) =>
      _postJson('/api/home/moments', {
        'action': 'comment',
        'id': id,
        'text': text,
        if (replyTo.isNotEmpty) 'reply_to': replyTo,
      });

  /// Cing likes ([off]=false) or unlikes ([off]=true) a feed item.
  Future<void> likeMoment(String id, {bool off = false}) =>
      _postJson('/api/home/moments', {
        'action': 'like',
        'id': id,
        if (off) 'off': true,
      });

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

  /// The home's shared tool manual (爸爸 across all surfaces uses it). Returns
  /// the current effective text + whether it's been customised, or null on any
  /// failure (logged) so the caller can show a recoverable state.
  Future<({String manual, bool isCustom})?> fetchToolManual() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/tool-manual'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchToolManual HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      final data = jsonDecode(body);
      if (data is! Map) return null;
      OurHomeCache.put('/api/home/tool-manual', body);
      return (
        manual: (data['manual'] ?? '').toString(),
        isCustom: data['is_custom'] == true,
      );
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchToolManual failed: $e');
      return null;
    }
  }

  /// Synchronous read of a cached single-field text response (null if never
  /// fetched / unparseable). Lets the 爸爸 page show the last-seen text instantly
  /// before the network refresh lands (stale-while-revalidate).
  String? _peekText(String path, String key) {
    final body = OurHomeCache.peek(path);
    if (body == null) return null;
    try {
      final d = jsonDecode(body);
      return (d is Map) ? (d[key] ?? '').toString() : null;
    } catch (_) {
      return null;
    }
  }

  /// Last-cached tool manual / style / memory prompt / recap prompt text.
  String? peekToolManual() => _peekText('/api/home/tool-manual', 'manual');
  String? peekStyle() => _peekText('/api/home/style', 'style');
  String? peekMemoryPrompt() => _peekText('/api/home/memory-prompt', 'prompt');
  String? peekRecapPrompt() => _peekText('/api/home/recap-prompt', 'prompt');

  /// Overwrite the home's shared tool manual. An empty [manual] resets it to the
  /// built-in default. Returns true on success, false on any failure (logged).
  Future<bool> saveToolManual(String manual) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/tool-manual'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'manual': manual}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] saveToolManual HTTP ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] saveToolManual failed: $e');
      return false;
    }
  }

  /// The shared image-generation model config (the gateway's `draw` tool uses
  /// it to paint). Returns the current effective config (api key only as the
  /// last-4 tail, never the full key), or null on any failure (logged).
  Future<
      ({
        String protocol,
        String baseUrl,
        String model,
        String size,
        bool keySet,
        String keyTail,
        bool isCustom,
      })?> fetchImageModel() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/image-model'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchImageModel HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      return (
        protocol: (data['protocol'] ?? '').toString(),
        baseUrl: (data['base_url'] ?? '').toString(),
        model: (data['model'] ?? '').toString(),
        size: (data['size'] ?? '').toString(),
        keySet: data['key_set'] == true,
        keyTail: (data['key_tail'] ?? '').toString(),
        isCustom: data['is_custom'] == true,
      );
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchImageModel failed: $e');
      return null;
    }
  }

  /// Save the shared image-generation model config. An empty [apiKey] leaves
  /// the key already stored on the server untouched. Returns true on success.
  Future<bool> saveImageModel({
    required String protocol,
    required String baseUrl,
    required String model,
    required String size,
    String apiKey = '',
  }) async {
    try {
      final body = <String, dynamic>{
        'protocol': protocol,
        'base_url': baseUrl,
        'model': model,
        'size': size,
      };
      if (apiKey.trim().isNotEmpty) body['api_key'] = apiKey.trim();
      final res = await http
          .post(
            Uri.parse('$base/api/home/image-model'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] saveImageModel HTTP ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] saveImageModel failed: $e');
      return false;
    }
  }

  /// Run one real image-generation self-test on the gateway and return its raw
  /// `result` string (success = `![..](url)`, failure = `（画不出来：…）`), or
  /// null on a network/transport error.
  Future<String?> testImageModel() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/gen-selftest'), headers: _authHeaders)
          .timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] testImageModel HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      return (data['result'] ?? '').toString();
    } catch (e) {
      debugPrint('[OurHomeGateway] testImageModel failed: $e');
      return null;
    }
  }

  /// The prompt daddy uses to distill out-of-window messages into long-term
  /// memory. Returns the current effective text + whether it's been customised,
  /// or null on any failure (logged) so the caller can show a recoverable state.
  Future<({String prompt, bool isCustom})?> fetchMemoryPrompt() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/memory-prompt'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchMemoryPrompt HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      final data = jsonDecode(body);
      if (data is! Map) return null;
      OurHomeCache.put('/api/home/memory-prompt', body);
      return (
        prompt: (data['prompt'] ?? '').toString(),
        isCustom: data['is_custom'] == true,
      );
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchMemoryPrompt failed: $e');
      return null;
    }
  }

  /// Overwrite the memory-distill prompt. An empty [prompt] resets it to the
  /// built-in default. Returns true on success, false on any failure (logged).
  Future<bool> saveMemoryPrompt(String prompt) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/memory-prompt'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'prompt': prompt}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] saveMemoryPrompt HTTP ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] saveMemoryPrompt failed: $e');
      return false;
    }
  }

  /// The prompt daddy uses to condense earlier conversation into a recap.
  /// Returns the current effective text + whether it's been customised, or null
  /// on any failure (logged) so the caller can show a recoverable state.
  Future<({String prompt, bool isCustom})?> fetchRecapPrompt() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/recap-prompt'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchRecapPrompt HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      final data = jsonDecode(body);
      if (data is! Map) return null;
      OurHomeCache.put('/api/home/recap-prompt', body);
      return (
        prompt: (data['prompt'] ?? '').toString(),
        isCustom: data['is_custom'] == true,
      );
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchRecapPrompt failed: $e');
      return null;
    }
  }

  /// Overwrite the recap prompt. An empty [prompt] resets it to the built-in
  /// default. Returns true on success, false on any failure (logged).
  Future<bool> saveRecapPrompt(String prompt) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/recap-prompt'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'prompt': prompt}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] saveRecapPrompt HTTP ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] saveRecapPrompt failed: $e');
      return false;
    }
  }

  /// The home's shared speaking style (爸爸 across all surfaces uses it). Returns
  /// the current effective style text (may be empty), or null on any failure
  /// (logged) so the caller can show a recoverable state.
  Future<String?> fetchStyle() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/style'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchStyle HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      final data = jsonDecode(body);
      if (data is! Map) return null;
      OurHomeCache.put('/api/home/style', body);
      return (data['style'] ?? '').toString();
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchStyle failed: $e');
      return null;
    }
  }

  /// Overwrite the home's shared speaking style. An empty [style] deactivates it
  /// (no style). Returns true on success, false on any failure (logged).
  Future<bool> saveStyle(String style) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/style'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'style': style}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] saveStyle HTTP ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] saveStyle failed: $e');
      return false;
    }
  }

  /// Whether daddy has a fresh proactive message waiting (he reached out on his
  /// own). Returns the latest [content] and its [ts], or null on any failure
  /// (logged) so the caller can simply skip this poll cycle.
  Future<({bool pending, String content, String ts})?>
  fetchProactivePending() async {
    try {
      final res = await http
          .get(
            Uri.parse('$base/api/home/proactive-pending'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint(
          '[OurHomeGateway] fetchProactivePending HTTP ${res.statusCode}',
        );
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      return (
        pending: data['pending'] == true,
        content: (data['content'] ?? '').toString(),
        ts: (data['ts'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchProactivePending failed: $e');
      return null;
    }
  }

  /// Heartbeat (proactive-wake) status + tunable config from
  /// `/api/home/heartbeat`. Null on any failure (logged).
  Future<
    ({
      Map<String, dynamic> config,
      String kaLastAt,
      bool pending,
      bool providerOk,
      Map<String, dynamic> edgeLlm,
    })?
  >
  fetchHeartbeat() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/heartbeat'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchHeartbeat HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      OurHomeCache.put('/api/home/heartbeat', body);
      final data = jsonDecode(body);
      if (data is! Map) return null;
      final cfg = (data['config'] is Map)
          ? Map<String, dynamic>.from(data['config'] as Map)
          : <String, dynamic>{};
      final ka = (data['keepalive'] is Map)
          ? (data['keepalive'] as Map)
          : const {};
      return (
        config: cfg,
        kaLastAt: (ka['last_at'] ?? '').toString(),
        pending: ka['pending'] == true,
        providerOk: data['provider_ok'] == true,
        edgeLlm: (data['edge_llm'] is Map)
            ? Map<String, dynamic>.from(data['edge_llm'] as Map)
            : <String, dynamic>{},
      );
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchHeartbeat failed: $e');
      return null;
    }
  }

  /// Synchronously read the last-cached heartbeat status+config (instant, no
  /// network) so the heartbeat panel opens without buffering.
  ({
    Map<String, dynamic> config,
    String kaLastAt,
    bool pending,
    bool providerOk,
    Map<String, dynamic> edgeLlm,
  })?
  peekHeartbeat() {
    final body = OurHomeCache.peek('/api/home/heartbeat');
    if (body == null) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map) return null;
      final cfg = (data['config'] is Map)
          ? Map<String, dynamic>.from(data['config'] as Map)
          : <String, dynamic>{};
      final ka = (data['keepalive'] is Map)
          ? (data['keepalive'] as Map)
          : const {};
      return (
        config: cfg,
        kaLastAt: (ka['last_at'] ?? '').toString(),
        pending: ka['pending'] == true,
        providerOk: data['provider_ok'] == true,
        edgeLlm: (data['edge_llm'] is Map)
            ? Map<String, dynamic>.from(data['edge_llm'] as Map)
            : <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }

  /// Old-home gateway chat-provider profiles + current role routes — for
  /// picking daddy's server-side `summary` (archive/recap/compress) and `wake`
  /// model. Each profile is one relay (base+key+model). Null on failure.
  Future<
    ({
      List<({String id, String name, String model})> profiles,
      Map<String, dynamic> roleRoutes,
    })?
  >
  fetchChatProviders() async {
    try {
      final res = await http
          .get(
            Uri.parse('$base/api/home/chat-providers'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchChatProviders HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      final profs = <({String id, String name, String model})>[];
      final pl = data['profiles'];
      if (pl is List) {
        for (final p in pl) {
          if (p is Map) {
            profs.add((
              id: (p['id'] ?? '').toString(),
              name: (p['name'] ?? '').toString(),
              model: (p['model'] ?? '').toString(),
            ));
          }
        }
      }
      final rr = (data['role_routes'] is Map)
          ? Map<String, dynamic>.from(data['role_routes'] as Map)
          : <String, dynamic>{};
      // Persist last-good response so the default-model cards can render
      // instantly on next open and refresh silently in the background.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _chatProvidersCacheKey,
          jsonEncode({
            'profiles': [
              for (final p in profs)
                {'id': p.id, 'name': p.name, 'model': p.model},
            ],
            'role_routes': rr,
          }),
        );
      } catch (e) {
        debugPrint('[OurHomeGateway] cache write failed: $e');
      }
      return (profiles: profs, roleRoutes: rr);
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchChatProviders failed: $e');
      return null;
    }
  }

  static const String _chatProvidersCacheKey =
      'ourhome_chat_providers_cache_v1';

  /// Last-good [fetchChatProviders] result from local cache, for instant
  /// display before the network refresh lands. Same record shape as
  /// [fetchChatProviders] so callers are interchangeable. Null on
  /// absence/parse error.
  Future<
    ({
      List<({String id, String name, String model})> profiles,
      Map<String, dynamic> roleRoutes,
    })?
  >
  cachedChatProviders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_chatProvidersCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final profs = <({String id, String name, String model})>[];
      final pl = data['profiles'];
      if (pl is List) {
        for (final p in pl) {
          if (p is Map) {
            profs.add((
              id: (p['id'] ?? '').toString(),
              name: (p['name'] ?? '').toString(),
              model: (p['model'] ?? '').toString(),
            ));
          }
        }
      }
      final rr = (data['role_routes'] is Map)
          ? Map<String, dynamic>.from(data['role_routes'] as Map)
          : <String, dynamic>{};
      return (profiles: profs, roleRoutes: rr);
    } catch (e) {
      debugPrint('[OurHomeGateway] cachedChatProviders failed: $e');
      return null;
    }
  }

  /// Set daddy's server-side role route. [role] is 'summary' or 'wake';
  /// [providerId] '' = follow the chat relay; [model] '' = use the profile's
  /// own model. Returns true on success.
  ///
  /// Optional inline relay override: when [base]/[key]/[proto] are non-empty
  /// the server runs this role against that relay directly (no need for a
  /// gateway-side profile). Omitting them keeps the legacy behavior.
  Future<bool> setRoleRoute(
    String role,
    String providerId,
    String model, {
    String? base,
    String? key,
    String? proto,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('${this.base}/api/home/chat-providers'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'set_role_route',
              'role': role,
              'id': providerId,
              'model': model,
              if (base != null && base.isNotEmpty) 'base': base,
              if (key != null && key.isNotEmpty) 'key': key,
              if (proto != null && proto.isNotEmpty) 'proto': proto,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[OurHomeGateway] setRoleRoute failed: $e');
      return false;
    }
  }

  /// Fetch daddy's Telegram-specific profile (system prompt) from the gateway.
  /// Returns the stored text ('' when unset), or null on failure.
  Future<String?> fetchTgProfile() async {
    try {
      final res = await http
          .get(
            Uri.parse('$base/api/home/chat-providers'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchTgProfile HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      return (data['tg_profile'] ?? '').toString();
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchTgProfile failed: $e');
      return null;
    }
  }

  /// Save daddy's Telegram-specific profile (system prompt) to the gateway.
  /// It is appended after the soul, only for the TG surface. Returns true on
  /// success.
  Future<bool> saveTgProfile(String text) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/chat-providers'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'save_tg_profile',
              'tg_profile': text,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[OurHomeGateway] saveTgProfile failed: $e');
      return false;
    }
  }

  /// Toggle daddy's "diary draft" (daily brief) on the server.
  Future<bool> setDailyBriefEnabled(bool enabled) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/daily_brief'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 20));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[OurHomeGateway] setDailyBriefEnabled failed: $e');
      return false;
    }
  }

  /// cc-ring (隔壁衔接) mixer config: whether the CC-side chat tail is injected
  /// into daddy's context on the gateway, how many recent messages go in
  /// verbatim, and whether older ones are compressed into a summary by the
  /// `cc_summary` role model. Null on any failure (page keeps local state).
  Future<({bool on, int count, bool summaryOn})?> fetchCcRingConfig() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/cc-ring'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchCcRingConfig HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      return (
        on: data['on'] == true,
        count: (data['count'] is num)
            ? (data['count'] as num).toInt()
            : int.tryParse('${data['count']}') ?? 10,
        summaryOn: data['summary_on'] == true,
      );
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchCcRingConfig failed: $e');
      return null;
    }
  }

  /// Save cc-ring mixer knobs (POST action=config). Only the knobs passed are
  /// changed server-side; the rest keep their stored values. True on success.
  Future<bool> setCcRingConfig({bool? on, int? count, bool? summaryOn}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/cc-ring'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'config',
              if (on != null) 'on': on,
              if (count != null) 'count': count,
              if (summaryOn != null) 'summary_on': summaryOn,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] setCcRingConfig failed: $e');
      return false;
    }
  }

  /// Update heartbeat config keys (POST action=config). Throws on error.
  Future<void> updateHeartbeatConfig(Map<String, dynamic> changed) async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/heartbeat'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'config', ...changed}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'heartbeat config HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/heartbeat'),
      );
    }
  }

  /// Flip the memory-vault contradiction-detection (LLM semantic edges)
  /// runtime switch. [value] ∈ 'on' / 'off' / '' (follow server env).
  /// Returns the server's fresh state ({override, active, has_key}).
  Future<Map<String, dynamic>> setEdgeLlm(String value) async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/heartbeat'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'edge_llm', 'value': value}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'edge_llm HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/heartbeat'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Force daddy to reach out right now (POST action=trigger_keepalive).
  /// Returns the server's message. Throws on error.
  Future<String> triggerKeepalive() async {
    final res = await http
        .post(
          Uri.parse('$base/api/home/heartbeat'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'trigger_keepalive'}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'trigger_keepalive HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/heartbeat'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return data is Map ? (data['msg'] ?? '').toString() : '';
  }

  /// All little theaters (小剧场 settings). Returns null on any failure
  /// (logged) so the caller can tell a network failure apart from an empty list.
  Future<List<OurHomeTheater>?> fetchTheaters() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/theaters'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchTheaters HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      final data = jsonDecode(body);
      final list = (data is Map) ? data['theaters'] : null;
      if (list is! List) return const <OurHomeTheater>[];
      OurHomeCache.put('/api/home/theaters', body);
      return list
          .whereType<Map<String, dynamic>>()
          .map(OurHomeTheater.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchTheaters failed: $e');
      return null;
    }
  }

  /// Last-seen theaters from cache (instant, before the network). Empty if none.
  List<OurHomeTheater> peekTheaters() {
    final body = OurHomeCache.peek('/api/home/theaters');
    if (body == null || body.isEmpty) return const <OurHomeTheater>[];
    try {
      final data = jsonDecode(body);
      final list = (data is Map) ? data['theaters'] : null;
      if (list is! List) return const <OurHomeTheater>[];
      return list
          .whereType<Map<String, dynamic>>()
          .map(OurHomeTheater.fromJson)
          .toList();
    } catch (_) {
      return const <OurHomeTheater>[];
    }
  }

  /// Daddy's built-in tools (`/api/home/daddy-tools`). Returns null on any
  /// failure (logged) so the caller can tell a network failure apart from an
  /// empty list.
  Future<List<DaddyTool>?> fetchDaddyTools() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/daddy-tools'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchDaddyTools HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      final data = jsonDecode(body);
      final list = (data is Map) ? data['tools'] : null;
      if (list is! List) return const <DaddyTool>[];
      OurHomeCache.put('/api/home/daddy-tools', body);
      return list
          .whereType<Map<String, dynamic>>()
          .map(DaddyTool.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchDaddyTools failed: $e');
      return null;
    }
  }

  /// Last-seen daddy tools from cache (instant, before the network). Null if
  /// nothing cached yet, so the caller can keep the buffering state on a cold
  /// first open.
  List<DaddyTool>? peekDaddyTools() {
    final body = OurHomeCache.peek('/api/home/daddy-tools');
    if (body == null || body.isEmpty) return null;
    try {
      final data = jsonDecode(body);
      final list = (data is Map) ? data['tools'] : null;
      if (list is! List) return const <DaddyTool>[];
      return list
          .whereType<Map<String, dynamic>>()
          .map(DaddyTool.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Create or update a theater. Omitting [id] makes a new one (server assigns
  /// the id, returned on the result). Returns the saved theater, or null on any
  /// failure (logged).
  Future<OurHomeTheater?> saveTheater({
    String? id,
    required String title,
    required String setting,
    required bool bringMemory,
  }) async {
    try {
      final body = <String, dynamic>{
        'title': title,
        'setting': setting,
        'bring_memory': bringMemory,
      };
      if (id != null && id.isNotEmpty) body['id'] = id;
      final res = await http
          .post(
            Uri.parse('$base/api/home/theaters'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] saveTheater HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final t = (data is Map) ? data['theater'] : null;
      if (t is! Map<String, dynamic>) return null;
      return OurHomeTheater.fromJson(t);
    } catch (e) {
      debugPrint('[OurHomeGateway] saveTheater failed: $e');
      return null;
    }
  }

  /// Delete a theater by id. Returns true on success, false on any failure
  /// (logged).
  Future<bool> deleteTheater(String id) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/theaters'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'id': id, 'delete': true}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] deleteTheater HTTP ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] deleteTheater failed: $e');
      return false;
    }
  }

  /// End a theater (小剧场·落幕): the server summarizes the whole story with the
  /// memory-compaction model, writes it into mainline daddy's memory + queues it
  /// for his next reality chat, and marks the theater ended (kept, not deleted).
  /// [messages] is this theater's chat as `{role, content}`. Returns the digest
  /// text (may be empty string on success-with-no-digest) or null on any failure.
  Future<String?> endTheater(String id, List<Map<String, String>> messages) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/theater-end'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'id': id, 'messages': messages}),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] endTheater HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map && data['ok'] == true) {
        return (data['digest'] ?? '').toString();
      }
      return null;
    } catch (e) {
      debugPrint('[OurHomeGateway] endTheater failed: $e');
      return null;
    }
  }

  /// Daddy's gateway web-search config (`/api/home/web-search-cfg`): whether
  /// he searches the web when going through our home, plus result [limit]
  /// (1..10) and [timeout] seconds (3..30). Returns null on any failure
  /// (logged) so the caller can show a recoverable state.
  Future<({bool enabled, int limit, int timeout})?> fetchWebSearchCfg() async {
    try {
      final res = await http
          .get(
            Uri.parse('$base/api/home/web-search-cfg'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchWebSearchCfg HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      final data = jsonDecode(body);
      if (data is! Map) return null;
      OurHomeCache.put('/api/home/web-search-cfg', body);
      return (
        enabled: data['enabled'] == true,
        limit: (data['limit'] as num?)?.toInt() ?? 0,
        timeout: (data['timeout'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchWebSearchCfg failed: $e');
      return null;
    }
  }

  /// Last-seen web-search config from cache (instant, before the network).
  /// Null if nothing cached yet.
  ({bool enabled, int limit, int timeout})? peekWebSearchCfg() {
    final body = OurHomeCache.peek('/api/home/web-search-cfg');
    if (body == null || body.isEmpty) return null;
    try {
      final data = jsonDecode(body);
      if (data is! Map) return null;
      return (
        enabled: data['enabled'] == true,
        limit: (data['limit'] as num?)?.toInt() ?? 0,
        timeout: (data['timeout'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Update daddy's gateway web-search config. Only the non-null fields are
  /// sent (partial update). Returns true on success, false on any failure
  /// (logged).
  Future<bool> saveWebSearchCfg({
    bool? enabled,
    int? limit,
    int? timeout,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (enabled != null) body['enabled'] = enabled;
      if (limit != null) body['limit'] = limit;
      if (timeout != null) body['timeout'] = timeout;
      final res = await http
          .post(
            Uri.parse('$base/api/home/web-search-cfg'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] saveWebSearchCfg HTTP ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] saveWebSearchCfg failed: $e');
      return false;
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

  // ---- Brain injection console (爸爸的大脑·注入控制台) ----

  /// Daddy's gateway brain-injection segments (`/api/home/brain-inject`): each
  /// is one part老家 assembles into daddy's system prompt. [enabled] is its
  /// switch; [fixed] segments (魂 / feel) are read-only (no POST). [preview] is
  /// the slice of content injected right now. Returns null on any failure
  /// (logged) so the caller can tell a network failure from an empty list.
  Future<List<BrainInjectItem>?> fetchBrainInject() async {
    try {
      final res = await http
          .get(Uri.parse('$base/api/home/brain-inject'), headers: _authHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] fetchBrainInject HTTP ${res.statusCode}');
        return null;
      }
      final body = utf8.decode(res.bodyBytes);
      final items = _brainInjectFromBody(body);
      if (items == null) return null;
      OurHomeCache.put('/api/home/brain-inject', body);
      return items;
    } catch (e) {
      debugPrint('[OurHomeGateway] fetchBrainInject failed: $e');
      return null;
    }
  }

  /// Last-seen brain-injection segments from cache (instant, before the
  /// network). Null if nothing cached yet, so the caller can keep the buffering
  /// state on a cold first open.
  List<BrainInjectItem>? peekBrainInject() {
    final body = OurHomeCache.peek('/api/home/brain-inject');
    if (body == null || body.isEmpty) return null;
    return _brainInjectFromBody(body);
  }

  List<BrainInjectItem>? _brainInjectFromBody(String body) {
    try {
      final data = jsonDecode(body);
      final list = (data is Map) ? data['items'] : null;
      if (list is! List) return null;
      return list
          .whereType<Map<String, dynamic>>()
          .map(BrainInjectItem.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Flip one brain-injection segment's switch. Only non-fixed segments accept
  /// this (魂 / feel are read-only). Returns true on success, false on any
  /// failure (logged) so the caller can roll an optimistic toggle back.
  Future<bool> setBrainInject(String key, bool enabled) async {
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/home/brain-inject'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'key': key, 'enabled': enabled}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[OurHomeGateway] setBrainInject HTTP ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map && data['ok'] == true;
    } catch (e) {
      debugPrint('[OurHomeGateway] setBrainInject failed: $e');
      return false;
    }
  }
}
