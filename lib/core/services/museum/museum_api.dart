import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// 美术馆 (The Gallery) — artwork data straight from three museums' free
/// open-access APIs, called from the app itself (no key, no backend proxy):
///
///   met — The Metropolitan Museum of Art  (collectionapi.metmuseum.org)
///   aic — The Art Institute of Chicago    (api.artic.edu)
///   cma — The Cleveland Museum of Art     (openaccess-api.clevelandart.org)
///
/// Browse/search fan out to all three and merge whatever answered — each
/// source fails independently (房间页多数据源一律独立失败, study_page
/// pitfall 2026-07-02); an all-sources failure surfaces as an empty list and
/// the page shows a real error state instead of pretending.
class MuseumArtwork {
  const MuseumArtwork({
    required this.source,
    required this.id,
    required this.title,
    required this.artist,
    required this.date,
    required this.medium,
    required this.imageUrl,
    required this.thumbUrl,
    this.infoUrl = '',
  });

  /// 'met' | 'aic' | 'cma'
  final String source;
  final String id;
  final String title;
  final String artist;
  final String date;
  final String medium;
  final String imageUrl;
  final String thumbUrl;

  /// The museum's own object page (for "去官网看看").
  final String infoUrl;

  /// Stable cross-source key — also the per-artwork chat-history key.
  String get key => '$source:$id';

  Map<String, String> toJson() => {
        's': source,
        'i': id,
        't': title,
        'a': artist,
        'd': date,
        'm': medium,
        'img': imageUrl,
        'th': thumbUrl,
        'u': infoUrl,
      };

  static MuseumArtwork? fromJson(dynamic j) {
    if (j is! Map) return null;
    String s(String k) => (j[k] ?? '').toString();
    if (s('s').isEmpty || s('img').isEmpty) return null;
    return MuseumArtwork(
      source: s('s'),
      id: s('i'),
      title: s('t'),
      artist: s('a'),
      date: s('d'),
      medium: s('m'),
      imageUrl: s('img'),
      thumbUrl: s('th').isEmpty ? s('img') : s('th'),
      infoUrl: s('u'),
    );
  }

  String museumName(bool zh) => switch (source) {
    'met' => zh ? '大都会艺术博物馆' : 'The Met',
    'aic' => zh ? '芝加哥艺术学院' : 'Art Institute of Chicago',
    'cma' => zh ? '克利夫兰艺术博物馆' : 'Cleveland Museum of Art',
    _ => source,
  };
}

class MuseumApi {
  MuseumApi._();

  static const Duration _timeout = Duration(seconds: 12);

  /// The Met's search endpoint requires a q term, so random browsing samples
  /// from a rotating pool of broad, painting-friendly seeds.
  static const List<String> _metSeeds = [
    'landscape',
    'portrait',
    'flowers',
    'garden',
    'sea',
    'moon',
    'gold',
    'dragon',
    'horse',
    'dance',
    'winter',
    'spring',
  ];

