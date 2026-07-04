import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/eryu/eryu_client.dart';

// eryu returns songs with two id conventions: search/daily use `id`, stored
// playlist/recent/room songs use `songId`. EryuSong must normalize both to a
// single `songId` (the web client's `s.id || s.songId` rule) and always emit
// `songId` — a mismatch here silently breaks playback and room sync.
void main() {
  group('EryuSong id normalization', () {
    test('search-style "id" (numeric) becomes string songId', () {
      final s = EryuSong.fromJson({'id': 123, 'name': 'A', 'artist': 'B', 'cover': 'c'});
      expect(s.songId, '123');
      expect(s.name, 'A');
      expect(s.artist, 'B');
    });

    test('stored-style "songId" is kept', () {
      final s = EryuSong.fromJson({'songId': '456', 'name': 'X', 'artist': 'Y'});
      expect(s.songId, '456');
      expect(s.cover, ''); // missing fields default to empty, not null
    });

    test('toJson always emits songId and never id', () {
      final s = EryuSong.fromJson({'id': 7, 'name': 'N', 'artist': 'R', 'cover': 'u', 'album': 'al'});
      final j = s.toJson();
      expect(j['songId'], '7');
      expect(j['album'], 'al');
      expect(j.containsKey('id'), isFalse);
    });

    test('missing id yields empty songId (never throws)', () {
      final s = EryuSong.fromJson({'name': 'N'});
      expect(s.songId, '');
      expect(s.name, 'N');
    });
  });

  group('EryuPlaylist', () {
    test('parses count as int and tolerates missing fields', () {
      final p = EryuPlaylist.fromJson({'id': 'liked', 'name': 'Liked', 'count': 12});
      expect(p.id, 'liked');
      expect(p.count, 12);
      expect(p.cover, '');
    });
  });
}
