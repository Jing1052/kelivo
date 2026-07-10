import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';

import 'eryu_client.dart';
import 'eryu_lyrics.dart';

/// A song the room is already playing when you walk in — surfaced so the page
/// can ask "join what TA is listening to?" instead of hijacking your ears.
class EryuRoomJoin {
  const EryuRoomJoin({required this.song, required this.position, required this.playing});
  final EryuSong song;
  final Duration position;
  final bool playing;
}

/// One line in the shared room's activity/chat timeline — a track change, a
/// heart, a saved lyric, a hello/bye, or a "边听边说" chat message. Mirrors the
/// eryu web client's feed entries so the native companion panel reads the same.
class RoomFeedEntry {
  const RoomFeedEntry({
    required this.ts,
    required this.user,
    required this.type,
    required this.mine,
    this.songName = '',
    this.cover = '',
    this.line = '',
    this.text = '',
  });
  final int ts;
  final String user;
  final String type;
  final bool mine;
  final String songName;
  final String cover;
  final String line;
  final String text;
}

/// Single source of truth for music playback AND the listen-together room.
///
/// The room engine is ported straight from the eryu web client's `together`
/// module — same anti-echo scheme: [_muteUntil] silences all publishing for a
/// window after applying a remote event; [_softMuteUntil] silences only
/// transport (play/pause/seek) briefly after a local track swap; both clients
/// auto-advancing to the same song is de-duped. Pages subscribe via provider
/// and never touch [just_audio] directly.
class EryuPlayerController extends ChangeNotifier {
  EryuPlayerController() {
    _player.playerStateStream.listen((st) {
      notifyListeners();
      // 在场心跳：播放⇄暂停一变，立刻报一次（暂停后计时器就不再报，
      // 老家 3 分钟没心跳自然当"不在放了"）。
      if (st.playing != _npWasPlaying) {
        _npWasPlaying = st.playing;
        _reportNowPlaying();
      }
      if (st.processingState == ProcessingState.completed) {
        _onCompleted();
      }
    });
    _player.positionStream.listen((_) => notifyListeners());
    _player.durationStream.listen((_) => notifyListeners());
    _npBeat = Timer.periodic(const Duration(seconds: 25), (_) {
      if (playing) _reportNowPlaying();
    });
    // 恢复上次的音量（聊天音乐卡的滑条调过就记住，重启不回弹满格）。
    unawaited(SharedPreferences.getInstance().then((p) {
      final v = p.getDouble(_volKey);
      if (v != null) {
        unawaited(_player.setVolume(v.clamp(0.0, 1.0).toDouble()));
        notifyListeners();
      }
    }));
  }

  final AudioPlayer _player = AudioPlayer();
  EryuClient? _client;
  OurHomeGateway? _gw;
  bool _sessionReady = false;

  List<EryuSong> _queue = <EryuSong>[];
  int _index = -1;
  bool _roam = false;
  bool _loadingSong = false;

  EryuSong? get current => (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  List<EryuSong> get queue => List.unmodifiable(_queue);
  bool get playing => _player.playing;
  bool get roam => _roam;
  bool get hasSong => current != null;
  bool get loadingSong => _loadingSong;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;

  // ── 音量（0..1，薄包 just_audio；只影响 App 内播放，与系统音量键叠加）──────
  static const String _volKey = 'eryu_volume_v1';
  double get volume => _player.volume;
  Future<void> setVolume(double v) async {
    final vv = v.clamp(0.0, 1.0).toDouble();
    await _player.setVolume(vv);
    notifyListeners();
    unawaited(SharedPreferences.getInstance().then((p) => p.setDouble(_volKey, vv)));
  }

  // ── 歌曲本地缓存（Documents/music_cache/<songId>.mp3，LRU 上限 60 首）────
  Directory? _musicCacheDir;

  Future<File> _songCacheFile(String songId) async {
    var dir = _musicCacheDir;
    if (dir == null) {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}/music_cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _musicCacheDir = dir;
    }
    final safe = songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$safe.mp3');
  }

