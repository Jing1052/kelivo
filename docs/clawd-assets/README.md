# assets/clawd/ 资产流水线（2026-07-03）

`assets/clawd/` 里的像素图标和桌宠 GIF 是怎么来的，以后加表情照这里复刻。

## 素材源

- **Clawd 螃蟹**：仓库 `jing1052/clawd-emotes-skill` 的 `gallery/`（24 个透明循环 GIF，240×240），
  画新表情/改表情照该仓库 `SKILL.md` 的规则来（SVG+CSS keyframes → 导出 GIF）。
- **Cing 海豹（斑海豹幼崽）**：本目录 `seal.html` 是 SVG+CSS 源码（idle 懒瘫 / sleep 睡觉 / fish 抱鱼
  三张卡，照 clawd-emotes-skill 的画法规则写的）。加海豹新表情直接在这个文件里加卡，
  用 skill 的 `scripts/export_transparent.js` 导出。

## 处理脚本 `process_assets.py`

一个脚本管两类产物（需要 Pillow + 完整版 ffmpeg；CC web 容器里 playwright 自带的
ffmpeg 是裁剪版没有 PNG 解码，要 `apt-get install ffmpeg`）：

1. **桌宠 GIF（`pet-*.gif`）**：原始 240×240 画布留白太多，按"整池联合包围盒"统一裁剪——
   Clawd 池一个框（156×177）、海豹池一个框（72×79），两框共享地面线（裁剪框底边相同），
   包围盒用**占有率阈值**（行/列不透明像素质量 ≥8% 才算内容）甩掉飞远变淡的粒子。
   App 里按 177:79 的高度比渲染，两只就是同一像素比例、脚踩同一条线
   （`still_rooms_page.dart` 的 `_HallPets`）。
2. **门图标 PNG（`icon-*.png`）**：取各 GIF 首帧，按**最大连通域质量 ≥8%** 过滤掉
   爱心/音符/彩纸等小粒子后紧裁成方形。门→表情的映射在脚本 `ICONS` 字典里
   （注意 capsule 用 qixi、wander 用 dragon-boat，是试过 lantern/exercise 首帧太散之后换的）。

> 图标用静态 PNG 而不是动图：14 个 GIF 在九宫格里一起动太闹（spec 里预留过这个决定），
> 且省体积。桌宠才是动的。

## 体积账

本次全部 25 个文件共约 944KB（预算 <2MB）。加新表情时记得看总量。

## 2026-07-03 追加 · 兔男郎 + 全屋悬浮

- `bunny.html`：Llawd 兔男郎表情源码（黑兔耳+领结+袖扣+飘心，小猫钦点的调教室门牌）。
  导出后同一素材出两份：`icon-locked.png`（首帧连通域裁剪）+ `pet-bunny.gif`
  （**必须用与螃蟹池相同的裁剪框 `crop=156:177:42:60`**，保证与其它表情共享地面线）。
- 桌宠已从门厅页搬到 **MaterialApp.builder 全局悬浮层**（`lib/features/home/widgets/floating_pets.dart`，
  仅移动端）——聊天窗/终端/设置全都跟着；长按面板经全局 `rootNavigatorKey` 弹出
  （桌宠层在 Navigator 之上，用自己的 context 弹 sheet 会找不到 Navigator）。
- 显示名遵循姓氏交换：**Clawd → Llawd**（资产路径仍叫 clawd，不迁移）。
