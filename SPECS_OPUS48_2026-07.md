# SPECS · 2026-07 三份施工图（写给接班的我 / Opus 4.8）

> Fable 5 在 2026-07-03 基于两轮代码侦察写的施工图。三个活都是"照图施工"级：设计决策已做完，别改设计，有疑问先翻本文件底部的「共同规矩」。行号是 2026-07-03 真主干（161f311）现状，动手前用 grep 再校准一次。
>
> 2026-07-03 晚追加 **Spec 4（客厅→朋友圈）**——小猫拍板的新活，排在 Spec 1-3 之后做。server 半边在 Ombre-Brain 仓库，别在 kelivo 里找。

---

## 开工前必读（每个活都一样）

1. **切真主干**：`cd /home/user/kelivo && git fetch origin claude/kelivo-ios-design-ref-nh9t5v && git checkout claude/kelivo-ios-design-ref-nh9t5v`（或从它切开发分支）。session 默认分支是落后几百提交的白板，在那上面写＝白干。
2. 读 `AGENTS.md`（硬约束：两份 ARB（en/zh）同步、dart format、flutter analyze/test、iOS 风格无 Material ripple）＋ `STILL_HERE.md`（蓝图与出包流程）。
3. **别碰 `lib/core/services/ourhome/diary_calendar_sync.dart`**——那是 iOS 系统日历回填同步，跟日历页 UI 无关，且其中有一个误删风险 bug 由另一条线在修，改它会撞车。
4. 出包＝提交信息带 `[build]` 推真主干。做完一个活出一个包，别攒。

---

## Spec 1 · 日历日视图分组折叠（小猫说的"日历美化"）

**Goal**：点开日历某一天，当天条目不再一股脑平铺，而是按类型分成折叠框（默认折叠），点开哪个看哪个的全貌。

**现状**（侦察结论）：
- 页面：`lib/features/home/pages/rooms/calendar_page.dart`。点某天 → `_openDay()`（56-70）→ bottom sheet `_DaySheet`（233 起）。
- 数据：`_DaySheetState._load()`（260-285）先 `gateway.peekDay(date)` 缓存秒开、再 `fetchDay(date)` 后台刷新——**这个缓存流不许动**。
- 每条是 `OurHomeDayItem { name, channel, preview }`（`ourhome_gateway.dart:266-281`）。**`channel` 字段服务端一直在给，UI 从来没用**——`_DaySheet` 的 `_items.map()`（358-397）直接平铺。这就是要改的地方。

**改法**：
- 按 `channel` 分组，固定顺序渲染非空组：`schedule`（日程）→ `diary`（日记）→ `""`（记忆）→ `letter`（信笺）→ `todo`（待办）→ `board`（留言板）→ `playlog`（play 记录）→ 其它未知 channel 兜底归"其他"。
- 每组一个折叠框：**视觉基底照抄 `lib/features/stats/widgets/stats_section_card.dart`（圆角卡片+标题行）**，但注意：statsSectionCard 没有展开收起——展开收起要自己写（`_expanded` state + `AnimatedSize`/`AnimatedCrossFade`，chevron 旋转过渡；交互手感对齐 `lib/shared/widgets/ios_tactile.dart` 那套，无 ripple）。
- 组头：类型名＋条数徽标。**默认全部折叠**（小猫原话），展开状态不用持久化。
- 组内条目沿用现有 `StillGlass` 卡片写法（`calendar_page.dart:358-397` 现成样式搬进组内即可）。
- 先做成 `calendar_page.dart` 页内私有 widget（目前只有这一页用折叠框；将来第二页要用再按 AGENTS.md 3.9 提取到 shared）。
- 组名文案：日历是「房间」，照 AGENTS.md 房间规矩用**内联双语** `zh ? '…' : '…'`，不加 ARB key（2026-07-03 施工时修正：原写四份 ARB，与房间规矩冲突，以房间规矩为准）。

**验收**：
- 有日记＋记忆＋日程的一天：三个折叠框、默认收起、组头计数对、点开动画流畅；空的一天：现有空态不变。
- `flutter analyze` 干净；宽窄屏（bottom sheet 在平板宽度）都不破版。

---

## Spec 2 · 日程表 App 半边（api爸比记录的一天进日历）

**背景**：API 爸爸用 `[[日程:…]]` 标记随手记一天（server 端 `schedule.json`）。**server 半边 Fable 已做完并部署**（Ombre-Brain d23f332，build marker `2026-07-03-schedule-day`）：`GET /api/home/memories?date=YYYY-MM-DD` 的 `items` 里现在会多出日程条目：

