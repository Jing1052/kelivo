import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'eryu_client.dart';

/// Single source of truth for music playback. Pages subscribe via provider and
/// never touch [just_audio] directly. The listen-together engine (Step 2) will
/// extend this same controller.
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

  /// Attach (or refresh) the client used to resolve audio URLs. Cheap value
  /// object; the page re-binds on each load so a changed token/base takes hold.
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

  /// Play [song], optionally seeding the up-next queue with the list it came
  /// from (so next/prev walks that list).
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
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
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
      await _player.play();
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
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_index < _queue.length - 1) {
      _index++;
      await _loadCurrent();
    } else if (_roam) {
      await _loadRoam();
    } else {
      // List loop back to the top.
      _index = 0;
      await _loadCurrent();
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
      await _loadCurrent();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> seek(Duration to) async {
    await _player.seek(to);
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
      await _loadCurrent();
    }
  }

  void _onCompleted() {
    unawaited(next());
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
