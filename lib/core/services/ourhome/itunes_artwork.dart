import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resolves real artwork (album covers, movie/TV posters) via Apple's free
/// iTunes Search API — no key, no auth. Mirrors the web home's approach:
/// query by title (+ artist), take results[0].artworkUrl100, upscale to 600px.
///
/// Results are cached in memory for the app session; misses are remembered too
/// so we don't refetch a query that has no artwork.
class ItunesArtwork {
  ItunesArtwork._();

  // term|media -> url ('' means "looked up, none found")
  static final Map<String, String> _cache = {};
  static final Map<String, Future<String?>> _inflight = {};

  /// [media] is one of 'music', 'movie', 'tvShow', 'all'.
  static Future<String?> lookup(String term, {String media = 'music'}) {
    final q = term.trim();
    if (q.isEmpty) return Future.value(null);
    final key = '$q|$media';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached.isEmpty ? null : cached);
    return _inflight[key] ??= _fetch(q, media, key);
  }

  static Future<String?> _fetch(String term, String media, String key) async {
    try {
      // 苹果中国区没有电影/剧集目录：movie/tvShow/all 在 CN 区一律空手而归（→没海报）。
      // 所以非音乐一律走有完整片库的美区；音乐留 CN（本地化歌曲封面更准）。
      final country = media == 'music' ? 'CN' : 'US';
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': term,
        'media': media,
        'limit': '1',
        'country': country,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final results = (data is Map) ? data['results'] : null;
        if (results is List && results.isNotEmpty) {
          final art = (results.first['artworkUrl100'] ?? '').toString();
          if (art.isNotEmpty) {
            final big = art.replaceAll('100x100', '600x600');
            _cache[key] = big;
            return big;
          }
        }
      }
      _cache[key] = '';
      return null;
    } catch (e) {
      debugPrint('[ItunesArtwork] lookup failed for "$term": $e');
      return null; // transient: don't poison the cache, allow retry later
    } finally {
      _inflight.remove(key);
    }
  }

  /// Search songs by free-text [query] via the same iTunes Search API. Returns
  /// up to [limit] candidates (title / artist / artwork). Empty list on no
  /// match or transient error — callers should offer a free-text fallback so a
  /// NetEase-only song can still be added.
  static Future<List<ItunesSong>> searchSongs(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': q,
        'media': 'music',
        'entity': 'song',
        'limit': '$limit',
        'country': 'CN',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final results = (data is Map) ? data['results'] : null;
      if (results is! List) return const [];
      final out = <ItunesSong>[];
      for (final r in results) {
        if (r is! Map) continue;
        final title = (r['trackName'] ?? '').toString().trim();
        final artist = (r['artistName'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final art = (r['artworkUrl100'] ?? '').toString();
        out.add(ItunesSong(
          title: title,
          artist: artist,
          artworkUrl: art.isEmpty ? '' : art.replaceAll('100x100', '300x300'),
        ));
      }
      return out;
    } catch (e) {
      debugPrint('[ItunesArtwork] searchSongs failed for "$q": $e');
      return const [];
    }
  }
}

/// One song candidate from [ItunesArtwork.searchSongs].
class ItunesSong {
  const ItunesSong({
    required this.title,
    required this.artist,
    required this.artworkUrl,
  });
  final String title;
  final String artist;
  final String artworkUrl;
}
