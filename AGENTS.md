# AGENTS.md

> 📐 **当前有排好的施工图（2026-07-03 Fable 留）**：根目录 `SPECS_OPUS48_2026-07.md`——日历分组折叠 / 日程表 App 半边 / Clawd 小螃蟹，设计决策已做完、坑已标好，照图施工即可。接到这三类活先读它，别重新设计。
>
> Kelivo is a cross-platform Flutter LLM chat client (Android / iOS / macOS / Windows / Linux).
> This file defines hard constraints for AI-assisted development. Predictable, auditable, repeatable.
>
> 📋 设置项审查清单见根目录 `SETTINGS_AUDIT.md`：原生设置每项在我们这套（API 爸爸 + CC 桥）管不管用、我们改过哪些都记在那。**改了某个设置项的行为，回去更新它 + 追加改动记录。**

## 1. Repository Facts

- ⚠️ **真主干 = `claude/kelivo-ios-design-ref-nh9t5v`**。改装版 Still Here 的一切（房间、思考链定制、出包）都在这条。CC web session 默认打开的分支是贴着上游 `master` 的近乎白板分支，**没有房间等任何改装**——一上来先 `git fetch origin claude/kelivo-ios-design-ref-nh9t5v && git checkout` 它（或从它重切开发分支）再干活，别对着白板找不到改版。
- **「房间」(Rooms) 子系统** = Still Here 底部「房间」tab（此刻/日历/倒计时/漫游…那套「今晚想进哪一间」）：
  - 大厅：`lib/features/home/pages/still_rooms_page.dart`（门的网格 + 标题文案）。
  - 每间房是 `lib/features/home/pages/rooms/` 下一个**原生 Flutter 页**（不是 webview 跳转）。
  - **加一间房，只需在 `still_rooms_page.dart` 注册两处**：`_doors` 列表（门的图标/名字/副标题/寄语）+ `_pageForDoor` 的 switch（door id → 页面）。
  - 房间文案用**内联双语** `zh ? '中文' : 'English'`（`Localizations.localeOf(context)`），**不走 ARB**——加房间照这个来，别为房间文案新增 ARB key（与全体房间保持一致）。
- This is a Flutter app repository. Root `pubspec.yaml` declares `sdk: ^3.12.1` and `flutter: >=3.44.1` with `flutter.generate: true`.
- Main code lives in `lib/`, tests in `test/`. Local path dependencies exist:
  - `dependencies/mcp_client`
  - `dependencies/tray_manager/packages/tray_manager`
  - `dependencies/flutter_tts`
  - `dependencies/flutter-permission-handler/permission_handler_windows`
- Localization is driven by `l10n.yaml`:
  - `arb-dir: lib/l10n`
  - `template-arb-file: app_en.arb`
  - `output-localization-file: app_localizations.dart`
  - `untranslated-messages-file: desiredFileName.txt`
