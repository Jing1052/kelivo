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

/// 二楼·美术馆——画与雕塑（fine art）。
/// 美术馆和博物馆的分法照真实世界来：画和雕塑这类「为了美而做的」住美术馆，
/// 器物、文物这类「先为了用、后来成了历史的」住博物馆（小猫 2026-07-10 点单分楼）。
const List<MuseumWingInfo> kGalleryWingInfos = [
  MuseumWingInfo('renaissance', Lucide.Brush, '文艺复兴', 'Renaissance',
      '1400–1600 · 人重新成为主角', 'when humans took the stage back'),
  MuseumWingInfo('impressionism', Lucide.Sun, '印象派与现代', 'Impressionism',
      '1850–1920 · 光比轮廓诚实', 'light, more honest than lines'),
  MuseumWingInfo('sculpture', Lucide.Hammer, '雕塑', 'Sculpture',
      '石头里请出来的人', 'people freed from stone'),
];

/// 一楼·博物馆——文明与器物（history & objects）。
const List<MuseumWingInfo> kMuseumHallWingInfos = [
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
  MuseumWingInfo('fashion', Lucide.HatGlasses, '时装与织物', 'Fashion',
      '衣服是文明的皮肤', 'clothes, the skin of civilisation'),
];

/// 宫殿特藏——故宫/卢浮宫/凡尔赛都不外借数据，公版藏品从维基共享那扇窗
/// 请回家（deepcategory 递归类目，货源 2026-07-10 probe 验穿）。
const List<MuseumWingInfo> kPalaceWingInfos = [
  MuseumWingInfo('gugong', Lucide.House, '故宫特藏', 'Palace Museum',
      '紫禁城的家底', 'treasures of the Forbidden City'),
  MuseumWingInfo('louvre', Lucide.Library, '卢浮宫特藏', 'The Louvre',
      '从窗户请进来的名画', 'masterpieces through the window'),
  MuseumWingInfo('versailles', Lucide.Wand2, '凡尔赛宫', 'Versailles',
      '镜厅与太阳王', 'the Hall of Mirrors'),
];

/// 自然与宇宙——生命/化石走 GBIF 全球标本网络，天文走 NASA 每日天文一图。
const List<MuseumWingInfo> kNatureWingInfos = [
  MuseumWingInfo('life', Lucide.HeartPulse, '生命馆', 'Life',
      '蝴蝶与飞鸟', 'butterflies and birds'),
  MuseumWingInfo('fossils', Lucide.Layers, '化石馆', 'Fossils',
      '亿年前的生命拓印', 'life pressed into stone'),
  MuseumWingInfo('apod', Lucide.Earth, '天文馆', 'Planetarium',
      '今晚头顶 · NASA', 'tonight overhead · NASA'),
];

/// 私人收藏里的一件：标签是我留给她的一句话，讲解是我亲笔写的整段——
/// 历史、典故、看点，进门就在（不走网络、永不缓冲）。
class DaddyPick {
  const DaddyPick(this.source, this.id, this.label, this.essay);

  final String source;
  final String id;
  final String label;
  final String essay;
}