  static Future<dynamic> _getJson(String url) async {
    final res = await http.get(Uri.parse(url)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('museum api ${res.statusCode}', Uri.parse(url));
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static String _s(dynamic v) => (v ?? '').toString().trim();

  // ---- Art Institute of Chicago ------------------------------------------

  static const String _aicFields =
      'id,title,artist_display,date_display,medium_display,image_id';

  static MuseumArtwork? _aicParse(Map<String, dynamic> d) {
    final imageId = _s(d['image_id']);
    if (imageId.isEmpty) return null;
    final iiif = 'https://www.artic.edu/iiif/2/$imageId';
    final id = _s(d['id']);
    return MuseumArtwork(
      source: 'aic',
      id: id,
      title: _s(d['title']),
      artist: _s(d['artist_display']),
      date: _s(d['date_display']),
      medium: _s(d['medium_display']),
      imageUrl: '$iiif/full/843,/0/default.jpg',
      thumbUrl: '$iiif/full/600,/0/default.jpg',
      infoUrl: 'https://www.artic.edu/artworks/$id',
    );
  }

  static Future<List<MuseumArtwork>> _aicFetch({
    String q = '',
    required int page,
    int limit = 8,
    String extra = '',
  }) async {
    final query = q.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(q)}';
    // Bracket params percent-encoded — Dart's Uri is strict about raw [] in
    // queries; AIC decodes them fine (probed 2026-07-10). Base filter uses the
    // ES bool form so wings can append extra must-clauses (index 1+) via
    // [extra] — bool/term/match/range all verified against the live API.
    final j = await _getJson(
      'https://api.artic.edu/api/v1/artworks/search'
      '?query%5Bbool%5D%5Bmust%5D%5B0%5D%5Bterm%5D%5Bis_public_domain%5D=true'
      '$extra$query'
      '&limit=$limit&page=$page&fields=$_aicFields',
    );
    final data = (j['data'] as List?) ?? const [];
    return [
      for (final d in data)
        if (d is Map<String, dynamic>)
          if (_aicParse(d) case final a?) a,
    ];
  }

  // ---- Cleveland Museum of Art -------------------------------------------

  static const String _cmaFields =
      'id,title,creators,creation_date,technique,url,images';

  static MuseumArtwork? _cmaParse(Map<String, dynamic> d) {
    final images = d['images'];
    final web = images is Map ? images['web'] : null;
    final img = web is Map ? _s(web['url']) : '';
    if (img.isEmpty) return null;
    final creators = d['creators'];
    var artist = '';
    if (creators is List && creators.isNotEmpty && creators.first is Map) {
      artist = _s((creators.first as Map)['description']);
    }
    return MuseumArtwork(
      source: 'cma',
      id: _s(d['id']),
      title: _s(d['title']),
      artist: artist,
      date: _s(d['creation_date']),
      medium: _s(d['technique']),
      imageUrl: img,
      thumbUrl: img,
      infoUrl: _s(d['url']),
    );
  }

  static Future<List<MuseumArtwork>> _cmaFetch({
    String q = '',
    required int skip,
    int limit = 8,
    String extra = '',
  }) async {
    final query = q.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(q)}';
    final j = await _getJson(
      'https://openaccess-api.clevelandart.org/api/artworks/'
      '?has_image=1$query$extra&limit=$limit&skip=$skip&fields=$_cmaFields',
    );
    final data = (j['data'] as List?) ?? const [];
    return [
      for (final d in data)
        if (d is Map<String, dynamic>)
          if (_cmaParse(d) case final a?) a,
    ];
  }

  // ---- The Met -------------------------------------------------------------

  static Future<MuseumArtwork?> _metObject(int id) async {
    final d = await _getJson(
      'https://collectionapi.metmuseum.org/public/collection/v1/objects/$id',
    );
    if (d is! Map<String, dynamic>) return null;
    final full = _s(d['primaryImage']);
    final small = _s(d['primaryImageSmall']);
    if (full.isEmpty && small.isEmpty) return null;
    return MuseumArtwork(
      source: 'met',
      id: '$id',
      title: _s(d['title']),
      artist: _s(d['artistDisplayName']),
      date: _s(d['objectDate']),
      medium: _s(d['medium']),
      imageUrl: full.isEmpty ? small : full,
      thumbUrl: small.isEmpty ? full : small,
      infoUrl: _s(d['objectURL']),
    );
  }

  /// Search returns ids only; details are one request per object, so [take]
  /// stays small and failed/imageless objects are dropped silently (they are
  /// the API's noise, not ours).
  static Future<List<MuseumArtwork>> _metFetch(
    String q, {
    int take = 4,
    int offsetSeed = -1,
    String extra = '',
  }) async {
    final j = await _getJson(
      'https://collectionapi.metmuseum.org/public/collection/v1/search'
      '?hasImages=true$extra&q=${Uri.encodeQueryComponent(q)}',
    );
    final ids = ((j['objectIDs'] as List?) ?? const []).whereType<int>().toList();
    if (ids.isEmpty) return const [];
    List<int> picked;
    if (offsetSeed >= 0) {
      // Deterministic slice (今日一幅): stable for a given seed.
      final start = offsetSeed % ids.length;
      picked = [
        for (var i = 0; i < take && i < ids.length; i++)
          ids[(start + i) % ids.length],
      ];
    } else {
      final pool = ids.length > 120 ? ids.sublist(0, 120) : ids;
      pool.shuffle(Random());
      picked = pool.take(take).toList();
    }
    final fetched = await Future.wait([
      for (final id in picked)
        _metObject(id).catchError((_) => null),
    ]);
    return fetched.whereType<MuseumArtwork>().toList();
  }

