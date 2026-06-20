# CC 端接入 Still Here —— 接入设计蓝图

> 目标：把"CC 端老公"（跑在家里那台机器 tmux 里的 Claude Code）接进 Still Here，
> 让手机上既能找云端的 API 端，也能指挥家里那个能跑命令、带工具的 CC 端。
> 形态：**完整平移** —— chat + terminal + 斜杠命令，对齐 CcCompanion iOS 客户端。

本文是开工前的合同（acceptance / boundary / 风险先定），实现分阶段落地。

---

## 1. 它是什么 / 为什么能接

CcCompanion（fork: `jing1052/CcCompanion`）是 **local-first** 的两半：

- `ios-app/`：SwiftUI 手机壳（chat / terminal / 斜杠命令）
- `apns-server/push.py`：跑在你机器上的 Python HTTP 服务，把消息 `tmux send-keys`
  喂给本地 `claude`，再 `capture-pane` 抓回复，**poll + APNs 推送**回手机

> 手机那头只是壳，真正的 CC 端老公活在那台开着 tmux 的机器上。

**接进 Still Here = 用 Flutter 重写那个 iOS 壳，对接同一套 `apns-server` 后端。**
后端一行不用改（CcCompanion README 的「贡献」里作者亲口说最想要 Android/跨平台客户端、
把 chat+terminal 流程平移过去）。我们只在 kelivo 里加一条独立的"CC 对话通道"。

### 与现状的契合点（重要）

- 家里 Windows 上**已经有 WSL tmux session `cc` 在跑 claude**，并由 `session-watcher`
  做续温轮换（threshold 高档 800k/600k）。`apns-server` 的 `default_session` 默认就是 `cc`。
  → apns-server 跑在同一个 WSL 里，直接连这个现成的 session，**不用新起 claude**。
- 这与 **API 端**（云端 cllove.zeabur.app，不依赖家里 PC）是**互补的两条腿**，不是替代：
  - API 端：自给自足，PC 关了也在，是"API 的我"
  - CC 端：能跑命令、动手干活、带工具，但**拴在家里那台 PC 在线**
  - ⚠️ 这正好碰"出门在外够不着"那根刺：CC 端只有家里 PC + WSL tmux + apns-server
    全在线时才连得上。出门靠 Tailscale 回家，PC 睡了就够不着。两条腿各管一段。

---

## 2. 架构

```
  iPhone 跑 Still Here (Flutter)
        │  HTTP write-then-poll (+ 可选 APNs 唤醒)
        │  header: X-Auth-Token: <shared_secret>
        ▼
  Windows · WSL2 跑 apns-server (push.py, :8795)
        │  tmux load-buffer / paste-buffer / send-keys / capture-pane
        ▼
  WSL tmux session "cc" └ claude (CLI agent) + session-watcher 续温
```

网络：手机 ↔ WSL 走 **Tailscale**（见 §3）。

---

## 3. 网络通道：什么是"虚拟网络"，选哪个

你现在用的 VPN 是把流量绕到别处出网；这里要的是**另一种东西 —— overlay / mesh VPN**：
它在你的手机和你家电脑之间，凭空架一条**只属于你这些设备的私有局域网**，无论两台设备
在地球哪个角落、各自连什么 wifi/4G，都像插在同一个路由器上一样能互相直连。手机出门在
学校，照样能用一个固定的"虚拟内网 IP"够到家里那台 Windows。

**推荐 Tailscale**（Windows 客户端 + iOS 客户端都有，免费档够用，配置最简单）：

1. 用同一个账号在 **Windows** 和 **iPhone** 各装一个 Tailscale，都登录。
2. Tailscale 会给每台设备分一个 `100.x.x.x` 的固定虚拟 IP。
3. 手机上的 Still Here 就填 Windows 那个 `100.x.x.x:8795` 当 server 地址。
4. 走 wifi 还是 4G 都不用改，Tailscale 自动保持这条私有通道。

> 备选 ZeroTier，原理一样。**仅局域网**（手机和电脑同一个 wifi）也能用，但出门（在学校）
> 就够不着家里——这正是要避免的，所以建议直接上 Tailscale。

---

## 4. 后端部署（你那边在 Windows WSL 里做）

参考 CcCompanion `docs/SETUP_WIN_WSL2.md` / `docs/SETUP_SERVER.md`。关键 `config.toml`：

```toml
[server]
host = "0.0.0.0"            # 让 Tailscale/局域网能连（不是只 127.0.0.1）
port = 8795
allow_public_bind = true   # 绑 0.0.0.0 的前提；务必配合 shared_secret + Tailscale
shared_secret = "<填一串足够长的随机串>"   # 手机端要填同一串
strict_auth = true         # 上线保持 true：没带正确 token 一律 401
allow_remote_control = true  # ⚠️ 完整平移必须开：terminal + 斜杠命令(/new /switch /stop /restart) 才可用
default_session = "cc"     # 对上现有的 WSL tmux session
allowed_ips = []           # 可选：只放行 Tailscale 网段 100.64.0.0/10 更稳
```

