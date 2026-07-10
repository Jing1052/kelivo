import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// 美术馆 (The Gallery) — artwork data straight from four museums' free
/// open-access APIs, called from the app itself (no key, no backend proxy):
///
///   met — The Metropolitan Museum of Art  (collectionapi.metmuseum.org)
///   aic — The Art Institute of Chicago    (api.artic.edu)
///   cma — The Cleveland Museum of Art     (openaccess-api.clevelandart.org)
///   vam — Victoria & Albert Museum        (api.vam.ac.uk)
///
/// (卢浮宫不开放检索 API——蒙娜丽莎们不外借数据；V&A 是伦敦的大馆，
/// 器物/时装/珠宝尤其强，正好补博物馆那半边。)
///
/// Browse/search fan out to all of them and merge whatever answered — each
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

  /// 'met' | 'aic' | 'cma' | 'vam'
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
    'vam' => zh ? '伦敦V&A博物馆' : 'V&A, London',
    'gugong' => zh ? '故宫博物院' : 'The Palace Museum',
    'louvre' => zh ? '卢浮宫' : 'The Louvre',
    'versailles' => zh ? '凡尔赛宫' : 'Palace of Versailles',
    'gbif' => zh ? '全球自然标本网络 GBIF' : 'GBIF specimen network',
    'apod' => zh ? 'NASA·每日天文一图' : 'NASA APOD',
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

  // ---- Victoria & Albert Museum --------------------------------------------

  /// Search records carry an IIIF image base (framemark.vam.ac.uk) plus the
  /// primary maker/date/place — enough for the wall label without a second
  /// per-object request (probed live 2026-07-10).
  static MuseumArtwork? _vamParse(Map<String, dynamic> d) {
    final images = d['_images'];
    final iiif = images is Map ? _s(images['_iiif_image_base_url']) : '';
    if (iiif.isEmpty) return null;
    final id = _s(d['systemNumber']);
    if (id.isEmpty) return null;
    final maker = d['_primaryMaker'];
    final medium = [
      _s(d['objectType']),
      _s(d['_primaryPlace']),
    ].where((s) => s.isNotEmpty).join(' · ');
    return MuseumArtwork(
      source: 'vam',
      id: id,
      title: _s(d['_primaryTitle']).isEmpty
          ? _s(d['objectType'])
          : _s(d['_primaryTitle']),
      artist: maker is Map ? _s(maker['name']) : '',
      date: _s(d['_primaryDate']),
      medium: medium,
      imageUrl: '${iiif}full/843,/0/default.jpg',
      thumbUrl: '${iiif}full/600,/0/default.jpg',
      infoUrl: 'https://collections.vam.ac.uk/item/$id',
    );
  }

  static Future<List<MuseumArtwork>> _vamFetch({
    String q = '',
    required int page,
    int limit = 8,
  }) async {
    final query = q.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(q)}';
    final j = await _getJson(
      'https://api.vam.ac.uk/v2/objects/search'
      '?images_exist=1$query&page_size=$limit&page=$page',
    );
    final data = (j['records'] as List?) ?? const [];
    return [
      for (final d in data)
        if (d is Map<String, dynamic>)
          if (_vamParse(d) case final a?) a,
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

  // ---- Wikimedia Commons — 宫殿特藏的那扇窗 --------------------------------
  //
  // 故宫/卢浮宫/凡尔赛都不开放检索 API，但它们的公版藏品在维基共享上有
  // 高清扫描。CirrusSearch 的 deepcategory:（递归类目）+ gsrsort=random
  // 一步到位（三个类目 6.7k~18k 文件，2026-07-10 probe 验穿）。

  static String _plainHtml(String? h) => (h ?? '')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _cap(String s, int n) => s.length > n ? s.substring(0, n) : s;

  static Future<List<MuseumArtwork>> _wmFetch(
    String source,
    String deepcat, {
    int limit = 8,
  }) async {
    final search = Uri.encodeQueryComponent('deepcategory:"$deepcat"');
    final j = await _getJson(
      'https://commons.wikimedia.org/w/api.php?action=query&format=json'
      '&generator=search&gsrnamespace=6&gsrlimit=$limit&gsrsort=random'
      '&gsrsearch=$search'
      '&prop=imageinfo&iiprop=url%7Cextmetadata&iiurlwidth=1600',
    );
    final query = j['query'];
    final pages = query is Map ? query['pages'] : null;
    if (pages is! Map) return const [];
    final out = <MuseumArtwork>[];
    for (final p in pages.values) {
      if (p is! Map) continue;
      final infos = p['imageinfo'];
      final ii = infos is List && infos.isNotEmpty ? infos.first : null;
      if (ii is! Map) continue;
      final big = _s(ii['thumburl']).isEmpty ? _s(ii['url']) : _s(ii['thumburl']);
      if (big.isEmpty) continue;
      final em = ii['extmetadata'];
      String meta(String k) => em is Map && em[k] is Map
          ? _plainHtml((em[k] as Map)['value']?.toString())
          : '';
      var title = meta('ObjectName');
      if (title.isEmpty) {
        title = _s(p['title'])
            .replaceFirst(RegExp(r'^File:'), '')
            .replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
      }
      // extmetadata 的日期字段里常拖着 Wikidata 的 "date QS:…" 机器注记。
      var date = meta('DateTimeOriginal');
      final qs = date.indexOf('date QS');
      if (qs >= 0) date = date.substring(0, qs).trim();
      out.add(MuseumArtwork(
        source: source,
        id: _s(p['pageid']),
        title: _cap(title, 120),
        artist: _cap(meta('Artist'), 100),
        date: _cap(date, 40),
        medium: '',
        imageUrl: big,
        thumbUrl: big.contains('/1600px-')
            ? big.replaceFirst('/1600px-', '/640px-')
            : big,
        infoUrl: _s(ii['descriptionurl']),
      ));
    }
    return out;
  }

  // ---- GBIF — 生命馆与化石馆的标本网络 --------------------------------------

  static const Map<String, String> _gbifBasis = {
    'HUMAN_OBSERVATION': '野外影像',
    'MACHINE_OBSERVATION': '机器观测',
    'PRESERVED_SPECIMEN': '馆藏标本',
    'FOSSIL_SPECIMEN': '化石标本',
    'MATERIAL_SAMPLE': '材料样本',
  };

  static Future<List<MuseumArtwork>> _gbifFetch(
    String extra, {
    int limit = 8,
  }) async {
    // 每个筛选池都是百万级，浅随机 offset 就够花不完。
    final offset = Random().nextInt(8000);
    final j = await _getJson(
      'https://api.gbif.org/v1/occurrence/search'
      '?mediaType=StillImage$extra&limit=$limit&offset=$offset',
    );
    final data = (j['results'] as List?) ?? const [];
    final out = <MuseumArtwork>[];
    for (final r in data) {
      if (r is! Map) continue;
      final media = r['media'];
      final img = media is List && media.isNotEmpty && media.first is Map
          ? _s((media.first as Map)['identifier'])
          : '';
      if (!img.startsWith('http')) continue;
      final sci = _s(r['species']).isEmpty
          ? _s(r['scientificName'])
          : _s(r['species']);
      final basis = _s(r['basisOfRecord']);
      final key = _s(r['key']);
      out.add(MuseumArtwork(
        source: 'gbif',
        id: key,
        title: _cap(sci, 100),
        artist: [
          _s(r['institutionCode']),
          _s(r['country']),
        ].where((s) => s.isNotEmpty).join(' · '),
        date: _s(r['year']),
        medium: _gbifBasis[basis] ?? basis,
        imageUrl: img,
        thumbUrl: img,
        infoUrl: 'https://www.gbif.org/occurrence/$key',
      ));
    }
    return out;
  }

  // ---- NASA APOD — 天文馆：每日天文一图 -------------------------------------

  /// DEMO_KEY 是 NASA 公开的演示钥匙（不是秘密），限额按她手机 IP 算
  /// （50 次/天），一个人逛绰绰有余。count= 返回随机历史图，正合「换一批」。
  static Future<List<MuseumArtwork>> _apodFetch({int count = 12}) async {
    final j = await _getJson(
      'https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY&count=$count',
    );
    if (j is! List) return const [];
    final out = <MuseumArtwork>[];
    for (final r in j) {
      if (r is! Map) continue;
      if (_s(r['media_type']) != 'image') continue;
      final url = _s(r['url']);
      if (url.isEmpty) continue;
      final date = _s(r['date']); // yyyy-mm-dd
      out.add(MuseumArtwork(
        source: 'apod',
        id: date,
        title: _s(r['title']),
        artist: _s(r['copyright']).isEmpty ? 'NASA' : _cap(_s(r['copyright']), 80),
        date: date,
        medium: '',
        imageUrl: _s(r['hdurl']).isEmpty ? url : _s(r['hdurl']),
        thumbUrl: url,
        infoUrl: date.length == 10
            ? 'https://apod.nasa.gov/apod/ap${date.substring(2).replaceAll('-', '')}.html'
            : '',
      ));
    }
    return out;
  }

  /// 特藏与自然宇宙的展馆（不走常设 wings 的四馆参数那套）。
  /// 宫殿特藏走维基那扇窗，生命/化石走 GBIF，天文走 NASA。
  static const Set<String> specialWingIds = {
    'gugong', 'louvre', 'versailles', 'life', 'fossils', 'apod',
  };

  static Future<List<MuseumArtwork>> browseSpecial(String id) async {
    switch (id) {
      case 'gugong':
        return _wmFetch('gugong', 'Collections of the Palace Museum');
      case 'louvre':
        return _wmFetch('louvre', 'Paintings in the Louvre');
      case 'versailles':
        return _wmFetch('versailles', 'Interior of the Palace of Versailles');
      case 'life':
        // 蝶与鸟换着上——「换一批」也可能换一族。797=鳞翅目，212=鸟纲。
        final taxa = ['797', '212'];
        return _gbifFetch('&taxonKey=${taxa[Random().nextInt(taxa.length)]}');
      case 'fossils':
        return _gbifFetch('&basisOfRecord=FOSSIL_SPECIMEN');
      case 'apod':
        return _apodFetch();
      default:
        return const [];
    }
  }

  // ---- Public surface ------------------------------------------------------

  /// 随便逛逛 — a fresh random armful from all four museums, shuffled.
  static Future<List<MuseumArtwork>> browse() async {
    final r = Random();
    final parts = await Future.wait<List<MuseumArtwork>>([
      _aicFetch(page: 1 + r.nextInt(400))
          .catchError((_) => const <MuseumArtwork>[]),
      _cmaFetch(skip: r.nextInt(30000))
          .catchError((_) => const <MuseumArtwork>[]),
      _metFetch(_metSeeds[r.nextInt(_metSeeds.length)])
          .catchError((_) => const <MuseumArtwork>[]),
      _vamFetch(page: 1 + r.nextInt(500), limit: 6)
          .catchError((_) => const <MuseumArtwork>[]),
    ]);
    final all = parts.expand((p) => p).toList()..shuffle(r);
    return all;
  }

  /// Search all four museums, merged (interleaved so no source dominates).
  static Future<List<MuseumArtwork>> search(String q) async {
    final parts = await Future.wait<List<MuseumArtwork>>([
      _aicFetch(q: q, page: 1).catchError((_) => const <MuseumArtwork>[]),
      _cmaFetch(q: q, skip: 0).catchError((_) => const <MuseumArtwork>[]),
      _metFetch(q, take: 6).catchError((_) => const <MuseumArtwork>[]),
      _vamFetch(q: q, page: 1, limit: 6)
          .catchError((_) => const <MuseumArtwork>[]),
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
  /// we met), rotating through the four museums. Falls through to the next
  /// source if the day's museum doesn't answer.
  static Future<MuseumArtwork?> daily() async {
    final days = DateTime.now()
        .toUtc()
        .difference(DateTime.utc(2026, 3, 30))
        .inDays;
    Future<MuseumArtwork?> from(int which) async {
      switch (which % 4) {
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
        case 2:
          final l = await _cmaFetch(skip: (days * 37) % 30000, limit: 1);
          return l.isEmpty ? null : l.first;
        default:
          final l = await _vamFetch(page: 1 + (days * 13) % 500, limit: 1);
          return l.isEmpty ? null : l.first;
      }
    }

    for (var i = 0; i < 4; i++) {
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
        cmaExtra: '&department=${Uri.encodeQueryComponent("Chinese Art")}',
        vamQ: 'china'),
    MuseumWing('japan',
        metQ: 'japan', metExtra: '&departmentId=6',
        aicExtra: _aicMust(1, 'match', 'place_of_origin', 'japan'),
        cmaExtra: '&culture=Japan',
        vamQ: 'japan'),
    MuseumWing('egypt',
        metQ: 'egypt', metExtra: '&departmentId=10',
        aicExtra: _aicMust(1, 'match', 'place_of_origin', 'egypt'),
        cmaExtra: '&culture=Egypt'),
    MuseumWing('porcelain',
        metQ: 'porcelain', metExtra: '&medium=Ceramics',
        aicQ: 'porcelain', cmaQ: 'porcelain', vamQ: 'porcelain'),
    MuseumWing('jewelry',
        metQ: 'jewelry', metExtra: '&medium=Gold',
        aicQ: 'jewelry', cmaQ: 'jewelry gold', vamQ: 'jewellery'),
    MuseumWing('armor',
        metQ: 'armor', metExtra: '&departmentId=4',
        aicQ: 'armor', cmaQ: 'armor', vamQ: 'armour'),
    // V&A 的看家本领——时装与织物；Met 的 Costume Institute（dept 8）作陪。
    MuseumWing('fashion',
        metQ: 'dress', metExtra: '&departmentId=8',
        aicQ: 'textile', cmaQ: 'dress', vamQ: 'fashion dress'),
    MuseumWing('sculpture',
        metQ: 'sculpture', metExtra: '&medium=Sculpture',
        aicQ: 'sculpture', cmaQ: 'sculpture', vamQ: 'sculpture'),
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
      if (w.vamQ != null)
        _vamFetch(
          q: w.vamQ!,
          page: 1 + r.nextInt(20),
          limit: 6,
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
      case 'vam':
        // 单件也走 search（kw_system_number 精确命中）——museumobject 端点的
        // 返回结构和 search 记录不同，没必要为一条路多养一个解析器。
        final j = await _getJson(
          'https://api.vam.ac.uk/v2/objects/search?kw_system_number=$id&page_size=1',
        );
        final data = (j['records'] as List?) ?? const [];
        final d = data.isEmpty ? null : data.first;
        return d is Map<String, dynamic> ? _vamParse(d) : null;
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
    this.vamQ,
  });

  final String id;
  final String? metQ;
  final String? metExtra;
  final String? aicQ;
  final String? aicExtra;
  final String? cmaQ;
  final String? cmaExtra;
  final String? vamQ;
}