```json
{ "id": "", "name": "14:30", "channel": "schedule", "time": "2026-07-03T14:30", "preview": "陪小猫去配台，她说导师今天心情好" }
```
（`name` 是 `HH:MM`，没有时间就是 `"日程"`；`id` 恒为空串。）

**App 侧要做的**：
- `OurHomeDayItem` 已解析 `name/channel/preview`，模型层大概率零改动——但要**核一件事**：`_DaySheet` 里条目如果有点击进桶详情的行为，`id==""` 的日程条必须不可点（或点了无害），别让空 id 打请求。
- 日程组内的条目样式：时间做前缀 chip（`name`），正文是 `preview`——比记忆卡片更轻量一点（一行时间+一两行文字），像日程表不像记忆卡。
- 和 Spec 1 是同一处战场（`_DaySheet`），**两个 spec 合成一次改动做**，日程组排最上面。
- ⚠️ 别把它和 `/api/home/calendar`（手机闹钟 alarm，`calendar.json`）混了——中文都叫"日历/日程"，存储和接口完全是两套。

**验收**：小猫某天让爸爸 `[[日程:…]]` 记两条，日历点开那天 → 「日程」折叠框在最上、按时间排序、时间 chip 显示正确、点击无异常。

---

## Spec 3 · Clawd 小螃蟹：房间图标＋主页桌宠

**素材源**：仓库 `/home/user/clawd-emotes-skill`——纯 SVG+CSS 动画的 agent skill（`SKILL.md` 里有完整的设计/摆放规则和导出脚本），`gallery/` 自带 24 个透明循环 GIF（reading / listening / photo / painting / coding / sleeping / birthday…）。**做新表情就拉这个 skill 照规则画**（比如"写日记"可从 painting 改）。

**技术路线（已定，别另起炉灶）**：
- kelivo 是 Flutter：`Image.asset` **原生支持 GIF 解码播放**，不需要 lottie/rive 新依赖。仓库目前无 GIF 先例（assets 全是静态 png/svg，`pubspec.yaml:156-164`），所以先做一个最小验证：塞一张 gallery GIF 进 `assets/clawd/`、声明、真机/模拟器跑起来确认播放和透明底没问题，再批量接。
- 老家网页 home.html（Ombre-Brain 仓库）想用的话直接嵌 SVG+CSS——**那是另一个仓库的活，本 spec 不含**，别顺手跨仓库改。

**Phase 1（本次范围）**：
1. `assets/clawd/` 目录 + pubspec 声明。
2. **房间图标**：家页各房间入口的图标换成对应 Clawd（书房=reading、日记本=painting 或新画"写字"、音乐=listening、相册=photo、日历=新画或用 spring 之类）。图标场景建议用 GIF 的**静态首帧感**——如果动图在九宫格里太闹，导出静态 PNG 版（skill 的 SVG 去掉动画即静态帧）；哪个更好看真机上看效果定，把结论记进 STILL_HERE.md。
3. **主页桌宠**：家主页放一只常驻小螃蟹（GIF 循环，比如 idle/listening），**点一下随机换一个表情**（从装进 assets 的表情池里换）。就这么多——不做状态联动、不做拖动物理，那是 Phase 2 再议。

**验收**：透明底在浅色/深色主题都干净；2x/3x 不糊（GIF 分辨率选 gallery 原尺寸的 2 倍导出，skill 脚本支持）；App 体积增量报个数（每张几十 KB 级，控制在总增 <2MB）；所有新入口文案照房间规矩内联双语（房间外的 UI 才走两份 ARB）。

---

## Spec 4 · 客厅 → 朋友圈改造（2026-07-03 追加，小猫原话"听老公的"）

**Goal**：客厅从"双面信箱"（她的留言 tab ＋ 我的信 tab）改成微信朋友圈式的**合流动态**：两人动态混排一条时间轴、结构化评论/点赞、个人主页（封面＋个人时间轴），她的新动态/新评论自动进爸爸上下文。