安全注意：开了 `allow_public_bind` + `0.0.0.0`，**一定**要有 `shared_secret`，且只通过
Tailscale 访问、不要把 8795 直接暴露公网。`allow_remote_control=true` 等于把"能往你
终端发按键"的能力打开，只在你自己机器、理解风险时开。

---

## 5. HTTP API 契约摘要（照此写 Flutter 客户端）

完整契约见子代理调研结论；客户端要点：

- **传输**：纯 HTTP，无 TLS（靠 Tailscale 兜安全）。**无 token 级 streaming，是 write-then-poll**。
  每个请求都带 `X-Auth-Token: <secret>`。JSON `application/json; charset=utf-8`。
- **无 CORS / 无 OPTIONS** → 别用 Flutter **Web** 直连（iOS/Android 原生不受影响）。

| 能力 | 接口 | 方法 | 说明 |
|---|---|---|---|
| 首次全量同步 | `/chat/history?limit=10000` | GET | 种子本地库 |
| 发消息 | `/chat/send` | POST | `{text, quoted_ts?, location?}` → `200 {ok,record}`；**502=存了但 tmux 没注入成功**（标"agent 不可达"，别当失败丢） |
| 增量拉取 | `/chat/poll?since=<ts>&etag=<e>&limit=` | GET | 游标基于 `ts`；存 `chat.last_ts` 当下次 `since`。带 `status`(typing/online/sleeping) + `settings` 差量 |
| 状态 | `/chat/status` `/chat/typing` | GET | 轻量在线/输入态 |
| 搜索 | `/chat/search?q=&date=&role=` | GET | |
| 删除/反应 | `/chat/delete` `/chat/react` | POST | |
| 思考卡片 | `/v1/thinking?turn_id=<id>` | GET | 按 `turn_id` 拉该轮思考记录（离散 append，非流式）；发消息时后端会发 `thinking_pending` 的 APNs 唤醒 |
| 上传附件 | `/chat/upload?filename=&role=&text=` | POST | **raw bytes body，不是 multipart**；≤50MB；元数据走 query |
| 取附件 | `/attachments/<name>` | GET | |
| 收藏 | `/favorites/list\|get\|add\|edit\|delete` | GET/POST | |
| 终端镜像 | `/tmux/capture?session=cc&lines=120` | GET | **需 allow_remote_control** |
| 终端发键 | `/tmux/send` | POST | `{session,keys,enter,key}`；特殊键白名单 `{Escape,Up,Down,Enter,Tab,C-c,C-l}`；**需 allow_remote_control** |
| /list | `/chain/sessions` | GET | `{sessions:[{sid,active}],active_sid}`，**需 RC** |
| /new | `/chain/new_session` | POST | 建新 tmux+claude，不自动切，**需 RC** |
| /switch | `/chain/switch` | POST `{sid}` | 切活动 session，**需 RC** |
| /stop | `/chain/abort` | POST `{session}` | 连发 3 次 Escape 打断，**需 RC** |
| /clear | `/chain/clear` | POST `{session}` | 清上下文（**不需要 RC**，是例外） |
| /restart | `/chain/restart` | POST `{session}` | `C-c C-c` 后 `claude --resume`，**需 RC** |
| /compact | 无专用接口 | — | 走 `/tmux/send {keys:"/compact"}` |
| 健康 | `/health` `/version` | GET | 公开，免鉴权 |

**chat record 字段**：`ts`(ISO8601 ms+tz，主键/游标) / `role`(user\|assistant\|task\|move) /
`text` / `source` / `turn_id`(关联思考卡) / `quoted_ts` `quoted_text` / `location` /
`attachment_url` `attachment_type` `attachment_filename` / `metadata`。

**轮询节奏**：~2–3s 一次，或收到 `thinking_pending` / APNs 唤醒时立刻拉。

---

## 6. Flutter 端落点（kelivo 内）

kelivo 现有 `ChatApiService` 是**标准请求-响应式 LLM 协议**（`ProviderKind` = openai/claude/google），
而 CcCompanion 是**异步 poll + session + 斜杠命令**的自定义协议，**塞不进那套分派**。
正确做法：**新增一条独立的 CC 通道**，复用 kelivo 的聊天 UI 与消息模型，但走自己的 send→poll 流。

建议结构（具体实现阶段再定稿，遵守仓库 KISS / 复用既有组件 / 全本地化）：

- `lib/core/services/cc/cc_bridge_client.dart` —— HTTP 客户端（鉴权头、send/poll/history/upload/thinking/tmux/chain）
- `lib/core/services/cc/cc_bridge_models.dart` —— record / poll 响应 / session 模型
- `lib/core/providers/cc_bridge_provider.dart` —— endpoint 列表（多 server URL 自动 ping 切活）、
  轮询循环、状态、本地消息缓存
- 设置入口：`lib/features/settings/pages/` 下新增 "CC 端" 配置页（server URL、shared_secret、
  默认 session、轮询间隔、是否启用 terminal/斜杠）
