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
| 偏好设置（外观/行为） | `DisplaySettingsPage` | 含「聊天项显示」等，常用 | 部分已审 ↓ |
| 助手 | `AssistantSettingsPage` | 爸爸已单独成栏，这里多半遗留 | ❓ |
| 默认模型 | `DefaultModelPage` | 接 API 命根子 | ❓ |
| 供应商 | `ProvidersPage` | 接 API 命根子 | ❓ |
| 爸爸的搜索 | `DaddySearchPage` | 联网搜索配置 | ❓ |
| TTS（语音朗读） | `TtsServicesPage` | 语音 | ❓ |
| MCP | `McpPage` | 工具服务器 | ❓ |
| 爸爸的内置工具 | `DaddyToolsPage` | 工具开关 | ❓ |
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

### 偏好设置 → 「聊天项显示」 ✅ 已审（2026-06-23）

> 文件：`lib/features/settings/pages/display_settings_page.dart`；渲染在 `chat_message_widget.dart` / `message_list_view.dart`

| 开关 | 作用 | 我们这套 |
|---|---|---|
| 显示用户头像 | 你消息旁的头像 | ✅ |
| 显示用户名称 | 你气泡上方的名字 | ✅ |
| 显示用户时间戳 | 你消息的时间 | ✅ |
| 显示用户消息操作按钮 | 你消息下的复制/编辑/重发 | ✅ |
| 聊天列表模型图标 | 用模型图标当爸爸头像 | ✅（若开了「标题栏显示助手头像」，改用爸爸头像，此项让位） |
| 聊天标题栏显示助手头像 | 标题栏+消息头用爸爸头像 | ✅ |
| 显示模型名称 | 消息头那行名字 | ✅ **现在显示爸爸的名字**（见改动记录 2026-06-23）；关掉＝不显示 |
| 显示模型时间戳 | 爸爸消息的时间 | ✅ |
| 模型名称后显示供应商 | 名字后接「\| 供应商」 | ⚠️ 空挡——头部显示名字非型号，此后缀不再出现，无害 |
| 显示 Token 和上下文统计 | 工具条里的 token 计数 | ✅ |

### 偏好设置 → 其余（字体/背景/气泡/自动滚动等） ❓ 待审

### 其余顶层页 ❓ 待审

> 按总览表逐个钻进去补：每页列「项 × 作用 × 我们这套」。审完把总览表对应行的 ❓ 改掉。
