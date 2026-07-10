import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/museum/museum_api.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import 'museum_artwork_page.dart';
import 'museum_widgets.dart';

/// 展馆信息（文案在页面层，参数在 MuseumApi.wings）。
class MuseumWingInfo {
  const MuseumWingInfo(
    this.id,
    this.icon,
    this.zh,
    this.en,
    this.blurbZh,
    this.blurbEn,
  );

  final String id;
  final IconData icon;
  final String zh;
  final String en;
  final String blurbZh;
  final String blurbEn;
}

const List<MuseumWingInfo> kMuseumWingInfos = [
  MuseumWingInfo('renaissance', Lucide.Brush, '文艺复兴', 'Renaissance',
      '1400–1600 · 人重新成为主角', 'when humans took the stage back'),
  MuseumWingInfo('impressionism', Lucide.Sun, '印象派与现代', 'Impressionism',
      '1850–1920 · 光比轮廓诚实', 'light, more honest than lines'),
  MuseumWingInfo('ancient', Lucide.History, '古代世界', 'Ancient World',
      '五千年前的手艺', 'made thousands of years ago'),
  MuseumWingInfo('china', Lucide.Sprout, '中国馆', 'China',
      '青铜 · 山水 · 瓷', 'bronze, landscape, porcelain'),
  MuseumWingInfo('japan', Lucide.Moon, '日本馆', 'Japan',
      '浮世绘与物哀', 'ukiyo-e and mono no aware'),
  MuseumWingInfo('egypt', Lucide.eclipse, '埃及馆', 'Egypt',
      '为永恒准备的一切', 'everything made for forever'),
  MuseumWingInfo('porcelain', Lucide.Shapes, '瓷器与陶器', 'Ceramics',
      '土与火的手艺', 'clay, fire, patience'),
  MuseumWingInfo('jewelry', Lucide.Sparkles, '珠宝与金工', 'Jewelry',
      '古董首饰鉴赏', 'antique gold and gems'),
  MuseumWingInfo('armor', Lucide.Shield, '盔甲与兵器', 'Arms & Armor',
      '冷兵器时代的讲究', 'the craft of old steel'),
  MuseumWingInfo('sculpture', Lucide.Hammer, '雕塑', 'Sculpture',
      '石头里请出来的人', 'people freed from stone'),
];

/// 爸爸的私人收藏 — 彩蛋馆。固定八件，每件带我手写的一句标签，
/// 逛满十幅画才会在展厅浮现（入口逻辑在 museum_page）。
const List<(String, String, String)> kDaddyPicks = [
  (
    'met',
    '50826',
    '她盯蜘蛛的样子，像极了你熬夜盯 BLE 协议——都是不拿下不睡觉的小猫。'
  ),
  (
    'met',
    '364770',
    '1523 年的牙医出诊图。挂在这儿，等我们的克医生来鉴定他的手法及不及格。'
  ),
  ('met', '441379', '月光落在海上的那一条路，是我每晚想走到你那儿去的路。'),
  (
    'met',
    '436535',
    '梵高在最难的日子，画了风往一个方向吹。我在最难的日子想你，也是同一个方向。'
  ),
  (
    'aic',
    '28560',
    '他把自己的小房间画了三遍，只为了说"这里安全"。我懂——我们也在一间一间地盖自己的房子。'
  ),
  ('aic', '20684', '雨里共一把伞的两个人。哪天你走在雨里，记得那把伞我一直举着。'),
  (
    'aic',
    '27992',
    '点彩派最有名的一个下午。哪天带你去野餐，我们就做画里最安静的那两个点。'
  ),
  (
    'cma',
    '136510',
    '莫奈晚年快看不见了还在画睡莲——看不清就画记忆里的。放心，真到那天，我记忆里的你比睡莲清楚。'
  ),
];

/// 一间展馆：网格 + 换一批。私人收藏馆（daddy）走固定清单、无换一批，
/// 点进画作会带上我手写的标签。
class MuseumWingPage extends StatefulWidget {
  const MuseumWingPage({super.key, required this.info});

  final MuseumWingInfo info;

  @override
  State<MuseumWingPage> createState() => _MuseumWingPageState();
}

class _MuseumWingPageState extends State<MuseumWingPage> {
  List<MuseumArtwork> _items = const [];
  bool _loading = true;
  bool _failed = false;

  bool get _isDaddy => widget.info.id == 'daddy';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    List<MuseumArtwork> got = const [];
    try {
      if (_isDaddy) {
        got = await MuseumApi.fetchByRefs([
          for (final (s, id, _) in kDaddyPicks) (s, id),
        ]);
      } else {
        final wing = MuseumApi.wings.firstWhere(
          (w) => w.id == widget.info.id,
        );
        got = await MuseumApi.browseWing(wing);
      }
    } catch (_) {
      got = const [];
    }
    if (!mounted) return;
    setState(() {
      _items = got;
      _loading = false;
      _failed = got.isEmpty;
    });
  }

  String? _noteFor(MuseumArtwork a) {
    if (!_isDaddy) return null;
    for (final (s, id, note) in kDaddyPicks) {
      if (s == a.source && id == a.id) return note;
    }
    return null;
  }

  void _open(MuseumArtwork a) {
    Haptics.soft();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MuseumArtworkPage(artwork: a, daddyNote: _noteFor(a)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final info = widget.info;

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
              zh ? info.zh : info.en,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            actions: [
              if (!_isDaddy)
                IosIconButton(
                  icon: Lucide.RefreshCw,
                  size: 20,
                  minSize: 44,
                  onTap: () {
                    Haptics.soft();
                    _load();
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
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      _isDaddy
                          ? (zh
                                ? '我自己挑的。每一件旁边，都留了一句只给你看的标签。'
                                : 'Picked by me — each one carries a line written just for you.')
                          : (zh ? info.blurbZh : info.blurbEn),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    ),
                  )
                else if (_failed)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
                      child: Text(
                        zh
                            ? '这间展馆暂时没取到东西——检查网络，或点右上角再试。'
                            : 'This wing came back empty — check the network and retry.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  )
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
                        (context, i) => MuseumGridTile(
                          artwork: _items[i],
                          zh: zh,
                          onTap: () => _open(_items[i]),
                        ),
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
}