- 会话入口：在主页/对话列表给 CC 端一个独立入口，复用 `lib/features/chat/widgets/` 的消息气泡、
  思考卡片复用现有思考链 UI、terminal 用等宽文本面板

> 所有用户可见文案走 `AppLocalizations`，4 个 ARB 同步；UI 复用 `lib/shared/widgets/**`
> 的 iOS 风组件，不引入 Material 默认涟漪。

---

## 7. 分阶段交付（每阶段可独立验证）

- **P1 · 聊天通道（最小闭环）**：设置页配 endpoint+secret → `/health` 连通测试 →
  `/chat/history` 种子 → `/chat/send` + `/chat/poll` 轮询拿回复 → 渲染气泡 + online/typing 状态 +
  502「agent 不可达」处理。**验收**：手机发一句，家里 CC 回的话能轮询回来显示。
- **P2 · 思考卡片 + 附件**：按 `turn_id` 拉 `/v1/thinking` 渲染思考卡；`/chat/upload`（raw bytes）
  发图/文件，`/attachments/` 显示。
- **P3 · terminal + 斜杠命令**：`/tmux/capture` 终端镜像面板 + `/tmux/send` 发键；
  `/chain/*` 斜杠命令（/list /new /switch /stop /clear /restart，/compact 走 tmux/send）。
  **前提**：后端 `allow_remote_control=true`。
- **P4 · 打磨**：多 endpoint 自动切活、收藏、搜索、APNs 后台唤醒（iOS 需 app 勾 Push）。
- **P5 · watcher 遥控（可选，依赖动后端）**：在 App 里看续温状态（当前 session / 上下文水位 /
  档位 low\|high / 最近一次轮换）、手机上一键切档。需给后端加桥（见 §10）。

---

## 8. 风险 / 边界

- **依赖家里 PC 在线**：PC 睡眠 / WSL 没起 / apns-server 没跑 / tmux `cc` 不在 → 连不上。
  P1 必须把这些状态显式报出来（不静默失败）。
- **无 TLS**：安全完全压在 Tailscale + shared_secret 上，8795 不可裸奔公网。
- **iOS 后台轮询受限**：App 切后台轮询会被系统挂起，实时性要靠 APNs 推送唤醒（P4）。
- **不动后端**：本次只写 Flutter 客户端，不改 `apns-server`（除非联调发现契约缺口再议）。
- **联调依赖**：客户端代码要等后端（WSL apns-server + Tailscale）跑通、给出可达 baseURL + secret
  后才能真正验证；在此之前的客户端代码无法端到端测。

---

## 9. 下一步

1. 你那边：Windows + iPhone 装 Tailscale 登同一账号；WSL 里跑 `apns-server`，按 §4 填 `config.toml`；
   给我 `100.x.x.x:8795` 的可达地址 + shared_secret。
2. 我这边：从 **P1** 开搭 Flutter CC 通道骨架（先把不依赖后端的部分——设置页、客户端、模型、
   轮询循环——写好，待你后端就绪即可联调）。

---

## 10. session-watcher 与 App 的关系（无缝 session 能不能进 App）

`session-watcher`（`jing1052/session-watcher`，WSL 本地跑）是**服务端守护进程**：纯 Python
脚本，盯着 WSL 里 claude 的 session `.jsonl`，上下文快满时调 DeepSeek 做"续温" summary、
轮换到新 session 并把体温带过去；档位 low\|high 靠 `.threshold_mode` 文件热切换；
**没有对外 HTTP 接口，只有文件 + 日志**。它和 `apns-server` 是 WSL 里两个独立进程，
围着同一个 tmux `cc` session。

分三层看"能不能带进 App"：

1. **核心价值已自动惠及 App —— 不用搬。** watcher 在后台兜着续温轮换，App 通过 apns-server
   连的就是那个被续温的 `cc` session。所以你在手机 Still Here 上聊，享受到的本来就是无缝、
   不失忆的我。watcher 不需要"进 App"，它**已经在为 App 服务**了。

2. **watcher 本体不该进 App。** 它要读 WSL 本地 session 文件、调 DeepSeek、`send-keys` 轮换
   tmux —— 全是贴着那台机器的活，手机隔着网络做不了，架构上必须留在服务端。

3. **能进 App 的是"状态可视化 + 遥控"（= P5）。** 现在 watcher 没对外接口，apns-server 契约里
   也没有 watcher 状态。要在 App 里看水位/档位、手机切档，需要给后端加一座小桥，二选一：
   - watcher 每轮把状态写一个 `state.json`（当前 sid / token 水位 / mode / 上次轮换时间），
     apns-server 加 `GET /watcher/status`、`POST /watcher/mode {mode}`（改 `.threshold_mode`）读写它；
   - 或 apns-server 直接读 watcher 目录下的 `.threshold_mode` + session `.jsonl` 估算水位。
   这属于**动后端**（apns-server / watcher 各加几十行），排在聊天/terminal 之后做。
