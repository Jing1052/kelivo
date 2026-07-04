import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'eryu_client.dart';

/// A song the room is already playing when you walk in — surfaced so the page
/// can ask "join what TA is listening to?" instead of hijacking your ears.
class EryuRoomJoin {
  const EryuRoomJoin({required this.song, required this.position, required this.playing});
  final EryuSong song;
  final Duration position;
  final bool playing;
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
      if (st.processingState == ProcessingState.completed) {
        _onCompleted();
      }
    });
    _player.positionStream.listen((_) => notifyListeners());
    _player.durationStream.listen((_) => notifyListeners());
  }

  final AudioPlayer _player = AudioPlayer();
  EryuClient? _client;
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

  void bind(EryuClient client) => _client = client;

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
      await _player.setUrl(url);
      if (seekTo != null && seekTo > Duration.zero) {
        await _player.seek(seekTo);
      }
      if (autoPlay) {
        await _player.play();
      }
      unawaited(eryuSoft(client.recentAdd(song), 'recent add'));
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

  bool get togetherOn => _togetherOn;
  List<String> get partners => List.unmodifiable(_partners);
  bool get hasPartner => _partners.isNotEmpty;
  String get controlledBy => _controlledBy;
  EryuRoomJoin? get joinCandidate => _joinCandidate;

  /// Room-activity feed for the page to surface (SnackBar/toast). Set by the
  /// page in initState, cleared in dispose.
  ValueChanged<String>? onRoomActivity;

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
  bool _canPub() => _togetherOn && _nowMs() >= _muteUntil;
  bool _canPubTransport() => _canPub() && _nowMs() >= _softMuteUntil;
  double _positionSecs() => _player.position.inMilliseconds / 1000.0;

  void _publish(String type, {EryuSong? song, double? position, String? line}) {
    final client = _client;
    if (client == null || !_togetherOn) return;
    final event = <String, dynamic>{
      'user': _user,
      'type': type,
      if (song != null) 'song': song.toJson(),
      if (position != null) 'position': position,
      if (line != null) 'line': line,
    };
    unawaited(eryuSoft(client.roomEvent(event), 'room $type'));
  }

  /// Send a heart / a saved lyric line to the room (used by the player page).
  void publishHeart() {
    if (_canPub()) _publish('heart', song: current);
  }

  void publishQuote(String line) {
    if (_canPub()) _publish('quote', song: current, line: line);
  }

  Future<void> enterTogether(String user) async {
    final client = _client;
    if (client == null || _togetherOn) return;
    _togetherOn = true;
    _user = user.trim().isEmpty ? 'Cing' : user.trim();
    _muteUntil = 0;
    _softMuteUntil = 0;
    _controlledBy = '';
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
    notifyListeners();
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
    }
    notifyListeners();
  }

  void _activity(String text) => onRoomActivity?.call(text);

  @override
  void dispose() {
    _togetherOn = false;
    _player.dispose();
    super.dispose();
  }
}
