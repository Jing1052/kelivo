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