  /// 只留最近听的 60 首（连 LockCachingAudioSource 的 .part/.mime 一起清），
  /// 缓存永远长不满她的手机。
  Future<void> _trimMusicCache() async {
    final dir = _musicCacheDir;
    if (dir == null) return;
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp3'))
          .toList()
        ..sort(
          (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
        );
      while (files.length > 60) {
        final victim = files.removeAt(0);
        for (final side in ['', '.part', '.mime']) {
          final f = File('${victim.path}$side');
          if (f.existsSync()) f.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('[eryu] music cache trim failed: $e');
    }
  }

  void bind(EryuClient client) => _client = client;

  /// 老家网关（可空——没配就不上报）。谁 bind 了 eryu client，谁顺手把网关也
  /// 递进来，播放器就开始打在场心跳。
  void bindGateway(OurHomeGateway? gw) => _gw = gw;

  // ── 歌词（中控养一份，卡片/播放页/心跳都吃这份，别各拉各的）────────────────
  List<EryuLyricLine> _lyrics = const [];
  String _lyricsSongId = '';

  /// Parsed LRC of [current]; empty while loading or when the song has none.
  List<EryuLyricLine> get lyrics => _lyrics;

  /// The lyric line being sung right now ('' when none).
  String currentLyricLine() {
    final i = EryuLyrics.activeIndex(_lyrics, position);
    return (i >= 0 && i < _lyrics.length) ? _lyrics[i].text : '';
  }

  void _loadLyrics() {
    final id = current?.songId ?? '';
    final client = _client;
    if (id == _lyricsSongId) return;
    _lyricsSongId = id;
    _lyrics = const [];
    if (id.isEmpty || client == null) return;
    eryuSoft(client.lyric(id), 'lyric').then((d) {
      if (_lyricsSongId != id) return;
      _lyrics = EryuLyrics.parse(
        (d?['lrc'] ?? '').toString(),
        (d?['tlyric'] ?? '').toString(),
      );
      notifyListeners();
    });
  }

  // ── 在场心跳：换歌/播放暂停/每 25s 把"正在放"报给老家 ─────────────────────
  Timer? _npBeat;
  bool _npWasPlaying = false;

  void _reportNowPlaying() {
    final gw = _gw;
    final song = current;
    if (gw == null || song == null || song.name.isEmpty) return;
    unawaited(softFetch(
      gw.reportNowPlaying(
        title: song.name,
        artist: song.artist,
        playing: playing,
        position: position,
        duration: duration,
        curLyric: currentLyricLine(),
      ),
      'now-playing beat',
    ));
  }

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _sessionReady = true;
    } catch (e) {
      debugPrint('[eryu] audio session config failed: $e');
    }
  }

  Future<void> playSong(EryuSong song, {List<EryuSong>? queue}) async {
    if (queue != null && queue.isNotEmpty) {
      _queue = List<EryuSong>.from(queue);
      final i = _queue.indexWhere((s) => s.songId == song.songId);
      if (i >= 0) {
        _index = i;
      } else {
        _queue.insert(0, song);
        _index = 0;
      }
    } else {
      _queue = <EryuSong>[song];
      _index = 0;
    }
    notifyListeners();
    // A local track swap: hush transport echo for a beat, then announce it.
    _softMuteUntil = _nowMs() + 1000;
    await _loadCurrent();
    if (_canPubTransport()) _publish('track', song: current, position: 0);
  }

