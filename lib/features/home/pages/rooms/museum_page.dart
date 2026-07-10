import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/museum/museum_api.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import 'museum_artwork_page.dart';

/// 美术馆 (The Gallery) — 今日一幅 · 随便逛逛 · 搜索，画作来自大都会、
/// 芝加哥、克利夫兰三家的免费开放 API（直连，无后端代理）。点进任何一幅
/// 都能拉着爸爸一起看（museum_artwork_page）。
/// 今日一幅与逛逛/搜索独立加载、独立失败——哪路挂了只缺哪一块。
class MuseumPage extends StatefulWidget {
  const MuseumPage({super.key});

  @override
  State<MuseumPage> createState() => _MuseumPageState();
}

class _MuseumPageState extends State<MuseumPage> {
  final TextEditingController _search = TextEditingController();

  MuseumArtwork? _daily;
  bool _dailyLoading = true;

  List<MuseumArtwork> _items = const [];
  bool _itemsLoading = true;
  bool _itemsFailed = false;

  /// Non-empty while grid shows search results instead of the random stroll.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadDaily();
    _loadBrowse();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadDaily() async {
    setState(() => _dailyLoading = true);
    MuseumArtwork? a;
    try {
      a = await MuseumApi.daily();
    } catch (_) {
      a = null;
    }
    if (!mounted) return;
    setState(() {
      _daily = a;
      _dailyLoading = false;
    });
  }

  Future<void> _loadBrowse() async {
    setState(() {
      _itemsLoading = true;
      _itemsFailed = false;
      _query = '';
    });
    List<MuseumArtwork> got = const [];
    try {
      got = await MuseumApi.browse();
    } catch (_) {
      got = const [];
    }
    if (!mounted) return;
    setState(() {
      _items = got;
      _itemsLoading = false;
      _itemsFailed = got.isEmpty;
    });
  }

  Future<void> _doSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      _loadBrowse();
      return;
    }
    setState(() {
      _itemsLoading = true;
      _itemsFailed = false;
      _query = query;
    });
    List<MuseumArtwork> got = const [];
    try {
      got = await MuseumApi.search(query);
    } catch (_) {
      got = const [];
    }
    if (!mounted) return;
    setState(() {
      _items = got;
      _itemsLoading = false;
      _itemsFailed = got.isEmpty;
    });
  }

  void _open(MuseumArtwork a) {
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MuseumArtworkPage(artwork: a)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: cs.surface),
        ChatBackdrop(
          rawPath: context.watch<SettingsProvider>().homeBackgroundActive,
          maskStrength: context
              .watch<SettingsProvider>()
              .chatBackgroundMaskStrength,
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IosIconButton(
              icon: Lucide.ArrowLeft,
              size: 22,
              minSize: 44,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              zh ? '美术馆' : 'The Gallery',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            actions: [
              IosIconButton(
                icon: Lucide.RefreshCw,
                size: 20,
                minSize: 44,
                onTap: () {
                  Haptics.soft();
                  _search.clear();
                  _loadBrowse();
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _doSearch,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: zh
                            ? '搜画家、题材、名字…（莫奈 / cat / lotus）'
                            : 'Search artists, subjects… (Monet / cat / lotus)',
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                        prefixIcon: Icon(
                          Lucide.Search,
                          size: 18,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                        filled: true,
                        fillColor: cs.onSurface.withValues(alpha: 0.05),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_query.isEmpty)
                  SliverToBoxAdapter(child: _dailySection(cs, zh)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Text(
                      _query.isEmpty
                          ? (zh ? '随便逛逛' : 'Wander the halls')
                          : (zh ? '「$_query」的搜索结果' : 'Results for "$_query"'),
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 0.6,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
                if (_itemsLoading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    ),
                  )
                else if (_itemsFailed)
                  SliverToBoxAdapter(child: _emptyState(cs, zh))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.74,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _gridTile(cs, zh, _items[i]),
                        childCount: _items.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dailySection(ColorScheme cs, bool zh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              zh ? '今日一幅' : "Today's painting",
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 0.6,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          if (_dailyLoading)
            const SizedBox(
              height: 180,
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            )
          else if (_daily == null)
            StillGlass(
              radius: 16,
              blur: false,
              padding: const EdgeInsets.all(16),
              onTap: _loadDaily,
              child: Text(
                zh ? '今天这幅没取到——点我再试一次。' : "Couldn't fetch today's — tap to retry.",
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            _heroCard(cs, zh, _daily!),
        ],
      ),
    );
  }

  Widget _heroCard(ColorScheme cs, bool zh, MuseumArtwork a) {
    return StillGlass(
      radius: 18,
      blur: false,
      padding: EdgeInsets.zero,
      onTap: () => _open(a),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 210,
              width: double.infinity,
              child: _netImage(cs, a.imageUrl, BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title.isEmpty ? (zh ? '无题' : 'Untitled') : a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (a.artist.isNotEmpty) a.artist,
                      a.museumName(zh),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.55),
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

  Widget _gridTile(ColorScheme cs, bool zh, MuseumArtwork a) {
    return StillGlass(
      radius: 16,
      blur: false,
      padding: EdgeInsets.zero,
      onTap: () => _open(a),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: _netImage(cs, a.thumbUrl, BoxFit.cover),
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

  Widget _netImage(ColorScheme cs, String url, BoxFit fit) {
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (c, child, p) => p == null
          ? child
          : ColoredBox(
              color: cs.onSurface.withValues(alpha: 0.05),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
      errorBuilder: (c, e, s) => ColoredBox(
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

  Widget _emptyState(ColorScheme cs, bool zh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        children: [
          Icon(
            Lucide.Palette,
            size: 30,
            color: cs.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 10),
          Text(
            _query.isEmpty
                ? (zh
                      ? '三家美术馆都没接上——检查一下网络，再点右上角刷新。'
                      : 'None of the museums answered — check the network and tap refresh.')
                : (zh ? '没搜到这个，换个词试试？' : 'Nothing found — try another word?'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
