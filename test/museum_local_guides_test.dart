import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/museum/museum_api.dart';
import 'package:Kelivo/core/services/museum/museum_local_guides.dart';

void main() {
  const artwork = MuseumArtwork(
    source: 'met',
    id: 'unknown',
    title: 'A quiet landscape',
    artist: 'Unknown artist',
    date: '1888',
    medium: 'Oil on canvas',
    imageUrl: 'https://example.com/full.jpg',
    thumbUrl: 'https://example.com/thumb.jpg',
  );

  test('every public wing has an offline Chinese guide', () {
    const wingIds = [
      'curated',
      'renaissance',
      'impressionism',
      'sculpture',
      'ancient',
      'china',
      'japan',
      'egypt',
      'porcelain',
      'jewelry',
      'armor',
      'fashion',
      'gugong',
      'louvre',
      'versailles',
      'life',
      'fossils',
      'apod',
    ];

    for (final wingId in wingIds) {
      final guide = MuseumLocalGuides.forArtwork(artwork, wingId: wingId);
      expect(guide, isNotEmpty, reason: wingId);
      expect(guide.length, greaterThan(80), reason: wingId);
    }
  });

  test('a known artist receives a more specific story', () {
    const vanGogh = MuseumArtwork(
      source: 'met',
      id: '436535',
      title: 'Wheat Field with Cypresses',
      artist: 'Vincent van Gogh',
      date: '1889',
      medium: 'Oil on canvas',
      imageUrl: 'https://example.com/full.jpg',
      thumbUrl: 'https://example.com/thumb.jpg',
    );

    final guide = MuseumLocalGuides.forArtwork(
      vanGogh,
      wingId: 'impressionism',
    );
    expect(guide, contains('梵高'));
    expect(guide, contains('圣雷米'));
  });

  test('unknown artwork falls back to its wing without a network call', () {
    final guide = MuseumLocalGuides.forArtwork(
      artwork,
      wingId: 'renaissance',
    );
    expect(guide, contains('文艺复兴'));
  });

  test('two unknown works in the same wing do not repeat the same guide', () {
    const second = MuseumArtwork(
      source: 'met',
      id: 'second',
      title: 'Portrait of a Musician',
      artist: 'A Renaissance painter',
      date: '1510',
      medium: 'Oil on wood',
      imageUrl: 'https://example.com/second.jpg',
      thumbUrl: 'https://example.com/second-thumb.jpg',
    );

    final firstGuide = MuseumLocalGuides.forArtwork(
      artwork,
      wingId: 'renaissance',
    );
    final secondGuide = MuseumLocalGuides.forArtwork(
      second,
      wingId: 'renaissance',
    );
    expect(firstGuide, isNot(secondGuide));
    expect(firstGuide, contains('A quiet landscape'));
    expect(secondGuide, contains('Portrait of a Musician'));
    expect(secondGuide, contains('1510'));
  });

  test('official source context survives artwork cache round-trip', () {
    const withContext = MuseumArtwork(
      source: 'apod',
      id: '2026-07-11',
      title: 'A Nebula',
      artist: 'NASA',
      date: '2026-07-11',
      medium: 'Astronomy image',
      imageUrl: 'https://example.com/nebula.jpg',
      thumbUrl: 'https://example.com/nebula-thumb.jpg',
      sourceContext: 'Official explanation for this exact image.',
    );

    final restored = MuseumArtwork.fromJson(withContext.toJson());
    expect(restored?.sourceContext, withContext.sourceContext);
  });

  test('unknown wing and source still receive a safe guide', () {
    const unknown = MuseumArtwork(
      source: 'new-museum',
      id: '1',
      title: '',
      artist: '',
      date: '',
      medium: '',
      imageUrl: 'https://example.com/full.jpg',
      thumbUrl: 'https://example.com/thumb.jpg',
    );

    final guide = MuseumLocalGuides.forArtwork(unknown, wingId: 'new-wing');
    expect(guide, contains('先别急着找标准答案'));
  });
}