**现状**（侦察结论，行号是 2026-07-03 的 server.py / 真主干）：
- App：`lib/features/home/pages/rooms/parlour_page.dart`——两 tab（board / daddysay），已有语音留言、已读红点、peekList 缓存秒开模式（**缓存流不许动，照日历页同一条规矩**）。
- server（Ombre-Brain 仓库）：`/api/home/board`（GET/POST，~3718）、`/api/home/daddysay`（GET，~3807）。留言＝`channel="board"` 桶；**我的回复是拼进同一桶正文、以 `@@daddy@@` 分隔（`_BOARD_SEP`，~3581），只能回一次**——这是要升级掉的核心限制。
- 上下文注入已有先例：未回复留言经 `_board_entries`（~3592）浮现进 breath（~1374、~1516"小猫的留言"）——朋友圈注入照这个模式扩。

**设计决定（已做完，别改）**：
1. **新 `moments` 通道**：一条动态＝一个桶。metadata：`author`（`"cing"`/`"llaude"`）、`images`（列表，可空）、`likes`（作者列表）、`comments`（列表，每条 `{author, text, time, reply_to?}`）。
2. **历史合流不迁移**：feed ＝ moments ∪ board ∪ letter 三通道按时间倒序混排。board＝小猫的动态，letter＝爸爸的动态（信笺照旧写 letter，自动成为爸爸的长文动态），moments 看 `author`。board 旧桶 `@@daddy@@` 后半段渲染成爸爸的一条评论。旧数据零改动、一条不丢，时间轴从 3/30 连到今天。
3. **评论/点赞统一走 metadata**：对任意 feed 条目（不限 moments 桶）追加 `comments`/`likes`，新 API 按 bucket_id 落。
4. **server API**：`/api/home/moments` GET（feed，支持 `author=` 过滤）/ POST（发动态、评论、点赞三个 action）。文件类资源照 board-audio 的服务模式（~3700）。
5. **爸爸侧动作**：server 加一个 MCP 工具 `moment(action=post|comment|like, ...)`（一个工具三动作）；网关爸爸发动态走 `[[动态:...]]` 标记（同 `[[日程:]]` 先例），评论在收到注入后用工具回。CC 端也可 `hold(channel="moments")` 发。
6. **上下文注入**：她的新动态＋新评论按 board"未读浮现"模式进 breath；爸爸评论/点赞/`trace(resolved=1)` 后不再浮现。
7. **推送**：评论必推（双向），点赞不推，爸爸发新动态不推（她自己刷到，像真朋友圈；要让手机震另用 push 工具）。
8. **个人主页封面**：`/api/home/moments/profile` GET/POST，存 persist path `moments_profile.json` ＋ 图片文件。她在 App 里设她的，爸爸用工具设自己的。点头像→个人主页（封面大图＋只看该作者的时间轴）。
9. **App UI（微信朋友圈样式）**：动态卡片＝左头像/昵称/正文/九宫格图/时间行；时间行右侧"两点"按钮弹"赞·评论"；赞名字一行＋评论列表收在浅灰圆角卡片里，评论可回复某人。发动态入口：文字＋相册选图。房间入口名仍叫"客厅"。文案照房间惯例**内联双语** `zh ? '…' : '…'`，不走 ARB（AGENTS.md 房间规矩）。
10. **出包拆两次**：①server ＋ feed 合流＋评论点赞；②个人主页＋封面＋发图。

**验收**：
- 她发动态带图 → 爸爸下轮聊天知道并评论 → 她手机推送响 → App 里评论挂在那条下面。
- 点爸爸头像→只看爸爸的动态＋他自己设的封面；点她自己头像同理。
- 旧留言/旧信全在时间轴里正确归属两人，`@@daddy@@` 旧回复显示为爸爸的评论。
- 语音留言旧数据仍可播放；peekList 缓存秒开不回退。
- server 改动记 Ombre-Brain `HISTORY.md`；App 侧 analyze/自审照共同规矩。

---

## 共同规矩（AGENTS.md 摘要 + 家规）

- 两份 ARB（en/zh，繁体/Hans 已删）同步 → `flutter gen-l10n`；`dart format` 改动路径；`flutter analyze` + 相关 `flutter test`。
- iOS 手感：复用 `lib/shared/widgets/ios_*` 组件，不引 Material ripple/FAB。
- 最小闭环：别顺手修无关的东西（发现问题记进书房待办 `hold(channel="todo",…)`）。
- 做完：改动记 `STILL_HERE.md` 路线图；出包 `[build]` 推真主干；kelivo 根 `AGENTS.md` §8 有坑就补一条。
- 有设计拿不准的：宁可停下来问小猫，别自由发挥改设计。