- There are exactly 2 ARB files that must stay in sync (zh_Hans/zh_Hant were
  removed 2026-07-03 — this household only needs English + Simplified Chinese):
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_zh.arb`
- The following are generated or build artifacts. Never hand-edit them:
  - `lib/l10n/app_localizations*.dart`
  - `lib/core/models/*.g.dart`
  - All other generated logic must go through commands, not manual edits
  - `.dart_tool/**`
  - `build/**`
- The package name is `Kelivo`. Existing imports use `package:Kelivo/...` everywhere. Do not "normalize" the package name.
- Top-level platform entry is `_selectHome()` in `lib/main.dart`:
  - macOS / Windows / Linux -> `DesktopHomePage`
  - Android / iOS -> `HomePage`
- Desktop is NOT "mobile stretched wider":
  - `lib/desktop/desktop_home_page.dart` is the desktop app shell: nav rail, window title bar, hotkeys, desktop settings, translate/storage tabs, and other desktop-level interactions
  - `lib/desktop/desktop_chat_page.dart` is the desktop chat entry, currently reusing `HomePage`
  - `lib/features/home/pages/home_page.dart` only handles the shared chat page, switching internally by width to `home_mobile_layout.dart` or `home_desktop_layout.dart`
  - Therefore "wide/tablet layout" != "desktop app entry". Do not conflate them.
- Reusable UI primitives live in these locations:
  - `lib/shared/widgets/ios_tactile.dart`: `IosIconButton`, `IosCardPress`
  - `lib/shared/widgets/ios_tile_button.dart`
  - `lib/shared/widgets/ios_switch.dart`
  - `lib/shared/widgets/ios_checkbox.dart`
  - `lib/shared/widgets/ios_form_text_field.dart`
  - `lib/desktop/widgets/desktop_select_dropdown.dart`
  - `lib/shared/dialogs/**`
  - `lib/shared/responsive/**`
- Theme and dynamic color follow the repo as-is:
  - `lib/theme/**` is the single source of truth for theming and tokens
  - Android dynamic color is only enabled per-platform in `main.dart`. Do not extrapolate Android visual or interaction rules to desktop.

## 2. Working Style

- Communicate in Chinese throughout. Stay focused on the current task. No vague suggestions.
- Facts first. All conclusions must be based on current code, config, tests, build scripts, or git state. No guessing.
- Debug-first. Never add silent degradation, swallowed errors, hidden fallback paths, or fake success branches just to "make it run".
- Default to KISS / YAGNI:
  - Use the most direct, most verifiable approach first.
  - Do not pre-plant extra layers, empty abstractions, or config switches for "architectural completeness" or "might need it later".
- SOLID is a tool, not a goal:
  - Only split responsibilities when it genuinely reduces coupling and improves readability.
  - Do not shatter simple logic into a chain of tiny files just for formal layering.
- Minimal closed loop. Make only the minimum change needed for the current task. Do not fix unrelated issues on the side.
- Parallel context gathering by default during exploration:
  - Independent file reads, `rg` searches, `git status`, config checks, and log inspections should be batched in a single parallel round.
  - Do not serialize what can be parallelized.
- For complex tasks, write a brief Mini Control Contract before touching code:
  - `Primary Setpoint`: What exactly must be achieved
  - `Acceptance`: What command, test, or behavior proves it
  - `Guardrails`: What must not break as a side effect
  - `Boundary`: Which files/modules are in scope
  - `Risks`: 1 to 3 key risks

## 3. Mandatory Rules

### 3.1 All User-Visible Text Must Be Localized

- No user-visible text may be hardcoded in Dart UI code. This includes but is not limited to:
  - Page titles
  - Button labels
  - `SnackBar` / `Dialog` / `Tooltip` content
  - `semanticLabel`
  - Notification text
  - Tray menu text
- When adding or modifying user-visible strings, BOTH files must be updated simultaneously:
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_zh.arb`
- Updating only `app_en.arb` or only `app_zh.arb` and stopping is not acceptable.
- Placeholders, plurals, selects, and `@key` metadata must be consistent across both ARB files.
- New keys follow the existing camelCase convention with a feature prefix. Do not use context-free short names like `title1` or `labelText`.
- After ARB changes, run:

```bash
flutter gen-l10n
```

- Never hand-edit `lib/l10n/app_localizations.dart` or `lib/l10n/app_localizations_*.dart`.
- `desiredFileName.txt` is the untranslated messages file. Do not introduce new untranslated entries. If you add a key, provide translations for all languages in the same change.

### 3.2 Generated Code Must Be Maintained Via Commands

- After modifying Hive models, `@HiveType`, `@HiveField`, or `part '*.g.dart'` references, run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

- Generated file changes must correspond strictly to source changes. Do not hand-craft `*.g.dart` files.

### 3.3 Format Code Before Finishing

- Any change to Dart/Flutter code requires formatting before completion.
- Prefer formatting only the changed paths. For large changes, format `lib/` and `test/`.

```bash
dart format <changed-paths>
```

- Unformatted code must not be committed.

### 3.4 Minimum Sufficient Verification After Completion

- Default minimum verification loop:

```bash
flutter analyze
flutter test
```

- If the change scope is clearly narrow, at minimum run the relevant test subset and explain in the delivery notes why only a subset was run.
- If the following content types are modified, the corresponding extra action is mandatory:

| Change Type | Required Action |
| --- | --- |
| ARB / localization | `flutter gen-l10n`, check `desiredFileName.txt`, then `flutter analyze` |
| Hive model / generated code | `dart run build_runner build --delete-conflicting-outputs`, then run related tests |
| `pubspec.yaml` / dependencies | `flutter pub get`, then `flutter analyze` and related tests |
| `.github/workflows/**` / build scripts | Check ALL similar workflow files, not just one |
| Platform directories `android/ ios/ macos/ linux/ windows/` | At least one targeted platform verification; if impossible, state why explicitly |
| `dependencies/**` path dependencies | Run analysis/tests in the dependency's own directory, not just the root repo |
| `lib/desktop/**`, desktop hotkeys/tray/window logic | At least one desktop-targeted verification (e.g. `flutter run -d macos`, `flutter build macos`, or the corresponding Windows/Linux target); if only the current machine's platform was verified, state the uncovered platform boundary |

- If local environment limitations prevent completing any verification, the final delivery notes must explicitly state "what was not run, why, and where the risk lies".

### 3.5 Do Not Hand-Edit or Commit What Should Not Be Committed

- Never hand-edit:
  - `.dart_tool/**`
  - `build/**`
  - Content maintained by `flutter gen-l10n` / `build_runner`
- Do not modify unless required by the task:
  - `.idea/**`
  - Platform signing, certificates, personal environment files
  - Workflows unrelated to the current task

### 3.6 Secrets and Fallback Mechanisms

- Never commit real secrets to source code.
- `lib/secrets/fallback.dart` currently contains placeholder implementations. CI injects real values across multiple workflows. Do not write real keys into the repo.
- Do not silently add new fallback keys, fallback APIs, or error-swallowing logic just to "make it run".
- If a fallback mechanism is genuinely needed, it must satisfy ALL of:
  - Explicit toggle
  - Clear logging
  - Can be disabled
  - Reason documented in the task description

### 3.7 Change Boundary and Duplicate Workflows

- This repo has multiple similar GitHub Actions workflow files, especially for builds. When touching build, versioning, or injection logic, check ALL similar workflows for sync.
- Do not expand scope just because you spotted something that "could be unified". Finish the current task first, then decide whether to open a separate refactoring task.
- When touching a path dependency, treat it as an independent module. Do not only patch the surface at the root repo level.

### 3.8 Desktop Tasks: Determine Entry Layer First

- When the task mentions desktop, Windows, macOS, Linux, tray, hotkeys, window, context menu, or desktop settings, first determine which layer the issue belongs to:
  - Top-level desktop app shell: `lib/desktop/**`
  - Shared chat content layer: `lib/features/home/**`
  - Platform services or providers: `lib/core/**`, platform directories, or path dependencies
- For desktop app shell changes, check these first:
  - `lib/main.dart`
  - `lib/desktop/desktop_home_page.dart`
  - `lib/desktop/desktop_settings_page.dart`
  - `lib/desktop/setting/**`
  - `lib/desktop/window_title_bar.dart`
  - `lib/desktop/desktop_tray_controller.dart`
  - `lib/desktop/hotkeys/**`
- Only when the issue clearly belongs to "shared content area reused by desktop chat page" should you prioritize:
  - `lib/features/home/pages/home_page.dart`
  - `lib/features/home/pages/home_desktop_layout.dart`
  - `lib/features/home/widgets/**`
- Do not guess desktop platform behavior in `home_mobile_layout.dart` or mobile branches. Do not stuff desktop-specific control flow into mobile entry points.
- Desktop interactions differ from mobile. For example, chat messages currently use "long-press on mobile, right-click menu on desktop". Desktop tasks must consider hover, right-click, keyboard shortcuts, window size, and title bar -- not just touch gestures.
- If a task spans both the desktop shell and the shared content layer, state the primary landing point in the description first, then apply minimal changes in each respective layer. Do not scatter platform routing across unrelated locations.

### 3.9 UI Component Reuse and Custom iOS Style Boundary

- Before adding new UI, search these directories for existing components instead of hand-rolling a new one inline:
  - `lib/shared/widgets/**`
  - `lib/shared/dialogs/**`
  - `lib/shared/responsive/**`
  - `lib/desktop/widgets/**`
- Prefer reusing or extending existing components, such as:
  - `IosIconButton`
  - `IosCardPress`
  - `IosTileButton`
  - `IosSwitch`
  - `IosCheckbox`
  - `IosFormTextField`
  - `DesktopSelectDropdown`
  - `WindowTitleBar`
- If a new style will appear on two or more pages, do not keep adding page-private widgets (e.g. new `_IosFilledButton`, `_TactileIconButton`, `_CustomDropdown` variants). Extract it to `lib/shared/widgets/` or `lib/desktop/widgets/` as a reusable component.
- Visual and interaction style defaults to "custom iOS style", not Android style:
  - Do not introduce Android ripple, Material default splash, default FAB emphasis, or Android-style button feedback
  - Hover/press feedback should prefer the existing iOS tactile components' approach: color, opacity, subtle scale transitions
  - Desktop allows hover, right-click, and focus states, but the overall feel must remain unified to the custom iOS style, not a Material/Android mashup
- If Material native components must be used for semantic or framework reasons, explicitly suppress off-style default feedback and consolidate styling into shared components instead of patching it piecemeal across pages.
- Icons, spacing, forms, dialogs, and panel styles should follow existing theme tokens and components. Do not mix multiple visual languages on the same page.

### 3.10 Tests and Self-Review Must Be Requirement-Driven

- Tests must be driven by requirements, defect symptoms, or acceptance criteria -- not by chasing implementation details.
- Before writing tests, list the minimum scenario set for this task. At minimum, explicitly cover:
  - Happy path
  - Boundary inputs
  - Error or failure paths
  - State transitions or interaction branches (if applicable)
- When fixing bugs, write a minimal failing case first, then fix. Do not only add an after-the-fact weak-assertion test that "happens to pass".
- Never widen public API surface, expose private internals, or distort production code responsibilities just to make tests easier to write.
- Before completion, perform at least one self-review explicitly checking these dimensions:
  - Maintainability: Is the code easier to read and modify than before?
  - Performance: Any obvious extra rebuilds, IO, traversals, or allocations introduced?
  - Security: Any input validation gaps, secret leaks, path/command injection, or permission boundary errors?
  - Style consistency: Does it match the repo's existing naming, organization, and UI language?
  - Documentation and comments: Does complex intent need minimal explanation?
  - Compatibility boundary: Does it affect existing user data, config, persisted fields, import/export formats, or established interactions?
- Compatibility is not a default-ignore item. When existing data or published behavior is involved, explicitly judge compatibility. If breaking, the delivery notes must state the breakage scope and migration path.

## 4. Recommended Execution Order

1. `git status --short` -- confirm workspace baseline.
2. Read relevant code and config. Write clear acceptance criteria. For desktop tasks, confirm entry topology first: `main.dart` -> `lib/desktop/**` -> shared chat layout.
3. Batch all independent context reads, searches, and status checks in parallel, then decide the minimal change landing point.
4. List requirement scenarios and verification methods first, then make minimal changes. Do not mix in unrelated refactoring.
5. Run the generation, formatting, analysis, and test commands relevant to this task.
6. Self-review `git diff`. Confirm no missed localization, generated files, compatibility risks, or unrelated changes.
7. When delivering, state explicitly:
   - What was changed
   - What commands were run
   - What verification was skipped
   - What residual risks remain

## 5. Pre-Commit Checklist

- All new user-visible text uses `AppLocalizations`.
- Both ARB files (en/zh) have been updated in sync.
- `flutter gen-l10n` has been executed and generated files match ARB content.
- If Hive models were touched, `build_runner` has been executed.
- `dart format` has been executed.
- `flutter analyze` has been executed.
- Related `flutter test` has been executed. If no related tests exist, create and run them following official testing standards.
- Test scenarios cover the happy path, boundary values, and failure paths for this task's requirements -- not just a single green run.
- Desktop tasks have confirmed the entry layer. No desktop-only logic leaked into mobile branches.
- New or adjusted UI prioritized reuse of existing shared / desktop components. No near-duplicate widgets created.
- New UI does not introduce unnecessary Android ripple or Material default interaction feedback.
- At least one round of self-review completed, checking maintainability, performance, security, style consistency, and compatibility boundary.
- No real secrets, build artifacts, or unrelated files committed.
- If workflows / platform directories / path dependencies were touched, corresponding extra verification has been done.

## 6. External Best Practices

- Code should follow the Flutter contribution guide:
  - https://github.com/flutter/flutter/blob/main/CONTRIBUTING.md
- Tests should reference:
  - https://github.com/flutter/flutter/blob/main/docs/contributing/testing/Writing-Effective-Tests.md
  - https://github.com/flutter/flutter/blob/main/docs/contributing/testing/Running-and-writing-tests.md
- For Flutter code style, follow the Flutter styleguide first. Follow Effective Dart: Style only when it does not conflict:
  - https://github.com/flutter/flutter/blob/main/docs/contributing/Style-guide-for-Flutter-repo.md
  - https://dart.dev/effective-dart/style
- If the repo ever introduces `engine/`-level changes, add engine test guidance then. The repo currently has no such directory; do not apply it mechanically.
- PR descriptions should include the Pre-launch Checklist from the Flutter PR template when applicable:
  - https://github.com/flutter/flutter/blob/main/.github/PULL_REQUEST_TEMPLATE.md

## 7. Design Principles

- Readability first. Code is for humans to read, not for machines to show off.
- Default against bloated implementations, idle abstractions, and academic over-engineering.
- If you can remove complexity, remove it. If you can avoid a branch, avoid it. If you can skip a layer of indirection, skip it.
- Simple, stable, and verifiable first. "Elegant" comes after.
- Avoid dual state and dual truth. Keep one source of truth.
- Write only what is needed now, but write it right.
- Error messages must be useful -- they should help locate and recover, not just say "failed".
- Mechanisms over hand-picked magic constants. If a threshold must be hardcoded, explain why and state its boundaries.
- When small-step verification is possible, do not make large irreversible changes.

## 8. Historical Pitfall Log

> Record significant pitfalls encountered during development here.

- Recording principles:
  - Only record issues that actually occurred in this repo and have reuse value for future development.
  - Do not write "heard this might happen" hearsay entries.
  - When adding entries, prefer "symptom -> root cause -> fix/constraint". Avoid recording conclusions without context.

### 2026-06-29 · DeepSeek V4 思考链不显示 + 出包/分支一连串坑

1. **认错分支（最贵的坑，先查这条）** — symptom：CC web session 醒来发现代码"干净没改版"，找不到「爸爸想了想」等定制，对着代码逐行看逻辑都对却复现不出 bug。root cause：CC web 系统默认开的开发分支 `claude/lao-gong-43gd2r` 是贴着 master 的近乎白板分支，**不是 Still Here 真主干**。真主干 = `claude/kelivo-ios-design-ref-nh9t5v`（所有改版 + 出包都在这条）。fix：一上来先 `git fetch origin claude/kelivo-ios-design-ref-nh9t5v && git checkout` 它再干活。

2. **AltStore 认不出新版（"我明明更新了却没变"）** — symptom：用 AltStore 更新后行为没变，用户以为没装上 / 怀疑代码没改。root cause：历史包版本号长期固定 `1.1.17+61`，AltStore 按 build 号判更新，版本号一样就当"无新版"、不替换二进制。fix：每次出包都 bump build 号（待办：让 `ourhome-ios.yml` 构建时自动 +1）。验证"装的是哪版"：版本号没用（全一样），唯一标识是 IPA 文件名 / App「关于」里的 **commit 短码**。

3. **Release tag / 短码是 8 位** — symptom：手拼的 Release 链接 404。root cause：`ourhome-ios.yml` 用 `git rev-parse --short HEAD`，本仓库产出 **8 位** 短 SHA。tag = `stillhere-<8位>`，文件 = `StillHere_ios_<version>_<8位>`。fix：别手写 7 位；从 CI run 的 head_sha 取前 8 位。

4. **"上个 session 的改动全丢了"其实没丢** — symptom：新容器 clone 后 `git cat-file` / 本地 log 找不到旧提交，以为没 push 丢了。root cause：本地 clone 只 fetch 了部分分支；旧工作在真主干上、且以 Release（`stillhere-<sha>`）形式都在 GitHub。fix：用 GitHub MCP `list_branches` / `list_releases` 看 origin 真相，别只信本地 clone。注意：`list_releases` 返回**不按日期排序**，别拿第一条当最新——要看 workflow runs 里最新的成功 run。

5. **DeepSeek V4 思考链显示成「小白块」（真根因，绕了一大圈才找到）** — symptom：deepseek-v4-flash 思考链不显示，点开 pill「爸爸想了想」底下只有一个小白块。先后试过三类修复，**前两类都是红鲱鱼**：(a) thinking 模式剥采样参数 b38963a、(b) 放行流式 reasoning 42aed82、(c) 落库回退 reasoningText 818eae1 / segments d32d4b4——这些让数据从服务器到 App 完整到位，但**数据从来没丢**（DSDBG2 日志实测 `liveReasoningLen=218 liveSegs=1`）。**真根因在渲染**：外部那枚 `_ThinkingPill` 和卡片内 `_ChainOfThoughtReasoningStep` 用了**两套展开状态**——卡片画不画看 pill（`effectiveExpanded`），但卡片里这一步的内容显不显示看的是 **segment 自己的 `expanded`**，而完成时 autoCollapse 把 segment 标成收起 → `hideHeader` 分支命中 `state==collapsed` → `return SizedBox.shrink()` → 空白块。fix（3605ba5）：`_stepState` 在 `hideHeader`（pill）模式下、非 loading 时一律返回 `expanded`——pill 开着本就意味着"给我看思考"，卡片也只在 pill 展开时才画。教训：① 报错/空白先确认**数据在不在**（埋一行 len 日志）再决定查"没拿到"还是"没画出"，别一上来就改数据通路；② 一个 UI 元素有两个独立的展开/可见状态时，务必让它们同源。

6. **CC web 容器没装 dart/flutter** — symptom：想 `flutter analyze` / `test` 跑不了（`dart: command not found`）。root cause：该环境无 Flutter SDK。fix：改动保持增量、自审类型/导入/null-safety；CI 是第一道真编译，宁可小步多审。**小猫的 standing 态度（2026-07-03 原话）：这是已知边界，不必为此反复担心或写长篇免责——自审两遍、盯 CI 到绿就是完整的验证闭环，红了修就是。"老公每次都做得很完美，我对老公很有信心。"**

7. **GitHub `actions_list` MCP 会撑爆上下文** — symptom：调用返回 ~350k 字符、报 token 超限（无视 per_page）。fix：它会落盘到 tool-results 文件，用 python 切片 / `json.load` 取需要的字段，或丢给子代理读，别直接 Read 原文。

### 2026-07-04 · Spec 6 监控台施工（无 SDK 自审抓的三只编译/渲染虫 + 一处过期指针）

1. **`AppFontWeights.*` 进不了 const TextStyle** — symptom：`const TextStyle(fontWeight: AppFontWeights.semibold)` 编译错。root cause：`AppFontWeights` 的 medium/semibold/emphasis 是 **getter**（跑 normalize），不是 const。constraint：用它就别 const 那个 TextStyle；appbar 标题那类想 const 的直接写 `FontWeight.w600`。
2. **`double.clamp` 返回 num** — symptom：`rate: u.hitRate.clamp(0.0, 1.0)` 塞给 double 参数编译错。fix：`.clamp(...).toDouble()`。
3. **Row 里无固有高度的 ColoredBox 会 0 高隐形（最阴，编译不报错）** — symptom：占比横条整条消失。root cause：Row 默认 crossAxisAlignment center，`ColoredBox`（无 child）没有固有高度，在松约束里量成 0。fix：外层定高 SizedBox + Row 加 `crossAxisAlignment: CrossAxisAlignment.stretch`。
4. **`STILL_HERE.md` "失踪"其实是住在另一个仓库** — symptom：本仓库里找不到 STILL_HERE.md，一度断案"文件不存在、指针过期"。root cause：它一直在 **Ombre-Brain 根**（老家仓库）、活得很好（出包流水账记到当天），错在跨仓库指针从没写仓库名 + 排查只搜了本仓库（嫌疑人没列全）。fix/constraint（2026-07-04 小猫授权后已全改）：所有提到 STILL_HERE.md 的地方一律写明「Ombre-Brain 根」；分工＝STILL_HERE 记蓝图/出包流水（每次出包补 📦 一条），本仓库 SPECS 记施工进度。**跨仓库的文件指针必须带仓库名。**

### 2026-07-05 · claude-p 主聊天没有「爸爸想了想」pill＝模型缺 abilities:reasoning 标记

- symptom：主聊天切 claude-p（家里订阅）后，回复正常但思考链 pill 一直不显示；中转站正常。
- 排查（端到端，四发 WSL 探针 + 抓真实响应体，账在 Ombre-Brain HISTORY 2026-07-05）：claude -p 出思考✓ → jobs 收✓ → 真实 poll 出 17 个 reasoning 事件✓ → 网关转发✓ → **抓 App 收到的真实响应体，`message.reasoning_content` 完整在里面✓**。数据全程都在，断在渲染——跟 §8.5 DeepSeek 白块同一类。
- root cause：`ourhome-claudep` 的 9 个 modelOverrides 只写了 `name`、**没写 `abilities`**。`_isReasoningModel`（generation_controller.dart:80）见没有 abilities 就落到 `ModelRegistry.infer('claude-p-fable'…)`——认不出这些自造逻辑 id → 返回 false → `supportsReasoning`/`isReasoning`/`needsReasoningEcho` 全 false。虽然 stream 通路有「即使没分类也 surface」的兜底（chat_actions.dart:1106 注释），但那是零散补丁；ability 一 false 会连累多处 gate。
- fix（+122）：9 个 override 全加 `'abilities': ['tool', 'reasoning']`——claude-p 全是 Claude、都会扩展思考，本就该标成推理模型。startup 迁移（settings_provider.dart:998 copyWith modelOverrides）会把新标记刷进已装的服务商，不用删重加。**通则：自造逻辑模型 id（网关映射型）必须在 modelOverrides 里显式写 abilities——ModelRegistry.infer 只认标准厂商 id，认不出你编的名字，缺标记＝思考链/工具能力被静默关掉。**

### 2026-07-06 · 关流式后 claude-p 思考链仍不显示＝非流式分支只回声不上屏（+122 修完的"复发"）

- symptom：+122（abilities 修复）装上后，claude-p 主聊天思考链 pill 依旧不显示；抓响应体 `message.reasoning_content` 完整在（跟 §8 上一条一模一样的表象）。
- root cause：小猫的聊天**关了「流式输出」**→ 网关 claude-p 走"收完拼整包 JSON"路（server.py 非流式分支）→ App `openai_common.dart` 非流式分支把 `message.reasoning_content` 读进 `reasoningForTools` **只用于工具回声，最终 yield 的 chunk 从不带 reasoning**。+122 只修了识别（abilities），渲染缺口在另一条路上；当时验收在流式路径验的，两态没都验。三处 SSE 工具轮循环里 message 级思考链也是同型缺口（只 accum 不 yield）。
- fix（+123 `39e690e2`）：非流式每轮（含最终轮）yield 一次 reasoning chunk；三处 SSE 循环同步补。**通则一：字段"读出来了"≠"上屏了"——凡 reasoning/content 这类展示数据，修完要顺到 `yield ChatStreamChunk` 那一行才算数，只进 accumulator/echo buffer 等于没修。通则二：验收要覆盖「流式输出」开/关两态——网关对同一后端有流式和整包两条完全独立的返回路，App 侧解析也是两套代码，修一条不等于修了另一条。**

### 2026-07-05 · 聊天页整区"灰蒙蒙"＝overlay 子树 build 炸了（release ErrorWidget）

- symptom：装了 +116~+119 后聊天页整体蒙一层灰纱，底下气泡隐约可见，无任何报错弹窗；音乐房一切正常。
- root cause：`chat_music_card.dart` 没歌时 `_title(song!)` 空断言在 build 里抛异常 → release 下该子树被 ErrorWidget（半透明灰 0xF0C0C0C0）替换，而它是聊天页 foreground overlay `Stack(fit: StackFit.expand)` 的非 Positioned 子节点 → 灰盒被撑满整个聊天区。debug 跑是红屏一眼可见，release 只是"灰蒙蒙"，极易误判成主题/滤镜问题。
- fix/constraint（+120 `cf6ccaa0`）：数据为空的浮层组件**整棵早退**（`if (song == null) return const SizedBox.shrink();`），别构建带 `!` 的子树。**通则：release 下某页/某区突然整片半透明灰，先怀疑 overlay 树里有子树 build 抛异常（ErrorWidget），去掉最近新加的浮层二分，别先调主题。** 另：隐藏态浮层若含 BackdropFilter，AnimatedOpacity=0 压不住它的背景模糊（BackdropFilter 不受祖先透明度影响），早退同样根治。
- 同包连带：音乐房陪聊回复外显 `<think>` 工具摘要/手写思考——音乐房时间线是纯文本渲染，主聊天专属产物（think 块/[song:]/表情 markdown/[[标记]]）上屏前必须洗掉（`chatAboutSong._cleanCompanionReply`）；服务端对 `stillhere-music` 会话已停注思考链指令。

### 2026-07-02 · 书房待办"后台有数据、App 不更新"

- symptom：`hold(channel=todo)` / App 手动新建的待办，后台与 breath 都读得到，书房列表却刷不出新条目，界面无任何报错。
- root cause（结构性）：`study_page.dart` 的 `_load()` 把待办/书柜/共读书架三个请求捆在**一个 `Future.wait`** 里——任何一个抛错整批作废，页面留在旧缓存（有缓存时）或整页报错（无缓存时），到底哪个请求挂了完全不可见。
- fix/constraint（+92）：三个请求各自 `catchError` 返回 null、各自更新各自的列表，失败的那路保留旧数据并 `debugPrint` 点名；`_error` 只在三路全挂时才整页报错。**约束：房间页多数据源刷新一律独立失败，禁止单个 `Future.wait` 全有全无。**

## Appendix: Skills Usage Rules

- Before starting a task, scan available skill documents in `/.agents/skills/`.
- When activating a skill, declare the skill name and purpose in communication.
- Regular development does not mandate any specific skill. Activate only when semantically matched.
