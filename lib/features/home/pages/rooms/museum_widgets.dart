import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/services/museum/museum_api.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../widgets/still_glass.dart';

/// 逛馆计数的存储键：画作页每次开门 +1，展厅页读它决定彩蛋馆浮不浮现。
const String museumOpenedCountPref = 'museum_opened_count_v1';

/// 画作清单的本地留档（今日一幅/随便逛逛/各展馆共用）：进门先上缓存秒开，
/// 「换一批」才真出门取新的。一条 key 一份清单，JSON 存 prefs。
Future<void> museumCacheSave(String key, List<MuseumArtwork> items) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'museum_cache_v1:$key',
    jsonEncode([for (final a in items) a.toJson()]),
  );
}

Future<List<MuseumArtwork>> museumCacheLoad(String key) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('museum_cache_v1:$key');
  if (raw == null) return const [];
  try {
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list)
        if (MuseumArtwork.fromJson(e) case final a?) a,
    ];
  } catch (_) {
    return const [];
  }
}

/// Shared bits of the museum pages (展厅 grid + 展馆 grids) so the two don't
/// grow near-duplicate tiles (§3.9). Images go through a disk cache
/// (cached_network_image) — loaded once, kept on her phone.
Widget museumNetImage(ColorScheme cs, String url, BoxFit fit) {
  return CachedNetworkImage(
    imageUrl: url,
    fit: fit,
    placeholder: (c, u) => ColoredBox(
      color: cs.onSurface.withValues(alpha: 0.05),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
    errorWidget: (c, u, e) => ColoredBox(
      color: cs.onSurface.withValues(alpha: 0.05),
      child: Center(
        child: Icon(
          Lucide.ImageOff,
          size: 22,
          color: cs.onSurface.withValues(alpha: 0.3),
        ),
      ),
    ),
  );
}

class MuseumGridTile extends StatelessWidget {
  const MuseumGridTile({
    super.key,
    required this.artwork,
    required this.zh,
    required this.onTap,
  });

  final MuseumArtwork artwork;
  final bool zh;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = artwork;
    return StillGlass(
      radius: 16,
      blur: false,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: museumNetImage(cs, a.thumbUrl, BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 8, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title.isEmpty ? (zh ? '无题' : 'Untitled') : a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    a.artist.isEmpty ? a.museumName(zh) : a.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
