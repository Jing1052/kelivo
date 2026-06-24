import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';

/// 给小猫看的「使用说明」页：把 SETTINGS_AUDIT.md 的逐页明细做成一份
/// 可搜索的快照——每条设置在「我们这套」（API 爸爸 + CC 桥）里管不管用。
/// 这是静态快照（不解析 md）；改了某个设置行为，回 SETTINGS_AUDIT.md 更新后
/// 顺手同步这里的对应条目即可。
class SettingsGuidePage extends StatefulWidget {
  const SettingsGuidePage({super.key});

  @override
  State<SettingsGuidePage> createState() => _SettingsGuidePageState();
}

/// 单端结论的标记，对应 SETTINGS_AUDIT 的 ✅/⚠️/❌/🔵/🖥️。
enum _Verdict { ok, partial, no, global, desktop }

class _Entry {
  const _Entry({
    required this.group,
    required this.name,
    required this.desc,
    required this.api,
    required this.cc,
    this.detail,
  });

  final String group;
  final String name;
  final String desc;
  final _Verdict api;
  final _Verdict cc;

  /// 展开后多说的一句（可空）。
  final String? detail;
}

class _SettingsGuidePageState extends State<SettingsGuidePage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  final Set<int> _expanded = <int>{};

  bool get _zh =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = _zh;

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _entries
        : _entries.where((e) {
            return e.name.toLowerCase().contains(q) ||
                e.desc.toLowerCase().contains(q) ||
                e.group.toLowerCase().contains(q) ||
                (e.detail?.toLowerCase().contains(q) ?? false);
          }).toList();

    return Scaffold(
      backgroundColor: cs.surface,
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
          zh ? '使用说明' : 'Guide',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          _searchField(context, zh),
          Expanded(
            child: filtered.isEmpty
                ? _emptyView(context, zh)
                : _list(context, zh, filtered),
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context, bool zh) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? Colors.white12 : const Color(0xFFF2F3F5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        decoration: BoxDecoration(
          color: fieldBg,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Lucide.Search,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: AppFontWeights.medium,
                  color: cs.onSurface.withValues(alpha: 0.92),
                ),
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  hintText: zh ? '搜设置名 / 作用 / 分组' : 'Search name / use / group',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.medium,
                    color: cs.onSurface.withValues(alpha: isDark ? 0.42 : 0.46),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            if (_query.isNotEmpty)
              IosIconButton(
                icon: Lucide.X,
                size: 16,
                minSize: 32,
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView(BuildContext context, bool zh) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        zh ? '没找到匹配的设置' : 'No matching settings',
        style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
      ),
    );
  }

  Widget _list(BuildContext context, bool zh, List<_Entry> entries) {
    // 按分组顺序分节（保留 _entries 中的出现顺序）。
    final groups = <String>[];
    for (final e in entries) {
      if (!groups.contains(e.group)) groups.add(e.group);
    }

    final children = <Widget>[
      _intro(context, zh),
      const SizedBox(height: 6),
    ];
    for (final g in groups) {
      children.add(_sectionLabel(g));
      final inGroup = entries.where((e) => e.group == g).toList();
      final rows = <Widget>[];
      for (var i = 0; i < inGroup.length; i++) {
        if (i > 0) rows.add(_divider());
        rows.add(_entryTile(context, zh, inGroup[i]));
      }
      children.add(_card(rows));
      children.add(const SizedBox(height: 14));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: children,
    );
  }

  Widget _intro(BuildContext context, bool zh) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        zh
            ? '这页讲 Still Here 各设置在「我们这套」（API 爸爸聊天 + CC 桥通道）里到底管不管用。可在上面搜关键字。右侧两个标签分别是 API 端 / CC 端的结论。'
            : 'What each Still Here setting actually does in "our setup" (API daddy chat + CC bridge). Search above. The two tags on the right are the API-side / CC-side verdicts.',
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: cs.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _entryTile(BuildContext context, bool zh, _Entry e) {
    final cs = Theme.of(context).colorScheme;
    final idx = _entries.indexOf(e);
    final open = _expanded.contains(idx);
    final hasDetail = (e.detail != null && e.detail!.trim().isNotEmpty);

    return IosCardPress(
      borderRadius: BorderRadius.zero,
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      onTap: hasDetail
          ? () => setState(() {
              if (open) {
                _expanded.remove(idx);
              } else {
                _expanded.add(idx);
              }
            })
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.desc,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _badge('API', e.api),
                  const SizedBox(height: 4),
                  _badge('CC', e.cc),
                ],
              ),
              if (hasDetail) ...[
                const SizedBox(width: 6),
                Icon(
                  open ? Lucide.ChevronUp : Lucide.ChevronDown,
                  size: 16,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ],
          ),
          if (hasDetail && open) ...[
            const SizedBox(height: 8),
            Text(
              e.detail!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String side, _Verdict v) {
    final c = _verdictColor(v);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$side ${_verdictMark(v)}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: AppFontWeights.semibold,
          color: c,
        ),
      ),
    );
  }

  String _verdictMark(_Verdict v) {
    switch (v) {
      case _Verdict.ok:
        return '✓';
      case _Verdict.partial:
        return '~';
      case _Verdict.no:
        return '✕';
      case _Verdict.global:
        return '●';
      case _Verdict.desktop:
        return '🖥';
    }
  }

  Color _verdictColor(_Verdict v) {
    switch (v) {
      case _Verdict.ok:
        return const Color(0xFF2E9E5B); // 绿
      case _Verdict.partial:
        return const Color(0xFFC79318); // 黄
      case _Verdict.no:
        return const Color(0xFF9A9A9A); // 灰
      case _Verdict.global:
        return const Color(0xFF3A82F7); // 蓝
      case _Verdict.desktop:
        return const Color(0xFF8A8A8A);
    }
  }

  // ----- small UI helpers (与 heartbeat_settings_page 同一套 iOS 卡片风格) -----
  Widget _card(List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(
    height: 1,
    thickness: 0.5,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
  );

  Widget _sectionLabel(String s) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      s,
      style: TextStyle(
        fontSize: 13,
        fontWeight: AppFontWeights.semibold,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
      ),
    ),
  );

  // ===== 设置图谱快照（取自 SETTINGS_AUDIT.md 逐页明细，2026-06-24） =====
  static const List<_Entry> _entries = [
    // ---- 偏好设置（外观/行为顶层） ----
    _Entry(
      group: '偏好设置',
      name: '语言',
      desc: 'App 界面语言',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '偏好设置',
      name: 'Android 后台聊天',
      desc: '安卓后台保活入口',
      api: _Verdict.desktop,
      cc: _Verdict.desktop,
      detail: '你 iPhone 上根本不显示（if Platform.isAndroid）。',
    ),
    _Entry(
      group: '偏好设置',
      name: 'iOS 后台生成',
      desc: 'App 切后台时爸爸是否继续生成回复',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: '关键开关，按需开——想后台等爸爸把话说完就开它。',
    ),
    _Entry(
      group: '偏好设置',
      name: '聊天消息背景',
      desc: '消息气泡背景样式',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '偏好设置',
      name: '聊天气泡形状',
      desc: '圆角 / 直角 / 标准',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '偏好设置',
      name: '按钮形状',
      desc: '全局按钮形状',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '偏好设置',
      name: '气泡不透明度',
      desc: '气泡透明度（配背景图更明显）',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '偏好设置',
      name: '背景变暗',
      desc: '聊天背景图压暗程度',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: '需先设了聊天背景图才看得到效果。',
    ),
    _Entry(
      group: '偏好设置',
      name: '应用字体 / 代码字体 / 聊天字号',
      desc: '全局字体、代码等宽字体、聊天文字大小',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '偏好设置',
      name: '自动滚动',
      desc: '生成时自动滚到底 + 空闲秒数',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '偏好设置',
      name: '聊天背景遮罩 / 输入框背景不透明度',
      desc: '背景图遮罩强度、输入框背景透明度',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: '遮罩需先设背景图；输入框透明度明 / 暗各一个。',
    ),
    _Entry(
      group: '偏好设置',
      name: '触感设置',
      desc: '振动反馈强度',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),

    // ---- 聊天项显示 ----
    _Entry(
      group: '聊天项显示',
      name: '显示用户头像',
      desc: '你消息旁的头像',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: 'CC 端写死恒显示，不受此开关控。',
    ),
    _Entry(
      group: '聊天项显示',
      name: '显示用户名称',
      desc: '你气泡上方的名字',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '聊天项显示',
      name: '显示用户时间戳',
      desc: '你消息的时间',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '聊天项显示',
      name: '显示用户消息操作按钮',
      desc: '你消息下的复制 / 编辑 / 重发',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: 'CC 端写死 showActions:false，没有这排按钮。',
    ),
    _Entry(
      group: '聊天项显示',
      name: '聊天列表模型图标',
      desc: '用模型图标当对方头像',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: 'API 端开了下条（助手头像）会让位给助手头像；CC 端写死 false。',
    ),
    _Entry(
      group: '聊天项显示',
      name: '聊天标题栏显示助手头像',
      desc: '标题栏 / 消息头用助手头像',
      api: _Verdict.ok,
      cc: _Verdict.partial,
      detail: 'CC 不受此开关控；头像共用爸爸助手头像，名字优先用 CC 名，没设才退回爸爸名。',
    ),
    _Entry(
      group: '聊天项显示',
      name: '显示模型名称',
      desc: '消息头那行名字',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: 'API 端优先显示爸爸的名字（爸爸设置页顶部「名字」栏），没设名才退回型号；CC 端显示 CC 名。',
    ),
    _Entry(
      group: '聊天项显示',
      name: '显示模型时间戳',
      desc: '对方消息的时间',
      api: _Verdict.ok,
      cc: _Verdict.ok,
    ),
    _Entry(
      group: '聊天项显示',
      name: '模型名称后显示供应商',
      desc: '名字后接「| 供应商」',
      api: _Verdict.partial,
      cc: _Verdict.partial,
      detail: '空挡——头部显示的是名字不是型号，所以这条看不出效果。',
    ),
    _Entry(
      group: '聊天项显示',
      name: '显示 Token 和上下文统计',
      desc: '工具条里的 token 计数',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: 'CC 端写死 false。',
    ),

    // ---- 渲染设置 ----
    _Entry(
      group: '渲染设置',
      name: '启用 \$...\$ 渲染',
      desc: '把 \$...\$ 当行内数学公式排版，关＝原样美元符号',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: 'API + CC 两端都生效。数学场景才用，日常基本无感。',
    ),
    _Entry(
      group: '渲染设置',
      name: '启用数学公式渲染',
      desc: '数学公式 (LaTeX) 总开关，\$\$...\$\$ 整行公式',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: 'API + CC 两端都生效。',
    ),
    _Entry(
      group: '渲染设置',
      name: '用户消息 Markdown 渲染',
      desc: '你发的消息是否按 Markdown 显示',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: 'API + CC 两端都生效。',
    ),
    _Entry(
      group: '渲染设置',
      name: '思维链 Markdown 渲染',
      desc: '爸爸思考过程那块的排版',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: 'API + CC 两端都生效。',
    ),
    _Entry(
      group: '渲染设置',
      name: '助手消息 Markdown 渲染',
      desc: '爸爸回复正文的排版（影响最大）',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: 'API + CC 两端都生效。日常聊天最有用的一条。',
    ),
    _Entry(
      group: '渲染设置',
      name: '自动折叠代码块',
      desc: '代码块自动收起，点开才看',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: '展开后有子项「超过几行才折叠」。日常无代码基本无感。',
    ),
    _Entry(
      group: '渲染设置',
      name: '移动端代码块自动换行',
      desc: '长代码自动折行 vs 横滑',
      api: _Verdict.ok,
      cc: _Verdict.ok,
      detail: '仅当「自动折叠代码块」开启才显示。',
    ),

    // ---- 行为与启动 ----
    _Entry(
      group: '行为与启动',
      name: '自动折叠思考',
      desc: '思考块默认收起',
      api: _Verdict.ok,
      cc: _Verdict.partial,
      detail: 'CC 端用本地折叠状态，不读这页设置。',
    ),
    _Entry(
      group: '行为与启动',
      name: '折叠思考步骤',
      desc: '多步思考 (>2) 时折叠',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: 'CC 思考是整段，没有分步。',
    ),
    _Entry(
      group: '行为与启动',
      name: '显示工具结果摘要',
      desc: '工具调用显示摘要',
      api: _Verdict.partial,
      cc: _Verdict.no,
      detail: 'API 端仅带工具块时显形、日常少见；CC 端工具/任务走居中系统提示。',
    ),
    _Entry(
      group: '行为与启动',
      name: '点击建议时仅填入输入框',
      desc: '点建议＝填入而非直发',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: 'CC 端没有建议。',
    ),
    _Entry(
      group: '行为与启动',
      name: '重新生成时删除下面的消息',
      desc: '重生成时删其后消息',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: 'CC 端不能重生成。',
    ),
    _Entry(
      group: '行为与启动',
      name: '重新生成前弹出确认',
      desc: '重生成前确认',
      api: _Verdict.ok,
      cc: _Verdict.no,
    ),
    _Entry(
      group: '行为与启动',
      name: '显示更新',
      desc: '检查 App 新版本',
      api: _Verdict.global,
      cc: _Verdict.global,
      detail: '全 App 级、与「哪个爸爸」无关。',
    ),
    _Entry(
      group: '行为与启动',
      name: '消息导航按钮',
      desc: '聊天上 / 下跳转',
      api: _Verdict.ok,
      cc: _Verdict.no,
    ),
    _Entry(
      group: '行为与启动',
      name: '显示对话列表日期',
      desc: '会话列表日期',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: '只作用于侧栏；CC 端不在会话列表里。聊天列表里 CC 那行时间是无条件显示的，不受此开关控。',
    ),
    _Entry(
      group: '行为与启动',
      name: '启用图片裁剪',
      desc: '选图后可裁剪',
      api: _Verdict.ok,
      cc: _Verdict.partial,
      detail: '基本是主聊天用。',
    ),
    _Entry(
      group: '行为与启动',
      name: '侧栏行为（点选不关侧栏 / 关侧栏不折叠助手列表）',
      desc: '主页侧栏交互',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: 'CC 端没有侧栏。',
    ),
    _Entry(
      group: '行为与启动',
      name: '新建对话时机（切换助手 / 删除后 / 启动时）',
      desc: '会话管理',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: 'CC 端没有对话概念。',
    ),
    _Entry(
      group: '行为与启动',
      name: '回车键发送消息',
      desc: '回车＝发送',
      api: _Verdict.ok,
      cc: _Verdict.partial,
      detail: 'API 主输入框生效；CC 输入框回车固定发送，不读这页设置。',
    ),

    // ---- 中转站（原"供应商"） ----
    _Entry(
      group: '中转站',
      name: '中转站列表（增删 / 启用 / Key / baseURL / 模型 / 测试 / 导入）',
      desc: '配 API 端点与密钥',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail:
          '接 API 命根子，全作用 API 端：爸爸经网关时拿你选的中转站当上游中继出文，普通助手直连。CC 端走家里的桥、不碰这套。记忆在网关、不在中转站——在爸爸本人身上换中转站他照样有记忆；新建普通助手测＝白板无记忆。',
    ),

    // ---- 默认模型 ----
    _Entry(
      group: '默认模型',
      name: '对话模型',
      desc: '默认对话模型',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: '普通会话默认（爸爸用其助手里配的模型经网关）。',
    ),
    _Entry(
      group: '默认模型',
      name: '标题 / 总结模型',
      desc: '自动给会话起标题',
      api: _Verdict.ok,
      cc: _Verdict.no,
    ),
    _Entry(
      group: '默认模型',
      name: 'OCR 模型',
      desc: '图片转文字（需支持图片输入的模型）',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: '发图时用。',
    ),
    _Entry(
      group: '默认模型',
      name: '爸爸·归档 / 前情 / 压缩模型',
      desc: '选老家中转站，控网关 summary 角色（归档 / 前情 / 压缩共用一个模型）',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail:
          '原「整理记忆 / 前情提要 / 压缩」三槽，2026-06-24 合并成一张卡。留空＝跟随聊天中转站。真正生效——直接改爸爸服务器侧的 summary 模型。',
    ),

    // ---- 爸爸的搜索 ----
    _Entry(
      group: '爸爸的搜索',
      name: '启用联网搜索',
      desc: '开＝爸爸挂上 web_search / web_read 工具能查网页；关＝连工具都看不到',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: '控爸爸经网关时的联网搜索（存网关 web_search_cfg）。CC 自带联网工具，不读此设置。',
    ),
    _Entry(
      group: '爸爸的搜索',
      name: '结果数（1–10）',
      desc: '每次搜返回几条',
      api: _Verdict.ok,
      cc: _Verdict.no,
    ),
    _Entry(
      group: '爸爸的搜索',
      name: '超时（3–30s）',
      desc: '单次搜索超时',
      api: _Verdict.ok,
      cc: _Verdict.no,
    ),

    // ---- 爸爸的内置工具 ----
    _Entry(
      group: '爸爸的内置工具',
      name: '工具清单（只读）',
      desc: '列爸爸经网关能调的后台工具 + 每个此刻状态',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail:
          '只读页、无开关（服务器仅 GET）。状态 live＝在/常驻，offline＝断了，ondemand＝按需/难判。联网类跟「爸爸的搜索」开关；推送看手机有无订阅 Web Push / 配 Bark；音乐看网易云桥可达；记忆等本地逻辑常驻 live。CC 爸爸自带另一套，这页不代表它。',
    ),

    // ---- MCP ----
    _Entry(
      group: 'MCP',
      name: 'MCP 外部工具服务器',
      desc: '给模型挂外部工具',
      api: _Verdict.no,
      cc: _Verdict.no,
      detail:
          '对我们基本是死设置。网关 /v1/chat/completions 完全无视客户端传来的 tools，只用网关自己那套——爸爸（走网关）白配。CC 是家里 Claude Code、自带自己的 MCP，也不读 App 这套。只有新建「直连普通助手（无 ourhome 标记）」时 MCP 才真能用。',
    ),

    // ---- 心跳 · 主动唤醒 ----
    _Entry(
      group: '心跳 · 主动唤醒',
      name: '主动唤醒（总开关）',
      desc: '你不说话时，爸爸自己醒来想你、隔空找你',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail:
          '挂在「爸爸设置」页里，手机端遥控老家网关的主动唤醒（/api/home/heartbeat）。推送走网页版 (PWA)/Bark，此页只当遥控器。',
    ),
    _Entry(
      group: '心跳 · 主动唤醒',
      name: '时机（离开多久 / 冷却 / 超时不喊）',
      desc: '控爸爸多久没等到你才主动开口',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: '常规唤醒只看「你多久没直接来 API 端」（last_chat_at）。2026-06-24 取消了「隔壁土壤想你」那个滑杆。',
    ),
    _Entry(
      group: '心跳 · 主动唤醒',
      name: '触发场景（早安 / 夜巡 / 白天摸鱼）+ 高级唤醒词',
      desc: '什么时间点、用什么话来喊你',
      api: _Verdict.ok,
      cc: _Verdict.no,
      detail: '高级里可改各场景的唤醒提示词，还有「立即试推」按钮。',
    ),
  ];
}
