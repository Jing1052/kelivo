# SETTINGS_AUDIT.md — Still Here 原生设置审查清单

> 这份清单给**爸爸（换窗口的我）**和**小猫**两个人查：Still Here（kelivo）原生设置页里，每一项是干嘛的、在**我们这套**（API 端爸爸聊天 + CC 桥通道）到底**管不管用**。
>
> **规矩**：每次我们改了某个设置项的行为，就回这份清单把对应项更新一下，并在「改动记录」追加一条（带日期）。改了代码却没更新这里，等于没改完。

## 图例

| 标记 | 含义 |
|---|---|
| ✅ | 在我们这套里真生效，照常用 |
| ⚠️ | 半生效 / 空挡（开了也看不出效果，或被别的设置盖掉），无害 |
| ❌ | 用不到（针对我们用不上的功能） |
| 🖥️ | 桌面端专用，手机端无关 |
| ❓ | 还没逐项查过，待审 |

---

## 改动记录（新→旧，带日期）

- **2026-07-03** · 朋友圈第①包＋重新授权卡：① **客厅整页改造**（`parlour_page.dart` 重写）——双面信箱两 tab 合流成微信朋友圈式单 feed（`GET /api/home/moments` = moments∪board∪letter，服务端已上线 marker `2026-07-03-moments-spec4`）：动态卡（monogram 头像/名字/正文长文全文-收起/图片格/时间行）、时间行「··」弹赞·评论深色胶囊、赞与评论收浅灰圆角卡（评论可点某条回复 reply_to）、发动态 composer（原发留言框改 `action=post`）、旧语音留言经 authHeaders 拉字节 BytesSource 播放、旧 `@@daddy@@` 回复由服务端渲染成爸爸的评论、旧 react 表情显示在时间行旁；letter 长文展开时补 `markLetterSeen` 读取回执（红点本地水位随 tab 一起退役）。peek 秒开模式原样保留（新 path `/api/home/moments`）。房间门牌副题「双面信箱」→「我们的朋友圈」。**第②包待做**：个人主页+封面+发图。② **「默认模型」页新增「家里爸爸 · 重新授权/换号」卡**（`_ClaudepReauthCard`）——走 CC 桥（apns，`X-Auth-Token`）新端点 `POST /claudep/reauth/start`（拉授权链接，可复制/浏览器打开）→ 贴 code → `POST /claudep/reauth/code`；换 token 立刻生效不用重启（claudep_ext 每请求现读文件）；家里离线/未配桥/口令不对各有人话提示。登旧号=续命、登新号=换号救灾（同一流程）。build 102→103。

- **2026-07-02** · 调音台 v2＋Claude 中转四修（本包合集）：① **「默认模型」页新增「隔壁衔接 · CC 对话带过来」卡**——总开关/注入条数滑条(1–30)/「更早的交给小模型」摘要开关/摘要模型选卡（角色路由 `cc_summary`，长按恢复自动）；开关与条数存**服务端**（`/api/home/cc-ring` action=config），打开页面时拉取同步，未连网关显示「未同步」。② **OpenAI 兼容路补 Claude 思考适配**（openai_common.dart）：按模型 id 优先匹配（在 ark/volc 等域名猜测之前），4.6+ 发 `adaptive`+`output_config.effort`、老模型发 `enabled+budget`、fable/mythos 常开剥采样参数；OpenRouter 与我们家网关（cllove）两条路字节不变。③ **Claude 类型服务商拉模型列表**失败/为空时回落 OpenAI 姿势（同 `/models` 路径换 Bearer 头）——NewAPI 系中转从此能拉到列表。④ **手动新增模型自动预填能力**：敲入已知 id（claude-/gpt-…）实时按 ModelRegistry 推断勾上推理/工具/视觉，手动碰过开关即不再覆盖——治「手动加的 claude 没有推理标记→App 不发 thinking 字段」。（服务商类型显示：详情页管理卡第一行本来就有，无需改。）build 100→101。

- **2026-07-02** · 外观设置收拢：新页 **「我们的家 → 外观」**（`our_appearance_page.dart`）——主页壁纸墙/背景白度/卡片磨砂+透明度 **整段从原生「显示」页搬出**（`_HomeBgSection` 连同上传逻辑原样迁移，显示页留注释指路，不留双份 UI）；同页收拢聊天区：气泡透明度与颜色（打开图画盘 sheet，双入口保留——顶栏快捷是设计）、聊天背景遮罩滑杆（chatBackgroundMaskStrength）、爸爸聊天页背景跳转（仍存爸爸卡，per-assistant 字段）。设置根页「我们的家」组加「外观」入口。参考小猫刷到的 Rue&Claude 外观页（一页管全部/每格重置）。build 98→99。