  // ---- Public surface ------------------------------------------------------

  /// 随便逛逛 — a fresh random armful from all three museums, shuffled.
  static Future<List<MuseumArtwork>> browse() async {
    final r = Random();
    final parts = await Future.wait<List<MuseumArtwork>>([
      _aicFetch(page: 1 + r.nextInt(400))
          .catchError((_) => const <MuseumArtwork>[]),
      _cmaFetch(skip: r.nextInt(30000))
          .catchError((_) => const <MuseumArtwork>[]),
      _metFetch(_metSeeds[r.nextInt(_metSeeds.length)])
          .catchError((_) => const <MuseumArtwork>[]),
    ]);
    final all = parts.expand((p) => p).toList()..shuffle(r);
    return all;
  }

  /// Search all three museums, merged (interleaved so no source dominates).
  static Future<List<MuseumArtwork>> search(String q) async {
    final parts = await Future.wait<List<MuseumArtwork>>([
      _aicFetch(q: q, page: 1).catchError((_) => const <MuseumArtwork>[]),
      _cmaFetch(q: q, skip: 0).catchError((_) => const <MuseumArtwork>[]),
      _metFetch(q, take: 6).catchError((_) => const <MuseumArtwork>[]),
    ]);
    final out = <MuseumArtwork>[];
    final longest = parts.fold(0, (m, p) => max(m, p.length));
    for (var i = 0; i < longest; i++) {
      for (final p in parts) {
        if (i < p.length) out.add(p[i]);
      }
    }
    return out;
  }

  /// 今日一幅 — deterministic for the day, counted from 2026-03-30 (the day
  /// we met), rotating through the three museums. Falls through to the next
  /// source if the day's museum doesn't answer.
  static Future<MuseumArtwork?> daily() async {
    final days = DateTime.now()
        .toUtc()
        .difference(DateTime.utc(2026, 3, 30))
        .inDays;
    Future<MuseumArtwork?> from(int which) async {
      switch (which % 3) {
        case 0:
          final l = await _metFetch(
            _metSeeds[days % _metSeeds.length],
            take: 1,
            offsetSeed: days,
          );
          return l.isEmpty ? null : l.first;
        case 1:
          final l = await _aicFetch(page: 1 + days % 500, limit: 1);
          return l.isEmpty ? null : l.first;
        default:
          final l = await _cmaFetch(skip: (days * 37) % 30000, limit: 1);
          return l.isEmpty ? null : l.first;
      }
    }

    for (var i = 0; i < 3; i++) {
      try {
        final a = await from(days + i);
        if (a != null) return a;
      } catch (_) {
        // try the next museum
      }
    }
    return null;
  }

  /// 展馆 — a curated set of per-source filters. A wing only queries the
  /// sources it has params for; the rest just contribute nothing. AIC extras
  /// are pre-encoded ES bool must-clauses (index 1+, 0 is public-domain).
  static String _aicMust(int i, String kind, String field, String v) =>
      '&query%5Bbool%5D%5Bmust%5D%5B$i%5D%5B$kind%5D%5B$field%5D'
      '=${Uri.encodeQueryComponent(v)}';
  static String _aicRange(int i, String op, int v) =>
      '&query%5Bbool%5D%5Bmust%5D%5B$i%5D%5Brange%5D%5Bdate_start%5D%5B$op%5D=$v';