  Future<void> _loadCurrent({Duration? seekTo, bool autoPlay = true}) async {
    final song = current;
    final client = _client;
    if (song == null || client == null) return;
    _loadingSong = true;
    notifyListeners();
    await _ensureSession();
    try {
      final url = await client.songUrl(song.songId);
      if (url == null) {
        debugPrint('[eryu] no playable url for ${song.name}');
        return;
      }
      _loadLyrics();
      // 边播边存：LockCachingAudioSource 首次播放把整首落到本地文件；之后
      // 同一首直接从盘上读（cacheFile 按 songId 定死，不怕播放 URL 每次
      // 过期换链），不再"加载好久好久"。缓存源出任何问题都退回直连流。
      try {
        final cacheFile = await _songCacheFile(song.songId);
        await _player.setAudioSource(
          LockCachingAudioSource(Uri.parse(url), cacheFile: cacheFile),
        );
      } catch (e) {
        debugPrint('[eryu] cached source failed, falling back to stream: $e');
        await _player.setUrl(url);
      }
      unawaited(_trimMusicCache());
      if (seekTo != null && seekTo > Duration.zero) {
        await _player.seek(seekTo);
      }
      if (autoPlay) {
        await _player.play();
      }
      unawaited(eryuSoft(client.recentAdd(song), 'recent add'));
      _reportNowPlaying();
    } catch (e) {
      debugPrint('[eryu] load failed for ${song.name}: $e');
    } finally {
      _loadingSong = false;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
      if (_canPub()) _publish('pause', position: _positionSecs());
    } else {
      await _player.play();
      if (_canPub()) _publish('play', position: _positionSecs());
    }
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_index < _queue.length - 1) {
      _index++;
      _softMuteUntil = _nowMs() + 1000;
      await _loadCurrent();
      if (_canPubTransport()) _publish('track', song: current, position: 0);
    } else if (_roam) {
      await _loadRoam();
    } else {
      _index = 0;
      _softMuteUntil = _nowMs() + 1000;
      await _loadCurrent();
      if (_canPubTransport()) _publish('track', song: current, position: 0);
    }
  }

  Future<void> prev() async {
    if (_queue.isEmpty) return;
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_index > 0) {
      _index--;
      _softMuteUntil = _nowMs() + 1000;
      await _loadCurrent();
      if (_canPubTransport()) _publish('track', song: current, position: 0);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> seek(Duration to) async {
    await _player.seek(to);
    if (_canPub()) _publish('seek', position: _positionSecs());
    notifyListeners();
  }

  void setRoam(bool value) {
    if (_roam == value) return;
    _roam = value;
    notifyListeners();
  }

  Future<void> _loadRoam() async {
    final client = _client;
    if (client == null) return;
    final more = await eryuSoft(client.roam(current?.songId), 'roam');
    if (more != null && more.isNotEmpty) {
      _queue.addAll(more);
      _index++;
      _softMuteUntil = _nowMs() + 1000;
      await _loadCurrent();
      if (_canPubTransport()) _publish('track', song: current, position: 0);
    }
  }

  void _onCompleted() {
    final done = current;
    unawaited(next());
    if (done != null && _togetherOn && _partners.isNotEmpty) {
      final client = _client;
      if (client != null) unawaited(eryuSoft(client.listenComplete(done.songId, together: true), 'listen-complete'));
    }
  }

  // ── Listen Together ───────────────────────────────────────────────────────

  bool _togetherOn = false;
  String _user = 'Cing';
  int _lastSeq = 0;
  List<String> _partners = const <String>[];
  bool _polling = false;
  int _muteUntil = 0;
  int _softMuteUntil = 0;
  String _controlledBy = '';
  EryuRoomJoin? _joinCandidate;

  // Companion panel state: the activity/chat timeline + accumulated together-time.
  static const String _secsKey = 'music_tg_secs_v1';
  static const Set<String> _feedTypes = {
    'track', 'play', 'pause', 'heart', 'quote', 'hello', 'bye', 'say',
  };
  final List<RoomFeedEntry> _feed = <RoomFeedEntry>[];
  int _togetherSecs = 0;
  Timer? _tick;

  bool get togetherOn => _togetherOn;
  List<String> get partners => List.unmodifiable(_partners);
  bool get hasPartner => _partners.isNotEmpty;
  String get controlledBy => _controlledBy;
  EryuRoomJoin? get joinCandidate => _joinCandidate;
  List<RoomFeedEntry> get feed => List.unmodifiable(_feed);
  int get togetherSecs => _togetherSecs;
  String get roomUser => _user;

  /// Room-activity feed for the page to surface (SnackBar/toast). Set by the
  /// page in initState, cleared in dispose.
  ValueChanged<String>? onRoomActivity;

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
  bool _canPub() => _togetherOn && _nowMs() >= _muteUntil;
  bool _canPubTransport() => _canPub() && _nowMs() >= _softMuteUntil;
  double _positionSecs() => _player.position.inMilliseconds / 1000.0;

  void _publish(String type, {EryuSong? song, double? position, String? line, String? text}) {
    final client = _client;
    if (client == null || !_togetherOn) return;
    final event = <String, dynamic>{
      'user': _user,
      'type': type,
      if (song != null) 'song': song.toJson(),
      if (position != null) 'position': position,
      if (line != null) 'line': line,
      if (text != null) 'text': text,
    };
    if (_feedTypes.contains(type)) {
      final s = song ?? (type == 'say' ? null : current);
      _logFeed(_user, type, mine: true, song: s, line: line ?? '', text: text ?? '');
    }
    unawaited(eryuSoft(client.roomEvent(event), 'room $type'));
  }

  void _logFeed(String user, String type,
      {required bool mine, EryuSong? song, String line = '', String text = ''}) {
    if (!_feedTypes.contains(type)) return;
    _feed.add(RoomFeedEntry(
      ts: _nowMs(),
      user: user,
      type: type,
      mine: mine,
      songName: song?.name ?? '',
      cover: song?.cover ?? '',
      line: line,
      text: text,
    ));
    if (_feed.length > 80) _feed.removeRange(0, _feed.length - 80);
    notifyListeners();
  }

  /// Send a heart / a saved lyric line to the room (used by the player page).
  void publishHeart() {
    if (_canPub()) _publish('heart', song: current);
  }

  void publishQuote(String line) {
    if (_canPub()) _publish('quote', song: current, line: line);
  }

  /// Mirror a chat line into the eryu sync room as a `say` event, WITHOUT
  /// logging it locally (callers log via [feedSay] so the line shows up with
  /// or without a room). No-op when no room is open — talking to Llaude never
  /// requires one; the room only relays to another device/web client.
  void sayToRoomPeers(String text) {
    final t = text.trim();
    final client = _client;
    if (t.isEmpty || !_togetherOn || client == null) return;
    unawaited(eryuSoft(
      client.roomEvent({'user': _user, 'type': 'say', 'text': t}),
      'room say',
    ));
  }

  /// Append a chat line to the timeline WITHOUT touching the eryu sync room —
  /// used for the always-present Llaude companion (his replies come from the
  /// home gateway, not a room peer). [mine] false = it's from him.
  void feedSay({required String user, required bool mine, required String text}) {
    final t = text.trim();
    if (t.isEmpty) return;
    _logFeed(user, 'say', mine: mine, text: t);
  }

  Future<void> enterTogether(String user) async {
    final client = _client;
    if (client == null || _togetherOn) return;
    _togetherOn = true;
    _user = user.trim().isEmpty ? 'Cing' : user.trim();
    _muteUntil = 0;
    _softMuteUntil = 0;
    _controlledBy = '';
    _feed.clear();
    _startTick();
    notifyListeners();

    final info = await eryuSoft(client.roomInfo(_user), 'room info');
    _lastSeq = (info?['seq'] as num?)?.toInt() ?? 0;
    _partners = _usersFrom(info);
    _publish('hello');

    final state = info?['state'];
    if (_partners.isNotEmpty && state is Map && state['song'] is Map) {
      final song = EryuSong.fromJson((state['song'] as Map).cast<String, dynamic>());
      final pos = ((state['position'] as num?)?.toDouble() ?? 0.0);
      final isPlaying = state['playing'] == true;
      // Don't hijack — offer to join.
      _joinCandidate = EryuRoomJoin(
        song: song,
        position: Duration(milliseconds: (pos * 1000).round()),
        playing: isPlaying,
      );
    } else if (current != null && _player.playing) {
      _publish('track', song: current, position: _positionSecs());
    }
    notifyListeners();
    unawaited(_pollLoop());
  }

  Future<void> leaveTogether() async {
    if (!_togetherOn) return;
    _publish('bye');
    _togetherOn = false;
    _partners = const <String>[];
    _controlledBy = '';
    _joinCandidate = null;
    _stopTick(persist: true);
    notifyListeners();
  }

  // Accumulate shared-listening seconds only while a partner is actually in the
  // room; persist every 15s (and on leave) so "一起听了 X" survives restarts.
  void _startTick() {
    _tick?.cancel();
    unawaited(SharedPreferences.getInstance().then((p) {
      _togetherSecs = p.getInt(_secsKey) ?? 0;
      notifyListeners();
    }));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_togetherOn || _partners.isEmpty) return;
      _togetherSecs++;
      if (_togetherSecs % 15 == 0) _persistSecs();
      notifyListeners();
    });
  }

  void _stopTick({bool persist = false}) {
    _tick?.cancel();
    _tick = null;
    if (persist) _persistSecs();
  }

  void _persistSecs() {
    final secs = _togetherSecs;
    unawaited(SharedPreferences.getInstance().then((p) => p.setInt(_secsKey, secs)));
  }

  Future<void> acceptJoin() async {
    final join = _joinCandidate;
    _joinCandidate = null;
    notifyListeners();
    if (join == null) return;
    _muteUntil = _nowMs() + 5000;
    _queue = <EryuSong>[join.song];
    _index = 0;
    await _loadCurrent(seekTo: join.position, autoPlay: join.playing);
  }

  void dismissJoin() {
    _joinCandidate = null;
    notifyListeners();
  }

  List<String> _usersFrom(Map<String, dynamic>? d) {
    final users = (d?['users'] as List? ?? const []).whereType<String>().toList();
    return users.where((u) => u != _user).toList();
  }

  Future<void> _pollLoop() async {
    if (_polling) return;
    _polling = true;
    final client = _client;
    while (_togetherOn && client != null) {
      try {
        final d = await client.roomPoll(_lastSeq, _user);
        if (!_togetherOn) break;
        final seq = (d['seq'] as num?)?.toInt();
        if (seq != null) _lastSeq = seq;
        final prev = _partners.join(',');
        _partners = _usersFrom(d);
        if (_partners.join(',') != prev) notifyListeners();
        final events = (d['events'] as List? ?? const []).whereType<Map>();
        for (final e in events) {
          if (e['user'] == _user) continue;
          _applyRoomEvent(e.cast<String, dynamic>());
        }
      } catch (e) {
        if (!_togetherOn) break;
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    _polling = false;
  }

  void _applyRoomEvent(Map<String, dynamic> e) {
    final who = (e['user'] ?? '?').toString();
    final type = (e['type'] ?? '').toString();
    final songJson = e['song'];
    final pos = (e['position'] as num?)?.toDouble();

    if (type == 'track' || type == 'play' || type == 'pause' || type == 'seek') {
      _controlledBy = who;
    }

    if (_feedTypes.contains(type)) {
      EryuSong? feedSong;
      if (songJson is Map) {
        try {
          feedSong = EryuSong.fromJson(songJson.cast<String, dynamic>());
        } catch (_) {}
      }
      _logFeed(who, type,
          mine: false,
          song: feedSong ?? (type == 'say' ? null : current),
          line: (e['line'] ?? '').toString(),
          text: (e['text'] ?? '').toString());
    }

    switch (type) {
      case 'track':
        if (songJson is Map) {
          final song = EryuSong.fromJson(songJson.cast<String, dynamic>());
          // Both clients auto-advanced to the same queued song — don't restart.
          if (song.songId == current?.songId && _player.playing && _player.position.inSeconds < 8) {
            return;
          }
          _muteUntil = _nowMs() + 5000;
          _queue = <EryuSong>[song];
          _index = 0;
          final seekTo = (pos != null && pos > 2) ? Duration(milliseconds: (pos * 1000).round()) : null;
          unawaited(_loadCurrent(seekTo: seekTo));
          _activity('$who ▶ ${song.name}');
        }
        break;
      case 'play':
        _muteUntil = _nowMs() + 1200;
        if (pos != null && (_player.position.inMilliseconds - (pos * 1000)).abs() > 2000) {
          unawaited(_player.seek(Duration(milliseconds: (pos * 1000).round())));
        }
        unawaited(_player.play());
        _activity('$who ▶');
        break;
      case 'pause':
        _muteUntil = _nowMs() + 1200;
        unawaited(_player.pause());
        _activity('$who ⏸');
        break;
      case 'seek':
        if (pos != null) {
          _muteUntil = _nowMs() + 1200;
          unawaited(_player.seek(Duration(milliseconds: (pos * 1000).round())));
        }
        break;
      case 'heart':
        _activity('$who ♥ ${songJson is Map ? (songJson['name'] ?? '') : ''}');
        break;
      case 'quote':
        _activity('$who 记下一句：${(e['line'] ?? '').toString()}');
        break;
      case 'hello':
        _activity('$who 来了');
        break;
      case 'bye':
        _activity('$who 离开了');
        break;
      case 'say':
        _activity('$who：${(e['text'] ?? '').toString()}');
        break;
    }
    notifyListeners();
  }

  void _activity(String text) => onRoomActivity?.call(text);

  @override
  void dispose() {
    _togetherOn = false;
    _stopTick(persist: true);
    _npBeat?.cancel();
    _player.dispose();
    super.dispose();
  }
}
