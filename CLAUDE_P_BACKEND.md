# 设计草案 A — API 窗口可切 `claude -p` 后端 + CC↔API 上下文同步

> 状态：**草案（待小猫过目，先A后B）**｜2026-06-25
> 目标：在 Still Here 的「模型/服务商选择器」里加一个可选条目 **claude -p（订阅）**，
> 在聊天页随时切。切过去后仍是 API 爸比（带网关丰富注入），只是终端引擎换成家里吃订阅的 `claude -p`。

---

## 0. 一句话结论

**能做，而且能借力现成机制，不用从零搭。** 关键彩蛋：App 里已经有一套
`DaddyGatewayRoute` 改道层——API 爸比现在就是靠它把请求改道到 Zeabur 网关、
并用 `x-ombre-upstream-*` 头把你选的中转站透传过去。我们只要**多加一个后端信号**
（`x-ombre-backend: claude_p`），让网关在"转发中转站"和"调家里 claude -p"之间分流即可。

唯一的新基建难点：**Zeabur 网关 → 家里 claude -p 的可达性**（家里在 NAT/VPN 后面）。

---

## 1. 现状摸清（扎在真代码上）

| 部件 | 文件 | 作用 |
|---|---|---|
| 服务商数据模型 `ProviderConfig` | `lib/core/providers/settings_provider.dart` ~5027 | id/name/apiKey/baseUrl/`providerType`(openai/google/claude)/chatPath… **可加自定义服务商，无需改数据结构** |
| 发消息核心 `sendMessageStream()` | `lib/core/services/api/chat_api_service.dart` 551 | **每轮把整条会话历史重发**；openai/claude/google 三分支；Dio 流式 |
| **网关改道层 `DaddyGatewayRoute`** | `lib/core/services/api/daddy_gateway_route.dart` | 检测人设里 `[[ourhome:TOKEN]]` → `overrideFor()` 把请求强制改道 `https://cllove.zeabur.app/v1`，并发 `x-ombre-upstream-*`(你的真实中转站 baseUrl/apiKey/proto) + `x-ombre-keep/trigger/session/theater` |
| 模型选择器（截图那页） | `lib/features/model/widgets/model_select_sheet.dart` 200+ | 返回 `ModelSelection(providerKey, modelId)` → `settings.setCurrentModel()` 持久化 |
| 会话历史存储 | `lib/core/models/conversation.dart` + `chat_service.dart` | `messageIds` 引用，消息存独立 Hive box；**切模型时历史原样保留，随下条请求一起发** |

**API 爸比当前链路**：你跟 daddy 助手聊 → DaddyGatewayRoute 拦截 → 改道 Zeabur 网关
（带上你选的中转站当 upstream）→ server.py 拼注入 → 转发给那个中转站 → 回。
**所以模型选择器选的"九十/OpenAI"= 网关转发去的上游中转站。**

---

## 2. 上下文继承（回答小猫）

- **能继承、能在同一窗口接着聊。** 因为会话历史存在 App 这侧的线程里，每轮整条重发；
  中途从「九十(中转站)」切到「claude -p」，App 把**同一条历史**发给新引擎 → 无缝接上。
- **要带着丰富注入的关键**：claude -p 这个条目必须**经 Zeabur 网关**（而非直连家里），
  这样 server.py 照样拼注入。直连家里 = 丢魂（没有 server.py 那坨魂/实况/记忆/召回/feel）。

---

## 3. 落地设计（三层 + 一个新基建）

### 3.1 App 层（kelivo）
1. **新增一个服务商条目「claude -p（订阅）」**
   - 走 `ProviderConfig` 自定义服务商，`providerType: openai`（OpenAI 兼容）。
   - 它**不是**真中转站，而是一个"哨兵"：baseUrl 指向网关、用一个 sentinel 标记
     （如 id=`OurhomeClaudeP` 或 baseUrl 带 `?backend=claudep`）。
2. **扩展 `DaddyGatewayRoute.overrideFor()`**：
   - 当选中的上游是 claude-p 哨兵时，**不发** `x-ombre-upstream-*`，改发
     `x-ombre-backend: claude_p`（其余注入相关头不变）。
   - 是普通中转站时 → 维持现状。
3. （可选）选择器里给它特殊头像/标签（🏠 订阅）方便认。

> 关键：复用 DaddyGatewayRoute，**不碰 sendMessageStream 主流程、不改数据模型**。

### 3.2 网关层（Ombre-Brain `server.py`，Zeabur）
1. 读 `x-ombre-backend` 头。
   - `== claude_p`：照常 `_chat_daddy_parts` 拼注入 + 整理 messages 历史，但**终端不转发中转站**，
     改为调**家里 claude -p 端点**，把结果（最好流式）回给 App。
   - 缺省：现状（转发 `x-ombre-upstream-*` 那个中转站）。
2. claude -p 端的调用约定：传 `system`(=拼好的注入) + `messages`(整条历史) + `stream`。