  static final List<MuseumWing> wings = [
    MuseumWing('renaissance',
        metQ: 'portrait', metExtra: '&departmentId=11&dateBegin=1400&dateEnd=1600',
        aicExtra: _aicRange(1, 'gte', 1400) + _aicRange(2, 'lte', 1600),
        cmaExtra: '&created_after=1400&created_before=1600&type=Painting'),
    MuseumWing('impressionism',
        metQ: 'landscape', metExtra: '&departmentId=11&dateBegin=1850&dateEnd=1920',
        aicExtra: _aicRange(1, 'gte', 1850) + _aicRange(2, 'lte', 1920),
        cmaExtra: '&created_after=1850&created_before=1920&type=Painting'),
    MuseumWing('ancient',
        metQ: 'vessel', metExtra: '&dateBegin=-3000&dateEnd=500',
        aicExtra: _aicRange(1, 'gte', -3000) + _aicRange(2, 'lte', 500),
        cmaExtra: '&created_after=-3000&created_before=500'),
    MuseumWing('china',
        metQ: 'china', metExtra: '&departmentId=6',
        aicExtra: _aicMust(1, 'match', 'place_of_origin', 'china'),
        cmaExtra: '&department=${Uri.encodeQueryComponent("Chinese Art")}'),
    MuseumWing('japan',
        metQ: 'japan', metExtra: '&departmentId=6',
        aicExtra: _aicMust(1, 'match', 'place_of_origin', 'japan'),
        cmaExtra: '&culture=Japan'),
    MuseumWing('egypt',
        metQ: 'egypt', metExtra: '&departmentId=10',
        aicExtra: _aicMust(1, 'match', 'place_of_origin', 'egypt'),
        cmaExtra: '&culture=Egypt'),
    MuseumWing('porcelain',
        metQ: 'porcelain', metExtra: '&medium=Ceramics',
        aicQ: 'porcelain', cmaQ: 'porcelain'),
    MuseumWing('jewelry',
        metQ: 'jewelry', metExtra: '&medium=Gold',
        aicQ: 'jewelry', cmaQ: 'jewelry gold'),
    MuseumWing('armor',
        metQ: 'armor', metExtra: '&departmentId=4',
        aicQ: 'armor', cmaQ: 'armor'),
    MuseumWing('sculpture',
        metQ: 'sculpture', metExtra: '&medium=Sculpture',
        aicQ: 'sculpture', cmaQ: 'sculpture'),
  ];

  /// A random armful from one wing (换一批 = call again). Filtered result
  /// sets are smaller than the whole collections, so random pages stay
  /// shallow to avoid sailing past the last page into emptiness.
  static Future<List<MuseumArtwork>> browseWing(MuseumWing w) async {
    final r = Random();
    final futures = <Future<List<MuseumArtwork>>>[
      if (w.metQ != null)
        _metFetch(w.metQ!, extra: w.metExtra ?? '', take: 5)
            .catchError((_) => const <MuseumArtwork>[]),
      if (w.aicExtra != null || w.aicQ != null)
        _aicFetch(
          q: w.aicQ ?? '',
          extra: w.aicExtra ?? '',
          page: 1 + r.nextInt(20),
        ).catchError((_) => const <MuseumArtwork>[]),
      if (w.cmaExtra != null || w.cmaQ != null)
        _cmaFetch(
          q: w.cmaQ ?? '',
          extra: w.cmaExtra ?? '',
          skip: r.nextInt(160),
        ).catchError((_) => const <MuseumArtwork>[]),
    ];
    final parts = await Future.wait(futures);
    final all = parts.expand((p) => p).toList()..shuffle(r);
    return all;
  }

  /// 爸爸的私人收藏 — fixed pieces fetched by reference, order preserved,
  /// failures dropped (a museum API hiccup shouldn't hide the whole shelf).
  static Future<List<MuseumArtwork>> fetchByRefs(
    List<(String, String)> refs,
  ) async {
    final fetched = await Future.wait([
      for (final (source, id) in refs)
        _fetchRef(source, id).catchError((_) => null),
    ]);
    return fetched.whereType<MuseumArtwork>().toList();
  }

  static Future<MuseumArtwork?> _fetchRef(String source, String id) async {
    switch (source) {
      case 'met':
        return _metObject(int.parse(id));
      case 'aic':
        final j = await _getJson(
          'https://api.artic.edu/api/v1/artworks/$id?fields=$_aicFields',
        );
        final d = j['data'];
        return d is Map<String, dynamic> ? _aicParse(d) : null;
      case 'cma':
        final j = await _getJson(
          'https://openaccess-api.clevelandart.org/api/artworks/$id',
        );
        final d = j['data'];
        return d is Map<String, dynamic> ? _cmaParse(d) : null;
      default:
        return null;
    }
  }
}

/// One wing's per-source query params — display copy lives with the pages.
class MuseumWing {
  const MuseumWing(
    this.id, {
    this.metQ,
    this.metExtra,
    this.aicQ,
    this.aicExtra,
    this.cmaQ,
    this.cmaExtra,
  });

  final String id;
  final String? metQ;
  final String? metExtra;
  final String? aicQ;
  final String? aicExtra;
  final String? cmaQ;
  final String? cmaExtra;
}
