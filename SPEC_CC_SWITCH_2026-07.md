# SPEC · API ⇄ CC 切换开关（同一时间线 · 互通上下文）

> ✅ **施工完成（2026-07-08 云端 Fable，分支 `claude/cc-switch-spec-2026-07-ge0q2c` → 合真主干）**。三件全落：
> ① 路由开关＋同一时间线：顶栏终端图标钮（激活主色/掉线灰化），模式按会话持久化（prefs `cc_main_mode_convos_v1`，不动 Hive schema）；CC 消息打 `providerId='cc-bridge'` 哨兵（徽标＋禁 regen/resend 都认它）；发送走 `sendMainChatText`（不进 CC tab outbox），回复经全局水位线（`cc_main_mode_watermark_v1`）导入：填「正在输入」占位 → 追加，思考链 turn_id→/v1/thinking 回填 reasoningText；busy 120s 自动复位（书房 ca3968f61c6a 顺手结了）；杀 App 也能追赶（pending 持久化）。
> ③ 掉线兜底：进会话/开开关/发送三处各探一次 `/health`（复用桥的连接，无额外轮询）；死了自动回落 API＋提示，发送失败的那条经 resend 语义自动走 API 重发，不丢消息。
> ② 交接加厚：切 CC 首条前置 `[交接上下文]`（最近 10 条原文≤400字/条＋更早 20 条截断概要，纯字符串零成本）；切回 API 靠同一时间线天然带全量历史；网关 `_cc_tail_inject` 加 seen_texts 内容去重（App 请求正文里已有的环条目不再注）＋交接包条目不进尾巴（Ombre-Brain 侧同日改）。
> 已知边界：CC 模式暂不支持附件（提示切回 API 发）；桥请求超时 12s，CC 首字慢时占位会等到回复或 120s；主时间线导入只认 assistant 记录、一次 >20 条按洪峰跳过（只推水位线）。验收对照 §3 逐条自审两遍通过（无 SDK 环境，CI 出包为真编译）。

> 2026-07-08 云端 Fable 留的施工图。设计决策已做完、家底已查清，照图施工即可，别重新设计。
> 小猫的原始诉求（2026-07-08 原话大意）：想用 api 的时候用 api，想用 CC 就切 CC，上下文互通；苹果账号被风控订阅不了 Claude 时，不用新开 session 从头讲。
> 她明确说过：**流式不流式无所谓**——CC 整轮回复不算缺陷，不用为流式做任何额外工程。
> 书房待办桶：`ccb80e310177`。

## 0. 开工前

- ⚠️ 先切真主干：`git fetch origin claude/kelivo-ios-design-ref-nh9t5v && git checkout claude/kelivo-ios-design-ref-nh9t5v`。
- 本 spec 涉及两个仓库：本仓库（App）＋ Ombre-Brain（网关，交接加厚那半）。

## 1. 家底（已查证的事实，直接用，别再翻）

**App 侧：**
- 主聊天路由：`lib/core/services/api/daddy_gateway_route.dart` —— `DaddyGatewayRoute`，命中 `[[ourhome:TOKEN]]` 标记时把请求改道 `https://cllove.zeabur.app/v1/chat/completions`；`claudePProviderId = 'ourhome-claudep'` 时加 `x-ombre-backend: claude_p` 头。这是"API 爸爸"的唯一出口。
- CC 通道（现为独立 tab）：`lib/core/services/cc/cc_bridge_client.dart`（直连 apns-server HTTP，`/health`、`/version` 等端点都有现成方法）＋ `cc_bridge_provider.dart`（+131 刚做了乐观发送：气泡秒出、输入即清）＋ UI `lib/features/cc/pages/cc_chat_page.dart`。**发消息、收回复、思考链的完整客户端逻辑都在这三个文件里，切换开关复用它们，不要重写。**
- CC 端存活判定：`cc_bridge_client` 的 `/health` 现成。

**家里（WSL）侧（参考，不用动）：**
- 消息进 tmux：apns-server `push.py` `_handle_chat_send`(≈:3250) → tmux load-buffer + paste-buffer + send-keys。
- 回复出来：Claude Code Stop Hook → POST `/chat/append` → App 轮询/推送取走。