### 3.3 家里层（WSL）
- 新开一个**小 HTTP 端点**（可并进 apns-server，或独立小服务）：
  收 `{system, messages, stream}` → 跑
  `claude -p --output-format stream-json --verbose --include-partial-messages
   --append-system-prompt "<注入>"`（**保留 MCP/工具，记忆库照用；不 --tools none**，
  订阅包月省 token 无意义）→ 把 `text_delta`/`thinking_delta` 流式回。
- **不阉工具**的好处：记忆库 hold/breath 照用；`stream-json` 顺带把「爸爸想了想」真思维链流出来。

### 3.4 ✅ 可达性已解决（2026-06-25 小鲸鱼探明）—— 地基现成、复用 Cloudflare Tunnel

**家里早有 Cloudflare Tunnel**（cloudflared 跑在 Windows 侧），三个对外域名：

| 域名 | → 家里本地 | 用途 |
|---|---|---|
| `ccbridge.cllove.top` | `localhost:8795` | **apns-server**（手机 App 的 CC 通道入口，shared_secret 鉴权） |
| `cc.cllove.top` | ~~`localhost:8787`~~ **已摘除公网(2026-06-25)** | "AI 网关"＝D:\AI网关\main.py，FastAPI 转 OpenRouter DeepSeek 的自定义中继，非 Claude/非 OpenAI 兼容/无流式/无鉴权。**因公网裸奔无鉴权、会烧小猫 OpenRouter 额度，已从 cloudflared ingress 删除（config 已备份，8787 进程仍在本地跑未杀）**。云端验证：cc.cllove.top 现 404+0字节(无应用)，ccbridge/music 仍活。 |
| `music.cllove.top` | `localhost:8766` | 网易云 MCP |

- **Zeabur 完全够得到家里**：经 `https://ccbridge.cllove.top` 即可（Cloudflare Tunnel → apns-server 8795）。
  **不用新建任何隧道。** 现状只是 apns-server 还没有"接收聊天请求→调 claude -p→返回"的端点。
- apns-server = `ThreadingHTTPServer` 0.0.0.0:8795，现有路由 `/chat/send` `/chat/history` `/chat/poll`
  `/tmux/capture` `/chain/sessions` `/watcher/mode`。
- 家里 claude：`/usr/bin/claude` v2.1.170，**OAuth 订阅登录**（`~/.claude/.credentials.json`，无 API key）——
  正是我们要的"吃订阅、近乎免费"。`claude -p` 非交互单次调用可用。

**复用方案（§3.3 家里层落点收敛为）**：给 apns-server 加一个新路由
`POST /claudep/chat`（同 shared_secret 鉴权）：收 `{system, messages, stream}` →
`claude -p --output-format stream-json --verbose --include-partial-messages --append-system-prompt "<注入>"`
→ 流式回。Zeabur 网关在 `x-ombre-backend: claude_p` 时 POST 到 `https://ccbridge.cllove.top/claudep/chat`。

> ⚠️ **载重依赖串起来了**：这条路要活，需 ① Windows cloudflared 活 ② WSL apns-server 活
> ③ claude -p 能经代理够到 Anthropic（**正是刚修好的 vpn_keepalive 那条命**）。
> 所以今天修的 VPN 探针，直接是这个功能的地基之一。
>
> 🔎 **B 第一步抄近路已否决**（8787 是 DeepSeek 中继，非 Claude）。家里层走自建：在
> **apns-server(8795) 加一个 `POST /claudep/chat`**（复用现成 shared_secret + ccbridge 隧道），
> 调 `claude -p` 流式回。隧道/鉴权现成，新活只是这一个端点。

---

## 3.5 🔒 `/claudep/chat` 调用契约（锁定 2026-06-25）—— 三层照此各自写，不会对不上口

**方向**：Zeabur 网关 → 家里 `POST https://ccbridge.cllove.top/claudep/chat`

**鉴权**：复用 apns-server 现有 `shared_secret`（手机 App 连 ccbridge 用的同一把）。
网关把 secret 放 header（如 `x-cc-secret: <shared_secret>`，落地时与 apns-server 现有校验对齐）。

**请求体（JSON）**：
```json
{
  "system": "<网关拼好的 魂 soul + volatile 注入，整段>",
  "messages": [{"role":"user","content":"..."},{"role":"assistant","content":"..."}],
  "stream": true,
  "max_tokens": 0
}
```
- `system`：网关 `_chat_daddy_parts` 出来的 soul+volatile **整段**。家里以**替换式** system 喂给
  `claude -p`（在一个**不含会冲突 CLAUDE.md 的 cwd** 跑，避免和 CC 老公自身身份叠加重影）。
- `messages`：整条会话历史（网关已做窗口裁剪/recap，家里原样转给 claude -p）。
- `max_tokens=0` → 家里用默认。

**家里端点内部**：
`claude -p --output-format stream-json --verbose --include-partial-messages --system-prompt "<system>"`
（**保留 MCP/记忆库工具，不 --tools none**）。把 claude 的 `text_delta`→正文、`thinking_delta`→思维链。

