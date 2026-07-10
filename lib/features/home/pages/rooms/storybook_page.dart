import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import '../../widgets/still_glass.dart';
import 'museum_widgets.dart' show museumNetImage;

/// 故事本 (Storybooks) — daddy 亲笔写的图画书：各个国家、各个时期的
/// 故事与风俗，插图全部是三座博物馆的真馆藏。内容住在老家
/// `/api/home/storybooks`（storybooks.json）——上新故事不用更新 App。
/// 书架缓存优先（秒开），右上角刷新拉新书。
class StorybookPage extends StatefulWidget {
  const StorybookPage({super.key});

  @override
  State<StorybookPage> createState() => _StorybookPageState();
}

class _StoryPage {
  const _StoryPage({required this.text, required this.img, required this.credit});
  final String text;
  final String img;
  final String credit;
}

class _StoryBook {
  const _StoryBook({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.region,
    required this.subtitle,
    required this.cover,
    required this.pages,
  });

  final String id;
  final String title;
  final String titleEn;
  final String region;
  final String subtitle;
  final String cover;
  final List<_StoryPage> pages;

  static _StoryBook? fromJson(dynamic j) {
    if (j is! Map) return null;
    String s(String k) => (j[k] ?? '').toString();
    final pages = <_StoryPage>[
      for (final p in (j['pages'] as List? ?? const []))
        if (p is Map)
          _StoryPage(
            text: (p['text'] ?? '').toString(),
            img: (p['img'] ?? '').toString(),
            credit: (p['credit'] ?? '').toString(),
          ),
    ];
    if (s('id').isEmpty || pages.isEmpty) return null;
    return _StoryBook(
      id: s('id'),
      title: s('title'),
      titleEn: s('title_en'),
      region: s('region'),
      subtitle: s('subtitle'),
      cover: s('cover'),
      pages: pages,
    );
  }
}

class _StorybookPageState extends State<StorybookPage> {
  static const String _cachePref = 'storybooks_cache_v1';

  List<_StoryBook> _books = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<_StoryBook> _parse(Map<String, dynamic> j) => [
        for (final b in (j['books'] as List? ?? const []))
          if (_StoryBook.fromJson(b) case final bk?) bk,
      ];

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final prefs = await SharedPreferences.getInstance();
    if (!refresh) {
      final raw = prefs.getString(_cachePref);
      if (raw != null) {
        try {
          final cached = _parse(jsonDecode(raw) as Map<String, dynamic>);
          if (cached.isNotEmpty && mounted) {
            setState(() {
              _books = cached;
              _loading = false;
            });
            return;
          }
        } catch (_) {
          // 缓存坏了就当没有，往下走真取
        }
      }
    }
    if (!mounted) return;
    final gw = OurHomeGateway.fromContext(context);
    if (gw == null) {
      setState(() {
        _loading = false;
        _error = 'unconnected';
      });
      return;
    }
    try {
      final j = await gw.fetchStorybooks();
      final books = _parse(j);
      if (books.isNotEmpty) {
        await prefs.setString(_cachePref, jsonEncode(j));
      }
      if (!mounted) return;
      setState(() {
        _books = books;
        _loading = false;
        _error = books.isEmpty ? 'empty' : '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _books.isEmpty ? 'network' : '';
      });
    }
  }

  void _open(_StoryBook b) {
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _StoryReaderPage(book: b)),
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
              zh ? '故事本' : 'Storybooks',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            actions: [
              IosIconButton(
                icon: Lucide.RefreshCw,
                size: 20,
                minSize: 44,
                onTap: () {
                  Haptics.soft();
                  _load(refresh: true);
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                : _error.isNotEmpty
                    ? _errorState(cs, zh)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
                            child: Text(
                              zh
                                  ? '我写的，讲给你听。插图全是博物馆里的真东西。'
                                  : 'Written by me, told to you — every picture is the real thing.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: cs.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                          for (final b in _books) ...[
                            _bookCard(cs, zh, b),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
          ),
        ),
      ],
    );
  }

  Widget _bookCard(ColorScheme cs, bool zh, _StoryBook b) {
    return StillGlass(
      radius: 18,
      blur: false,
      padding: EdgeInsets.zero,
      onTap: () => _open(b),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 150,
              width: double.infinity,
              child: museumNetImage(cs, b.cover, BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    zh ? b.title : (b.titleEn.isEmpty ? b.title : b.titleEn),
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    b.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Lucide.MapPin,
                        size: 12,
                        color: cs.primary.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          b.region,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.primary.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      Text(
                        zh ? '${b.pages.length} 页' : '${b.pages.length} pages',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(ColorScheme cs, bool zh) {
    final msg = switch (_error) {
      'unconnected' => zh
          ? '家里的连接还没配好——先在爸爸设置里连一下。'
          : 'Home is not connected yet.',
      'empty' => zh ? '书架上还空着——我这就去写。' : 'The shelf is empty — for now.',
      _ => zh ? '书架没取到——检查网络，点右上角再试。' : "Couldn't reach the shelf — retry.",
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Lucide.BookOpenText,
              size: 30,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 10),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 图画书阅读器：横向翻页，上图下文，页脚馆藏署名＋页码。
class _StoryReaderPage extends StatefulWidget {
  const _StoryReaderPage({required this.book});

  final _StoryBook book;

  @override
  State<_StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends State<_StoryReaderPage> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final b = widget.book;

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
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  zh ? b.title : (b.titleEn.isEmpty ? b.title : b.titleEn),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_page + 1} / ${b.pages.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: PageView.builder(
              itemCount: b.pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final p = b.pages[i];
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p.img.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: SizedBox(
                              width: double.infinity,
                              child: museumNetImage(cs, p.img, BoxFit.contain),
                            ),
                          ),
                        ),
                      if (p.credit.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          p.credit,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        p.text,
                        style: TextStyle(
                          fontSize: 15.5,
                          height: 1.85,
                          color: cs.onSurface.withValues(alpha: 0.92),
                        ),
                      ),
                      if (i == b.pages.length - 1) ...[
                        const SizedBox(height: 24),
                        Center(
                          child: Text(
                            zh ? '—— 完 ——' : '— the end —',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 2,
                              color: cs.onSurface.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