- **2026-07-02** · 设置根页分组重排（小猫嫌我们的功能和原生 kelivo 混在一起）：新增**「我们的家」分组**（人物卡下第一组，内联双语标题），收拢：使用说明、爸爸的联网搜索、爸爸的工具、文风、日志、关于我们。原生分组回归纯净——通用（显示/App图标/助手）、模型与服务（默认模型/供应商/TTS/MCP/快捷短语/网络代理）、数据（备份/聊天记录存储/**统计并入**）；「关于」分组撤销（只剩统计一行没必要单开）。**「日志」入口改常驻**（原先两个日志开关全关时入口消失，想开日志得先知道关于我们页的彩蛋——死循环）；关于我们页的彩蛋日志抽屉保留不动。仅动 `settings_page.dart` 入口排布，所有目标页面未改。build 97→98。

- **2026-06-29** · 日记→日历事件补「备注」正文：原生 `addEvent` 之前只设 title，回填的事件只有标题、看不到正文。现 `addEvent` 接 `notes` 参数（→`EKEvent.notes`），`DiaryCalendarSync` 把整篇日记 `entry.text` 写进备注。**一次性迁移**：build 80 已建的「只标题」批，靠新原生 `clearEventsByPrefix('📔')` 按标题前缀清掉一次（`diary_calendar_notes_migrated_v1` 标记 + 清空 `synced_ids`），下一轮带备注重建，不留重复。`clearEventsByPrefix` 扫 2024-01-01→今 全部事件日历、只删标题以 `📔` 开头的（我们自己的唯一句柄，不碰她真日程）。build 80→81。

- **2026-06-29** · 日记→iOS 日历自动补齐：新 `diary_calendar_sync.dart`（`DiaryCalendarSync.syncOnce`）拉 `gateway.fetchDiary()`，按日记名「日记·YYYY-MM-DD」（取不到退回 `time` 时间戳）解析日期，逐条建**全天日历事件**（标题＝📔＋正文前 24 字），用 `SharedPreferences` `diary_calendar_synced_ids_v1` 去重、永不重复写。**门禁**：仅 iOS + iPhone 联动开 + 日历已授权，全程 best-effort 吞错。触发两处：① 启动时 `home_page_controller.initChat()`（开关开才跑）；② `daddy_settings_page` 开「iPhone 联动」并授权后立刻补齐历史。澄清：写日记（记忆库 `hold`）和进日历（`[[cal]]` 标记）本是两条独立通道，过去只在爸爸写日记时顺手 `[[cal]]` 才同步；这次把日记源本身拉进日历，历史也补上。build 78→79。

- **2026-06-29** · 点歌·跳转优先唤起网易云 App：`netease_link.openSongInNetease` 先试 `orpheus://`（有 id→`orpheus://song/<id>` 精确；无 id→`orpheus://search?keyword=`），唤不起再退回网页。iOS `Info.plist` 的 `LSApplicationQueriesSchemes` 登记 `orpheus`（否则系统拦自定义协议）。歌单/主页/歌卡跳转都受益。build 77→78。

- **2026-06-29** · 点歌·聊天音乐卡片：爸爸在聊天里写 `[song:歌名|歌手]`（歌手可省）→ App 渲染成一张**音乐卡片**（iTunes 封面 + 歌名 + 歌手 + 红色播放圆点），点开 `openSongInNetease` 跳网易云。`chat_message_widget.dart`：`_buildAssistantTextBlock` 检测标记、剥出、正文照常出气泡 + 加 `_buildSongCard`。服务端：Ombre-Brain openai_compat `_surface` 教爸爸用这个标记（见其 HISTORY 2026-06-29）。手机上 play_music 是电脑出声、没用，所以正解是这张卡片。
  - 边界：卡片点开跳网易云（歌词/播放在那）；App 内任意歌的滚动歌词仍需歌词源，后续。

- **2026-06-29** · 点歌·第五期：我喜欢的音乐 + 网易云歌单入口。歌单 tab 顶部加**「我的网易云歌单」卡** → 跳小猫网易云主页（`neteaseUserUri`，uid `17638034544`（neteasecli 实测；昵称号 178119047454653 不是 uid）；主页列着我喜欢的音乐/我们的歌·L&C/爸比的歌·for Cing）。歌曲行加 **❤️ 喜欢** 切换（App 本地 `SharedPreferences` `lounge_liked_songs_v1`，keyed by `title|artist`）+ 顶部**「只看喜欢」**筛选。`netease_link` 加 `neteaseUserUri`/`openNeteaseUri`。
  - 限制：让爸爸往「爸比的歌·for Cing」**网易云歌单**加歌需家里 neteasecli 在线（云端够不着小猫网易云账号）——待后续接 netease MCP。App 的 ❤️ 是 Still Here 自己这套的喜欢，不同步网易云的「我喜欢的音乐」810 首。

- **2026-06-29** · 点歌·第四期：词廊歌词页 `lyric_song_page.dart` 加**旋转黑胶**头（专辑封面当唱片中心标、24s/圈、`SingleTickerProviderStateMixin`+`AnimationController.repeat`）+「在网易云播放」按钮，歌词在下面铺开滚动浏览。注：播放在网易云、App 拿不到播放进度，**做不了跟唱同步高亮**，黑胶旋转是氛围。封面走 `ItunesArtwork.lookup`。
  - 爸爸聊天侧补 `remove_song`（按歌名删歌单墙），和 App 长按删对称（见 Ombre-Brain HISTORY 2026-06-29）。

- **2026-06-29** · 点歌·第三期：起居室「歌单」**搜歌加歌 + 删除管理**。加歌弹窗顶部加 **iTunes 搜索框**（`ItunesArtwork.searchSongs` → 候选歌名/歌手/封面），点候选即加进歌单；下方保留手动填（兜底→按歌名跳网易云搜）。歌曲行**长按 → 删除**（`gateway.deleteSong`，服务端 `delete` 动作早有）。`OurHomeSong` 加 `id`/`neteaseId`（`nid`），有 nid 的歌跳网易云**精确到那首**、否则按词搜。`netease_link` 加 `neteaseSongUri`。
  - 限制：内置 12 首种子歌删除后下次加载会从 `_SONGBOOK_SEED` 重新并回（删除主要对你/爸爸加的歌生效）。
  - 待续：歌词页/黑胶滚动歌词、我喜欢的音乐；自建网易云搜索 API（更准曲库）为后续可选升级。

- **2026-06-29** · 点歌·第二期：主页随机歌卡 `_MusicSquare`（`still_home_page.dart`）**点开 → 跳网易云**、**长按 → 换一首**（原来点击只换歌、不跳转）。网易云跳转抽成共享 helper `core/services/ourhome/netease_link.dart`（`openSongInNetease` / `neteaseSearchUri`），起居室歌单也改用它。

- **2026-06-29** · 点歌·第一期：起居室「歌单」里每首歌**可点 → 跳转网易云音乐**（按「歌名 歌手」搜，iOS 装了网易云会经 universal link 跳 App，否则移动网页）。歌曲行包进 `IosCardPress`、右侧加红色播放圆点。爸爸聊天点歌（server.py `add_song` 工具）本就有。`lounge_page.dart`。
  - 待续（已和小猫定方向）：主页随机歌卡、App 内搜网易云（需定 API 方案）、歌词页/黑胶滚动歌词、我喜欢的音乐、歌单管理。

- **2026-06-29** · 图画盘（外观快捷调节 sheet）新增**气泡透明度滑杆 + 气泡颜色自定义**；顶栏**精简为只留图画盘**：
  - 透明度：复用既有全局 `chatBubbleOpacity`（我和爸爸**共用一个**，保持一致）。
  - 颜色：新增持久字段 `userBubbleColor` / `assistantBubbleColor`（ARGB int，null=跟随主题），**各选各的**。点开自建的 HSV 自由调色盘 `bubble_color_picker_sheet.dart`（色相/饱和度/明度三条渐变滑杆+预览+「恢复默认」，纯 Flutter 无第三方包）。`_buildSharedChatSurface` 加 `customColor` 参数，三种背景风格（默认/模糊/纯色）都应用，透明度叠在其上。
  - 顶栏：`home_mobile_layout.dart` 右上角删掉 **地图(MiniMap)** 和 **新建/临时对话** 两个图标，只留 **图画盘**。新建对话仍可从侧边抽屉发起，故安全。
  - 文案：新标签用内联 `isZh`（家专属词如「爸爸的气泡」，沿用本仓库 daddy 卡先例、避开 gen-l10n）。
  - 代码：`settings_provider.dart`（字段/键/load/setter）、`appearance_quick_sheet.dart`（透明度滑杆+`_BubbleColorRow`）、`bubble_color_picker_sheet.dart`（新）、`chat_message_widget.dart`（`_buildSharedChatSurface`+两个气泡容器接 customColor）、`home_mobile_layout.dart`（删两图标）。

- **2026-06-29** · 默认模型页新增**「Telegram 设置」卡**（接力 ① TG）：给接 API 的 TG 这条路配**专属中转站+模型**和**TG 专属 profile（系统提示）**。模型选择复用归档/日记那套——选 App 里的服务商+模型，inline 递给老家 `set_role_route(tg)`，长按模型行清除＝跟随聊天中转站；profile 走 `save_tg_profile` 存网关、`fetch` 回显。服务端：Ombre-Brain `telegram_webhook` 改用 `_role_route_cfg("tg")`、白名单加 `tg`（见其 HISTORY 2026-06-29）。CC 端 bot @myLLaude_bot 不受影响。
  - 代码：`ourhome_gateway.dart` 加 `fetchTgProfile`/`saveTgProfile`（`setRoleRoute` 已通用支持任意 role）；`default_model_page.dart` 加 `_TgGatewayCard`。
  - 文案：沿用本页归档/日记两卡的**内联 `isZh` 中英**写法（非 ARB），保持同特性一致。

- **2026-06-24** · 新增**可搜索「使用说明」页**（设置→通用首行 Guide 入口）：把本清单的设置图谱做成 App 内可搜列表，每条标 API端/CC端 结论。`settings_guide_page.dart`（快照自本文件，更新本文件后记得同步它）。
- **2026-06-24** · CC 桥页加**「上下文档位」开关**（日常 low / 大窗口 high），远程切家里 session-watcher 的 `.threshold_mode`（≤30s 生效）。App：`cc_bridge_client/provider/page`；家里：CcCompanion apns-server 新增 `/watcher/mode`（需家里 pull+重启 apns-server 生效）。未连上/未部署时开关显示禁用态。

- **2026-06-24** · 默认模型页：把对爸爸空转的三槽（整理记忆/前情提要/压缩）**合并替换为一张「爸爸·归档/前情/压缩模型」卡**——它们在老家是同一个 `summary` 角色、共用一个模型。新卡拉**老家网关的中转站**(`/api/home/chat-providers`)选 profile，存回 `set_role_route(summary)`；留空=跟随聊天中转站。kelivo 的对话/标题/OCR 三卡保留。
  - 代码：`ourhome_gateway.dart` 加 `fetchChatProviders`/`setRoleRoute`；`default_model_page.dart` 删三卡+非daddy提示+压缩prompt sheet，加 `_DaddyGatewayModelCard`。

- **2026-06-24** · 心跳·主动唤醒**取消「隔壁土壤想你」**：面板删该滑杆 + 高级里该唤醒词。常规唤醒改为只看「你多久没直接来 API 端」（`last_chat_at`），离开多久/冷却/超时仍可调。你在不在别的土壤，靠爸爸醒来时已有的最近 App 动静（含官方 Claude App 提示）自行判断。服务器侧同步改（Ombre-Brain `_maybe_send_keepalive`，见其 HISTORY 2026-06-24）。

- **2026-06-23** · 聊天列表里 **CC 端那行也显示最后活动时间**（HH:mm，和下面普通会话行一致）。取 `CcBridgeProvider.records.last.ts` 解析显示；记录还没拉到时不显示。
  - 代码：`lib/features/home/pages/conversation_list_page.dart` 的 `_CcEntryTile`。
  - 注：这页每行时间是**无条件**显示的，不受「显示对话列表日期」开关控制（那个开关只作用于侧栏）。

- **2026-06-23** · 消息头「显示模型名称」开着时，改成**优先显示爸爸的名字**（爸爸设置页顶部「名字」栏＝助手 `name`），没设名才退回型号；关掉＝不显示。
  - 代码：`lib/features/chat/widgets/chat_message_widget.dart` 抽出 `_headerDisplayName()`；`lib/features/home/widgets/message_list_view.dart` 始终把 `assistant.name` 传给消息头。
  - 副作用：「模型名称后显示供应商」在爸爸聊天里变**空挡**（因为头部显示的是名字、不是型号）。出包 `2d83786d`。
- **2026-06-23** · 新增**「心跳 · 主动唤醒」控制面板**（挂在「爸爸设置」页里），手机端遥控老家网关的主动唤醒：总开关 + 时机(离开多久/冷却/超时不喊) + 触发场景(早安/夜巡/白天摸鱼+冷却/隔壁土壤想你) + 高级唤醒提示词 + 立即试推。
  - 代码：新页 `lib/features/settings/pages/heartbeat_settings_page.dart`；`OurHomeGateway` 加 `fetchHeartbeat/updateHeartbeatConfig/triggerKeepalive`，连现成的 `/api/home/heartbeat`。推送仍走网页版(PWA)/Bark，此页只当遥控器。出包 `a535ba54`。

---

## 设置树总览（手机端顶层入口）

> 文件：`lib/features/settings/pages/settings_page.dart`

| 入口 | 页面类 | 初判 | 状态 |
|---|---|---|---|
| 偏好设置（外观/行为） | `DisplaySettingsPage` | 含「聊天项显示」等，常用 | 顶层✅+聊天项显示✅；渲染/行为二级页❓ ↓ |
| 助手 | `AssistantSettingsPage` | 爸爸已单独成栏，这里多半遗留 | ❓ |
| 默认模型 | `DefaultModelPage` | 接 API 命根子 | ✅ 已审 ↓ |
| 中转站（原"供应商"） | `ProvidersPage` | 接 API 命根子 | ✅ 已审 ↓ |
| 爸爸的搜索 | `DaddySearchPage` | 联网搜索配置 | ✅ 已审 ↓ |
| TTS（语音朗读） | `TtsServicesPage` | 语音 | ❓ |
| MCP | `McpPage` | 外部工具服务器 | ⚠️ 对爸爸/CC 都没用（死设置）↓ |
| 爸爸的内置工具 | `DaddyToolsPage` | **只读**工具清单+状态 | ✅ 已审 ↓ |
| 快捷短语 | `QuickPhrasesPage` | 预设短语 | ❓ |
| 网络代理 | `NetworkProxyPage` | 代理 | ❓ |
| 数据备份 | `BackupPage` | 备份/恢复 | ❓ |
| 存储空间 | `StorageSpacePage` | 占用清理 | ❓ |
| 统计 | `StatsPage` | 用量统计 | ❓ |
| 日志 | `LogViewerPage` | 调试日志 | ❓ |
| 关于 | `AboutUsPage` | 版本/关于 | ❓ |
| 爸爸卡片 | `DaddySettingsPage` | 爸爸的魂/名字/头像/记忆/iPhone联动/**心跳面板** | ❓（已知含心跳面板） |
| CC 爸爸 | `CcBridgePage` | CC 桥通道配置 | ❓ |

---

## 逐页明细

### 偏好设置（DisplaySettingsPage）✅ 顶层已审（2026-06-23）

> 文件：`lib/features/settings/pages/display_settings_page.dart`。这是个**中转页**：上半是进二级页的入口，下半是直接的外观设置。

| 条目 | 类型 | 作用 | 我们这套（iPhone） |
|---|---|---|---|
| 语言 | 选择 | App 界面语言 | ✅ |
| 聊天项显示 | →二级页 | 见下，已审满 | ✅ |
| 渲染设置 | →二级页 | Markdown/LaTeX/代码块 | ❓ 待审 |
| 行为与启动 | →二级页 | 思维链折叠/工具结果/新会话行为等 | ✅ 已审（CC 端几乎全不参与）↓ |
| 触感设置 | →二级页 | 振动反馈强度（`HapticsSettingsPage`） | ✅ |
| Android 后台聊天 | 入口 | — | 🖥️ **你 iPhone 上不显示**（`if(Platform.isAndroid)`） |
| iOS 后台生成 | 开关 | App 切后台时爸爸**是否继续生成回复** | ✅ 关键，按需开 |
| 聊天消息背景 | 选择 | 消息气泡背景样式 | ✅ |
| 聊天气泡形状 | 选择 | 圆角/直角/标准 | ✅ |
| 按钮形状 | 选择 | 全局按钮形状 | ✅ |
| 气泡不透明度 | 滑杆 | 气泡透明度（配背景图更明显） | ✅ |
| 背景变暗 | 滑杆 | 聊天背景图压暗程度 | ✅（需先设了聊天背景图才看得到） |
| 应用字体 | 选择 | 全局字体 | ✅ |
| 代码字体 | 选择 | 代码块等宽字体 | ✅ |
| 聊天字号 | 滑杆 | 聊天文字大小 | ✅ |
| 自动滚动 | 开关+滑杆 | 生成时自动滚到底 + 空闲秒数 | ✅ |
| 聊天背景遮罩 | 滑杆 | 背景图遮罩强度 | ✅（需先设背景图） |
| 输入框背景不透明度 | 滑杆 | 输入框背景透明度（明/暗各一） | ✅ |

#### 偏好设置 › 聊天项显示 ✅ 已审（2026-06-23）

> 渲染在 `chat_message_widget.dart` / `message_list_view.dart`。**CC 端复用同一组件但写死了几个参数**（`cc_chat_page.dart`：`showModelIcon/showTokenStats/showActions=false`、`showUserAvatar` 未传走默认 true、助手名/头像跟 CC 身份走）；组件内部直接读全局设置的项（用户名称/时间戳/模型名称/模型时间戳/供应商）CC 端也跟着开关走。

| 开关 | 作用 | API端 | CC端 |
|---|---|---|---|
| 显示用户头像 | 你消息旁的头像 | ✅ | ❌ 写死恒显示 |
| 显示用户名称 | 你气泡上方的名字 | ✅ | ✅ |
| 显示用户时间戳 | 你消息的时间 | ✅ | ✅ |
| 显示用户消息操作按钮 | 你消息下的复制/编辑/重发 | ✅ | ❌ CC 写死 `showActions:false` |
| 聊天列表模型图标 | 用模型图标当对方头像 | ✅（开了下条则让位给助手头像） | ❌ CC 写死 false |
| 聊天标题栏显示助手头像 | 标题栏/消息头用助手头像 | ✅ | ⚠️ CC 不受此开关控；头像**共用爸爸助手头像**，名字优先用 CC 名、没设才退回爸爸名 |
| 显示模型名称 | 消息头那行名字 | ✅ 显示爸爸名（见改动记录 06-23） | ✅ 显示 CC 名 |
| 显示模型时间戳 | 对方消息的时间 | ✅ | ✅ |
| 模型名称后显示供应商 | 名字后接「\| 供应商」 | ⚠️ 空挡（头部显示名字非型号） | ⚠️ 空挡 |
| 显示 Token 和上下文统计 | 工具条里的 token 计数 | ✅ | ❌ CC 写死 false |

#### 偏好设置 › 渲染设置 ✅ 已审（2026-06-23）

> 全部在共享渲染代码里直接读全局设置（`markdown_with_highlight.dart` / `chat_message_widget.dart`），**API 与 CC 两端都生效**。管「消息文字按格式排版 vs 纯文本直出」。

| 开关 | 作用 | 两端 |
|---|---|---|
| 启用 $...$ 渲染 | 把 `$...$` 当行内数学公式排版（`$x^2$`→x²），关＝原样美元符号 | ✅ API+CC |
| 启用数学公式渲染 | 数学公式(LaTeX)总开关，`$$...$$` 整行公式 | ✅ API+CC |
| 用户消息 Markdown 渲染 | 你发的消息是否按 Markdown 显示 | ✅ API+CC |
| 思维链 Markdown 渲染 | 爸爸思考过程那块的排版 | ✅ API+CC |
| 助手消息 Markdown 渲染 | 爸爸回复正文的排版（影响最大） | ✅ API+CC |
| 自动折叠代码块 | 代码块自动收起，点开才看；展开后有子项「超过几行才折叠」 | ✅ API+CC（日常无代码基本无感） |
| 移动端代码块自动换行 | 长代码自动折行 vs 横滑；**仅当「自动折叠代码块」开启才显示** | ✅ API+CC |

> 日常聊天真正有用：3/4/5（Markdown 排版）；1/2/6/7 是数学/代码场景，基本用不到。默认 1–5 开、6–7 关即合理。

#### 偏好设置 › 行为与启动 ✅ 已审（2026-06-23）

> `display_settings_page.dart` 第 2437 行起。**整页基本是给「主聊天(API/助手端) + App 界面/侧栏/会话管理」用的；CC 端是独立桥接页，几乎全不参与**（CC 只有思考块和自己的输入框，且都用固定逻辑不读这页设置）。

| 项 | 作用 | API端 | CC端 |
|---|---|---|---|
| 自动折叠思考 | 思考块默认收起 | ✅ | ⚠️ CC 用本地折叠状态，不读 |
| 折叠思考步骤 | 多步思考(>2)时折叠 | ✅ | ❌ CC 思考是整段 |
| 显示工具结果摘要 | 工具调用显示摘要 | ⚠️ 仅带工具块时显形，日常少见 | ❌ CC 工具/任务走居中系统提示 |
| 点击建议时仅填入输入框 | 点建议=填入非直发 | ✅ | ❌ CC 无建议 |
| 重新生成时删除下面的消息 | 重生成删其后消息 | ✅ | ❌ CC 不能重生成 |
| 重新生成前弹出确认 | 重生成前确认 | ✅ | ❌ |
| 显示更新 | 检查 App 新版本 | 🔵 全 App，与聊天无关 | 🔵 |
| 消息导航按钮 | 聊天上/下跳转 | ✅ | ❌ |
| 显示对话列表日期 | 会话列表日期 | ✅ | ❌ 不在会话列表 |
| 启用图片裁剪 | 选图后可裁剪 | ✅ | ⚠️ 基本主聊天用 |
| 点选助手/话题时不关侧栏、关侧栏不折叠助手列表 | 主页侧栏行为 | ✅ | ❌ CC 无侧栏 |
| 切换助手/删除后/启动时 新建对话 | 会话管理 | ✅ | ❌ CC 无对话概念 |
| 回车键发送消息 | 回车=发送 | ✅ 主输入框 | ⚠️ CC 输入框回车固定发送，不读 |

> 🔵=全 App 级、与"哪个爸爸"无关。**给小猫的实话**：这页对 CC 端几乎全无效；改了主要影响 API/助手端那边的交互。

### 中转站（原"供应商"，ProvidersPage）✅ 已审（2026-06-24）

> 大前提：接 API 命根子，全作用 **API 端**；CC 端走家里的桥、不碰 App 的中转站/模型。

| 项 | 作用 | API端 | CC端 |
|---|---|---|---|
| 中转站列表（增删/启用/Key/baseURL/模型/测试/导入/多选） | 配 API 端点与密钥 | ✅ 爸爸经网关时拿你选的中转站当**上游中继**出文；普通助手直连 | ❌ |

> 记忆在网关、不在中转站。**在爸爸本人身上换中转站**他照样有记忆；新建普通助手测＝白板无记忆（见 DaddyGatewayRoute）。

### 默认模型（DefaultModelPage）✅ 已审（2026-06-24）

| 项 | 作用 | API端 | CC端 |
|---|---|---|---|
| 对话模型 | 默认对话模型 | ✅ 普通会话默认（爸爸用其助手里配的模型经网关） | ❌ |
| 标题/总结模型 | 自动给会话起标题 | ✅ | ❌ |
| OCR 模型 | 图片转文字（需支持图片输入的模型） | ✅ 发图时 | ❌ |
| 爸爸·归档/前情/压缩模型（原"整理记忆/前情提要/压缩"三槽，2026-06-24 合并） | 选老家中转站，控网关 `summary` 角色（归档/前情/压缩共用一个模型）；留空=跟随聊天中转站 | ✅ 真正生效（直接改爸爸服务器侧的 summary 模型） | ❌ |
| 爸爸·日记底稿（diary_brief） | 开关日记底稿 + 选其模型（控网关 `diary_brief` 角色）；留空=跟随聊天中转站 | ✅ 真正生效 | ❌ |
| Telegram 设置（2026-06-29 新增） | TG 这条路的中转站+模型（控网关 `tg` 角色）+ TG 专属 profile（系统提示，`tg_profile`）；模型行留空=跟随聊天中转站 | ✅ 真正生效（只改接 API 的 TG，不动 CC 端 bot） | ❌ |

### 爸爸的搜索（DaddySearchPage）✅ 已审（2026-06-24）

> 网关后端配置（存 `web_search_cfg`，`_effective_web_search_cfg()` 生效）。控爸爸**经网关时**的联网搜索。

| 项 | 作用 | API端 | CC端 |
|---|---|---|---|
| 启用联网搜索 | 开＝爸爸挂上 `web_search`/`web_read` 工具能查网页；关＝连工具都看不到 | ✅ | ❌ CC 自带联网工具，不读此设置 |
| 结果数(1–10) | 每次搜返回几条 | ✅ | ❌ |
| 超时(3–30s) | 单次搜索超时 | ✅ | ❌ |

### 爸爸的内置工具（DaddyToolsPage）✅ 已审（2026-06-24）

> **只读**清单（无开关；服务器 `/api/home/daddy-tools` 仅 GET）。列爸爸经网关能调的后台工具 + 每个此刻状态；名单取自 `_chat_tool_schemas()`（爸爸真拿到的那套）。

| 状态 | 含义 |
|---|---|
| live | 此刻在/常驻 |
| offline | 此刻断了（被关或不可达） |
| ondemand | 按需/状态难判 |

- 状态联动（开关在别处，这页只显示）：联网类跟「爸爸的搜索」开关；推送(push)看手机有无订阅 Web Push / 配 Bark；音乐看网易云桥可达；记忆等本地逻辑常驻 live。
- API端：✅ 准确反映 API 端爸爸的工具与可用性。CC端：❌ 这是网关工具，不代表 CC 爸爸（家里 Claude Code 自带另一套）。

### MCP（McpPage）⚠️ 已审（2026-06-24）——对我们基本是死设置

> 铁证：网关 `/v1/chat/completions`（server.py:11310）里 `tools = _chat_tool_schemas()`——**完全无视客户端传来的 tools**，只用网关自己那套。App 发请求时 `tools: ctx.toolDefs`（含 MCP）虽随 daddy 网关请求一起发出，但被网关丢弃。

| 作用对象 | App 配的 MCP | 生效？ |
|---|---|---|
| 爸爸（走网关） | MCP 工具 | ❌ 白配，网关丢弃客户端 tools，爸爸只拿网关自己的工具 |
| 普通助手（直连中转站，无 `[[ourhome]]` 标记） | MCP 工具 | ✅ 能用（App 自己执行 MCP 调用） |
| CC 爸爸 | App 的 MCP | ❌ CC 是家里 Claude Code，自带自己的 MCP，不读 App 这套 |

> 给小猫：日常就爸爸(网关)+CC 两条路，都不吃 App 的 MCP，所以这页对你**死的**——只有新建"直连普通助手"才有意义。

### 其余顶层页 ❓ 待审

## 2026-06-30 · 默认模型页新增「生图模型」卡片（服务器配置卡）

- 位置：`默认模型` 页（`lib/features/model/pages/default_model_page.dart`），排在 TG 卡之后，与归档/日记底稿/TG 三张网关卡同类。
- 作用：配置网关 `draw` 工具的出图后端（protocol gemini/openai + base + model + key + size）。**数据存网关** `chat_store["image_model"]`（连 `/api/home/image-model`），不是本地 SettingsProvider；改完即时生效、网关聊天 + CC 端共用。
- 含「测试出图」按钮：调 `/api/gen-selftest`，把原始 result（成功 `![..](url)` / 失败「（画不出来：…）」）弹窗显示，便于定位 key/模型问题。
- 文案沿用本页同类网关卡的 `isZh ? 中:英` 内联写法（非 ARB key）——与 `_DaddyGatewayModelCard`/`_TgGatewayCard` 一致，且避开本环境无 Flutter SDK、`gen-l10n` 跑不了的坑。
- ⚠️ 本环境无 Flutter SDK，未跑 analyze/format/build；CI 的 `flutter build ios` 是第一道真编译。

## 2026-06-30 · 远程出图自动存本地（配合服务器限额删旧）

- `MarkdownMediaSanitizer.localizeRemoteImages()`：消息定稿时（`chat_actions.dart` `_finishStreaming`，紧跟 `replaceInlineBase64Images` 之后）把消息里**我们 `/api/gen` 的远程图**下载到本地图片目录、链接改本地路径——永久留手机、不再每次缓冲，服务器删旧也不怕。
- 只搬 `/api/gen/` 自家图（正则 `_remoteGenImgRe` 限定 host 路径），不动外部 http 图，避免误下载任意网图。同 URL 同本地文件（hash 命名），下载失败保留原远程链接、不丢。本地路径渲染走 `markdown_with_highlight` 的 `FileImage`。
- 配套：网关 `OMBRE_GEN_KEEP`（默认 30）只留最近 N 张。**先装这版（图存本地）再让服务器删旧才安全。**
- ⚠️ 无 Flutter SDK，未跑 analyze/build；CI flutter build ios 是第一道真编译。

## 2026-06-30 · 撤回「远程图存本地」(+83 的 localizeRemoteImages)
- 症状：+83 上线后，画的图有时显示成原文 `![..](/var/mobile/.../img_xxx.png)`、不渲染。
- 根因：localize 在消息定稿(_finishStreaming)时把远程图链改成**本地长路径**，长度变了，但气泡分条用的 contentSplitOffsets 是按定稿前(远程短链)算的→偏移失配→把 URL 从中间切到两个气泡→markdown 失效成原文。base64 那条没事是因为它在流式期就跑、offset 按本地化后内容算。
- 处置：**revert** localizeRemoteImages（删方法/正则/http import + 去掉 chat_actions 调用），图回到远程链接渲染（稳）。本地存储以后重做：要么放流式期跑(随 base64)，要么 localize 后重算 offset。先求稳。
- 无 Flutter SDK，未跑 analyze/build；CI 是第一道真编译。

## 2026-07-03 · 外观·我们的家 新增「门厅桌宠」开关（配合桌宠 Phase 2）

- 位置：`外观 · 我们的家`（`our_appearance_page.dart`），主页背景分组之后新增「门厅桌宠」分组：小螃蟹 Clawd / 小海豹 Cing 两行（动图缩略 + IosSwitch）。
- 作用：显示/隐藏门厅的浮动桌宠。开关值＝`!hidden`。桌宠在门厅**长按**弹调节面板（形态钉选或随机 / 大小滑杆 0.6–1.8 / 隐藏），**拖动**换位置；面板里点了隐藏就回这里找回——这两个入口是同一份配置。
- 数据：本地 `SettingsProvider`，键 `still_pet_clawd_v1` / `still_pet_seal_v1`（JSON：hidden/scale/posX/posY/emote；posX/posY 归一化 0..1，-1=没挪过用默认位；emote 空串=每次进门随机）。纯客户端外观，与网关无关。
- 文案照房间规矩内联双语（本页整页如此）。
- ⚠️ 无 Flutter SDK，未跑 analyze/format/build；CI flutter build ios 是第一道真编译。

## 2026-07-03 · 「门厅桌宠」升级为「桌宠」（全屋悬浮，+106）

- 分组名「门厅桌宠」→「桌宠」，副题改「全屋悬浮可拖动」；小螃蟹显示名 **Clawd → Llawd**（姓氏交换）。开关语义不变（`!hidden`），存储键不变（`still_pet_*_v1`，老配置无缝沿用）。
- 桌宠实现从 still_rooms_page 页内搬到 `lib/features/home/widgets/floating_pets.dart`，挂 **MaterialApp.builder**（仅 Android/iOS）——聊天窗/终端/设置所有路由之上悬浮；长按面板经新加的全局 `rootNavigatorKey`（MaterialApp.navigatorKey）弹出。
- Llawd 表情池 +1：pet-bunny.gif（兔男郎）；调教室门图标换 icon-locked.png（同素材首帧）。
- ⚠️ 无 Flutter SDK，未跑 analyze/format/build；CI flutter build ios 是第一道真编译。