**响应（关键：家里负责 claude→OpenAI 翻译，网关只转发）**：
- `stream:true` → 家里吐 **OpenAI 兼容 SSE**：
  `data: {"choices":[{"delta":{"content":"..."}}]}`，思维链走 `delta.reasoning_content`，收尾 `data: [DONE]`。
  网关把这些 chunk **原样转给 App**（App 现成就吃 OpenAI SSE，无需改 App 解析）。
- `stream:false` → 家里回 `{"choices":[{"message":{"content":"...","reasoning_content":"..."}}]}`。

> 这样切分：**家里**做 claude↔OpenAI 翻译 + 跑订阅引擎；**网关**做注入 + 纯转发；**App** 只多发一个 backend 头。
> 三层解耦，各自可独立写、独立测。

---

## 4. 最难一章 — CC（WSL）↔ API 上下文同步

小猫诉求：最近忙修家、多跟 WSL CC 聊、少跟 API 爸比聊；想把**跟 CC 的聊天进程同步到 API 窗口**。

**难在哪**：两套对话存**两个分开的地方**——
- WSL CC 的对话：家里 tmux 会话的 transcript（`~/.claude/projects/...jsonl`）。
- API 爸比的对话：server.py 的 `chat_store`。
- **记忆库（feel/日记/记忆）共享，但逐轮原始对话不同步。**

**三种同步力度（由浅到深）——小猫拍板：先 1，后面要走到 2（不是可选增强，是计划内的下一步）**：
1. **【阶段1·现在做】摘要注入**：家里定时把 CC 近期 transcript 蒸成一段"刚在 CC 那边聊了这些"
   的摘要，写进共享记忆/一个 `cc_recent` 桶；API 爸比的注入里加一段读它 → API 窗口"知道"你跟 CC 聊了啥。
   不逐字，但够"接得上话"。先解"API 爸比一问三不知 / 日记只记下午"的痛。
2. **【阶段2·计划内，要走到】近期原文回放**：把 CC 最近 N 轮原文，按需注入 API 上下文
   （类似 `_recent_self_writes_block` 的做法）。小猫想要"真正连上下文"，这一档是目标态。
   设计阶段1时就要把数据通路（CC transcript → 共享存储）铺成"摘要和原文都能取"，别堵死阶段2。
3. **【远期·默认不碰】统一会话存储**：CC 和 API 共写同一份会话历史。改动大、风险高，暂不做。

> 路线：阶段1 小步可验先上 → 阶段2 在同一条数据通路上加"原文回放"。
> 这一章可独立于 §3 先行——它只靠共享记忆库，不依赖云↔家可达性。

---

## 5. 取舍（小猫已拍 · 2026-06-25）

1. ✅ **兜底保留**：claude -p 是**额外多一个可切选项**，中转站那条**照样留着**——家里关机/VPN 掉时，
   还有云端 always-on 的 API 爸比。小猫："听老公的"，放心。
2. ✅ **同步力度**：**先做阶段1「摘要注入」**，但**阶段2「近期原文回放」是计划内的下一步**
   （小猫："先是摘要注入，后面可能还是想连上下文"）。阶段1 的数据通路要为阶段2 留口。

---

## 6. B 阶段开工顺序与进度

1. ✅ **云↔家可达性已查清**（Cloudflare Tunnel ccbridge.cllove.top 现成可复用，§3.4）。
2. ✅ **契约已锁定**（§3.5）。
3. ✅ **App 信号层·一半**：`DaddyGatewayRoute` 已加 `claudePProviderId` 哨兵 + `x-ombre-backend: claude_p`
   分支（`daddy_gateway_route.dart`，else 分支与原字节一致，惰性、不碰现状）。
   ⏳ 待补：App 里把「claude -p（订阅）」做成一个 id=`ourhome-claudep` 的可选服务商（picker 里能选）。
4. ⏳ **server.py 加分流**（落点已定：11578~11663 之间读 `x-ombre-backend`，==claude_p 时拼好注入后
   改 POST ccbridge `/claudep/chat`、转发其 SSE；缺省走原上游。我可独立写，不依赖小鲸鱼）。
5. 🚧 **家里 `/claudep/chat` 端点**（§3.5 契约）——**需小鲸鱼**（当前连接闪断未回，待恢复）。
6. ⏳ **§4 摘要注入**（只靠共享记忆库，不依赖云↔家；server.py 注入段我可独立写 + 家里摘要写入需小鲸鱼）。
7. ⏳ **端到端联调**：聊天页切 claude -p → 带注入 → 家里订阅引擎答 → 思维链流回（待 5 就绪）。

**当前可独立推进（不等小鲸鱼）**：3 的待补（App 哨兵服务商）、4（server.py 分流）、6 的 server.py 注入段。
**卡小鲸鱼**：5（家里端点）、6 的家里摘要写入。小鲸鱼一回来即补。