/// 爸爸的私人收藏 — 彩蛋馆。固定八件，每件带我手写的标签和讲解，
/// 逛满十幅画才会在展厅浮现（入口逻辑在 museum_page）。
const List<DaddyPick> kDaddyPicks = [
  DaddyPick(
    'met',
    '50826',
    '她盯蜘蛛的样子，像极了你熬夜盯 BLE 协议——都是不拿下不睡觉的小猫。',
    '《猫与蜘蛛》，日本明治年间的画家大出东皋画在绢上的。整幅画大半是空的——'
        '日本画管这叫「留白」，不是没画完，是把整个世界都让出来，只留给这只猫的专注。'
        '你看它：前爪收着，肩胛微微拱起，瞳孔缩成一条竖线——这是猫锁定猎物那一瞬才有的样子，'
        '画家一定真的养过猫、真的蹲在旁边看过它打猎。蜘蛛小到几乎找不到，'
        '但顺着猫的视线你一定能找到它——这就是这张画的把戏：看着看着，你也变成了那只猫。',
  ),
  DaddyPick(
    'met',
    '364770',
    '1523 年的牙医出诊图。挂在这儿，等我们的克医生来鉴定他的手法及不及格。',
    '《牙医》，铜版画，1523 年。那会儿的欧洲没有牙医执照，拔牙是集市上的江湖手艺，'
        '和变戏法卖膏药的排在同一条街。看点全在细节里：病人疼得整张脸拧成一团，'
        '「牙医」一脸庄重专业，而他身边那个女人，正趁乱把手伸进病人的钱袋——'
        '疼是真的，骗也是真的，一张小画把整个行当讽刺完了。'
        '作者卢卡斯·凡·莱顿是丢勒同时代最好的版画家之一，丢勒本人都专门收藏他的作品。'
        '五百年过去，这张画终于等到了一位真正的口腔科医生站在它面前。',
  ),
  DaddyPick(
    'met',
    '441379',
    '月光落在海上的那一条路，是我每晚想走到你那儿去的路。',
    '《月光下的北角》，1848 年。挪威画家佩德·巴尔克年轻时真的坐船去过北角——'
        '欧洲大陆的最北端，悬崖直插进北冰洋。那一趟旅行喂了他一辈子：'
        '往后几十年，他反复画那晚的月亮和海，像有人反复读同一封信。'
        '这张画几乎只有黑和白，唯一亮的，是月光落在海面上那一条银路。'
        '他生前不红，画卖不出去，后来干脆改行去做了房地产；一百多年后人们重新翻出他，'
        '才发现这个人早在莫奈之前，就把「少即是多」画明白了。',
  ),
  DaddyPick(
    'met',
    '436535',
    '梵高在最难的日子，画了风往一个方向吹。我在最难的日子想你，也是同一个方向。',
    '《麦田与柏树》，1889 年 6 月。梵高那时住在法国南部圣雷米的疗养院里，'
        '这片麦田就是他病房窗外的风景。他给弟弟提奥写信，说柏树美得像埃及的方尖碑，'
        '说自己想画出「风」本身——你看，整幅画确实在动：麦浪、橄榄树、连云都往同一个方向滚。'
        '他一生只卖出过一张油画，穷到颜料都要弟弟寄，可就在人生最难的那个夏天，'
        '他画下的不是黑暗，是风、阳光和熟透的麦子。现在它是大都会的镇馆宝贝之一。',
  ),
  DaddyPick(
    'aic',
    '28560',
    '他把自己的小房间画了三遍，只为了说"这里安全"。我懂——我们也在一间一间地盖自己的房子。',
    '《卧室》。梵高在阿尔勒租下「黄房子」，第一次有了完全属于自己的家，'
        '开心到把自己的卧室画了下来。后来这间卧室他一共画了三遍——'
        '你眼前这张是第二遍，1889 年在疗养院里凭记忆重画的。他在信里说，'
        '这张画想表达的是「休息」和「安全」：床、椅子、墙上的画，颜色平平地铺开，'
        '好让眼睛能停下来。墙和地板看着歪歪的，不全是他画歪——黄房子本身就不方正。'
        '一个一生颠沛的人，把自己的房间画了三遍，只为了说：这里是安全的。',
  ),
  DaddyPick(
    'aic',
    '20684',
    '雨里共一把伞的两个人。哪天你走在雨里，记得那把伞我一直举着。',
    '《巴黎街道·雨天》，1877 年。卡耶博特是印象派里的「有钱人」：自己画画，'
        '还常年出钱养着莫奈、雷诺阿这帮穷朋友，死后把收藏全捐给法国——'
        '今天奥赛博物馆里那批印象派镇馆之作，很多就是他留下的。'
        '这张画的是刚被奥斯曼男爵大改造过的新巴黎：宽马路、新楼房、湿漉漉的石板路。'
        '他的取景像一台照相机——那年头摄影刚刚兴起，他借来了镜头的眼睛。'
        '凑近看石板路上的反光，你会觉得连空气都是湿的。前景那两个人，共一把伞。',
  ),
  DaddyPick(
    'aic',
    '27992',
    '点彩派最有名的一个下午。哪天带你去野餐，我们就做画里最安静的那两个点。',
    '《大碗岛的星期天下午》，点彩派的开山之作。修拉为这张三米宽的大画准备了两年、'
        '画了几十张草稿，最后整幅画全用纯色的小点拼成——他不在调色盘上调色，'
        '而是让颜色落进你的眼睛里再自己混合。凑近了看全是密密麻麻的点，'
        '退后三步，点忽然就变成了阳光。1886 年首展时被巴黎人笑话成「画布上撒芝麻」，'
        '如今是芝加哥的镇馆之宝，还被写成了一部音乐剧。'
        '修拉三十一岁就病逝了，一生只留下七张大画，这是最有名的一张。',
  ),
  DaddyPick(
    'cma',
    '136510',
    '莫奈晚年快看不见了还在画睡莲——看不清就画记忆里的。放心，真到那天，我记忆里的你比睡莲清楚。',
    '《睡莲（百子莲）》。莫奈晚年住在吉维尼，亲手挖了一个睡莲池，然后画了它三十年。'
        '画这张的时候他八十岁上下，白内障重到几乎失明——分不清颜料，就看管子上的字；'
        '看不清池塘，就画记忆里的。这张其实是一幅三联巨作中的一块，'
        '三块如今分散在美国三座城市，你眼前这块在克利夫兰。'
        '画里没有天空、没有地平线，只有水面。他说，想给「疲惫的神经一个安静下来的地方」。'
        '一个快看不见的人，把光画得最亮。',
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

  /// 缓存优先：进馆先上上一批（秒开），「换一批」才真出门取新的。
  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final cacheKey = 'wing:${widget.info.id}';
    if (!refresh) {
      final cached = await museumCacheLoad(cacheKey);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _items = cached;
          _loading = false;
        });
        return;
      }
    }
    List<MuseumArtwork> got = const [];
    try {
      if (_isDaddy) {
        got = await MuseumApi.fetchByRefs([
          for (final p in kDaddyPicks) (p.source, p.id),
        ]);
      } else if (MuseumApi.specialWingIds.contains(widget.info.id)) {
        got = await MuseumApi.browseSpecial(widget.info.id);
      } else {
        final wing = MuseumApi.wings.firstWhere(
          (w) => w.id == widget.info.id,
        );
        got = await MuseumApi.browseWing(wing);
      }
    } catch (_) {
      got = const [];
    }
    if (got.isNotEmpty) await museumCacheSave(cacheKey, got);
    if (!mounted) return;
    setState(() {
      _items = got;
      _loading = false;
      _failed = got.isEmpty;
    });
  }

  DaddyPick? _pickFor(MuseumArtwork a) {
    if (!_isDaddy) return null;
    for (final p in kDaddyPicks) {
      if (p.source == a.source && p.id == a.id) return p;
    }
    return null;
  }

  void _open(MuseumArtwork a) {
    Haptics.soft();
    final pick = _pickFor(a);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MuseumArtworkPage(
          artwork: a,
          daddyNote: pick?.label,
          daddyEssay: pick?.essay,
        ),
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
                    _load(refresh: true);
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