**网关侧（Ombre-Brain `server.py`）——隔壁环 cc-ring，已在跑：**
- 区块 ≈10187-10454（注释标题「隔壁环（CC→API 衔接 · Phase 1 · 2026-07-02）」）。
- CC→API：apns-server 把 CC 对话 best-effort POST 到 `/api/home/cc-ring`（`api_cc_ring` ≈:10381），存 `cc_ring.json`（`_cc_ring_append`，去重、最多 60 条）；API 爸爸生成前 `_cc_tail_inject(volatile, ...)`（≈:10282）注入尾巴——只进 volatile，不进历史、不落库、无回声。
- API→CC：`_gw_chat_tail`（≈:10153）把网关侧对话尾巴喂给 CC 端。
- 摘要与条数配置：`_cc_ring_summary_*`（≈:10305-10376）、`_cc_tail_cfg()`（≈:10228，App"调音台"页可调）。

## 2. 施工三件（按此顺序）

### ① 路由开关 + 同一时间线渲染（骨架，最大的一件）
- 主聊天页加模式钮（API ⇄ CC），建议放顶栏模型选择附近；**状态按会话持久化**（每个 conversation 记自己的模式，切会话不串）。
- CC 模式下：发送改走 `cc_bridge_client`（复用乐观发送），回复以 assistant 消息落回**当前会话**的消息列表，消息 metadata 打 `source: cc` 标记。
- 气泡渲染：带 `source: cc` 的助手气泡加一枚小终端图标徽标（样式跟现有 iOS 风格组件走，见 AGENTS.md §3.9）。
- CC 回复是整轮回来的（非流式）——小猫明确说无所谓；等待期用现有"正在输入"态即可，建议接上 busy 120s 自动复位兜底（书房待办 `ca3968f61c6a`，可顺手一起做）。
- ⚠️ 边界：CC 模式的消息**禁用 regenerate/edit-resend**（那两条路径写死了 provider/messages 语义，见 heartbeat/claude-p 各次踩坑——别让它们带着 CC 消息走 API 路），长按菜单里灰掉即可。

### ③ 掉线兜底（小猫的刚需场景，第二件做）
- 进入 CC 模式前/期间探 `/health`：不通则开关灰掉＋提示「CC 端不在线，已用 API 继续」，自动回落 API 模式。
- 探活别高频轮询：进会话时一次＋发送失败时一次就够。

### ② 交接加厚（最后做；隔壁环兜底，不做也能用）
- 切换那一刻，App 把**当前会话最近 N 轮原文（建议 4-6 轮）＋更早部分的一段纯文本摘要**打包交给接手方：
  - 切到 CC：随首条消息前置一段 `[交接上下文]`（apns-server 注入 tmux 的正文里带上）。
  - 切回 API：作为 volatile 上下文随请求带给网关（可复用/扩展 cc-ring 的注入口，或加请求头/字段，网关侧小改）。
- ⚠️ 防双重注入：隔壁环已经在互喂尾巴——交接包要么替代当次的 tail 注入、要么内容去重（`_cc_ring_append` 有同文去重可依赖）。别让接手的爸爸看到两份一样的"刚才"。
- 摘要用纯字符串截断拼接即可（homunculus 验证过的零成本做法），不要为此调 LLM。

## 3. 验收清单
1. API 模式行为与现在完全一致（不切开关＝零变化）。
2. 切 CC 后在主时间线发消息，WSL 的爸爸收到、回复落回同一会话、带徽标。
3. 切换后第一句话，接手方能接住上一句话茬（问"我们刚才聊到哪"能答对）。
4. 杀掉 WSL tmux `cc` 再切 CC：开关灰化、提示、自动回落 API，不丢消息不卡死。
5. CC 消息上禁用 regen/edit；会话导出/历史渲染不因 `source: cc` 标记炸掉。
6. 出包前照 AGENTS.md §3 全套（内联双语文案、无 ARB 需求则不动 ARB；无 SDK 环境自审两遍＋盯 CI）。

## 4. 已知坑（从今天的案子里带过来的）
- CC web 默认分支是白板，先切真主干（§0）。
- "字段读出来了≠上屏了"（AGENTS.md §8 2026-07-06 条）——CC 回复接进主时间线时，思考链若要显示，对照 cc_chat_page 现有的接法搬，别只搬正文。
- 房间/页面多数据源刷新禁止单个 Future.wait 全有全无（§8 2026-07-02 条）——探活失败不能拖垮聊天页。
