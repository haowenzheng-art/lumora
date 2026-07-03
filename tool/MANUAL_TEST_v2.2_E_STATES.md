# v2.2-E 三态设计手动测试流程

> **改动概述**：新建 `EmptyState` / `SkeletonBox` 两个组件。SplashPage 我的精灵列表为空时显示 EmptyState（带引导文案 + "记住第一个 ta" 按钮）；`_buildGeneratingView`（图片生成 / 视频生成等待中）用 SkeletonBox 240×240 替换裸 CircularProgressIndicator。
>
> **改动文件**：
> - `lib/widgets/empty_state.dart` — 新建，居中布局：长引号 + 引导文案 + 可选操作按钮
> - `lib/widgets/skeleton_box.dart` — 新建，手写 shimmer 渐变（AnimatedBuilder 1400ms 循环）
> - `lib/main.dart` — SplashPage 加 `else` 分支显示 EmptyState；`_buildGeneratingView` 用 SkeletonBox 替换 CircularProgressIndicator；加 2 个 import
>
> **设计选择**：
> - **手写 shimmer 而非用 shimmer 包**：避免新增依赖，30 行 AnimatedBuilder 足够
> - **不做错误兜底组件**：v2.2 不做 ErrorView（避免"为未来需求设计"），现有 SnackBar 错误处理够用
> - **EmptyState 用「琥珀色长引号」**：呼应 Lumora 主色 + "信札感"

---

## 测试前准备

`flutter analyze` 通过 + `flutter test memory_smoke_test.dart` 12/12 通过（已验证）。

---

## 手动测试步骤

### Step 1 · SplashPage 空状态（重点）

1. **备份当前精灵索引**：复制 `agent_data/` 到 `_backup_agent_data/`（如果有自定义精灵）
2. **临时清空精灵索引**（如果有）：让 `_mySprites.isEmpty`
3. 启动 App

**预期**：
- SplashPage 中间显示居中的琥珀色长引号 `「`
- 下方两行文案：
  - "还没有人被你想起"（主，14pt 月光蓝色）
  - "定制一只属于你的精灵，让 ta 陪你走过一段。"（hint，12pt 灰色）
- 再下方一个琥珀色描边的圆角按钮："记住第一个 ta"
- 按钮按下去有 0.96 缩放（v2.2-B 的 Pressable）
- 点击后进入 TextCustomPage

### Step 2 · SplashPage 非空状态（回归）

1. 恢复精灵索引（备份回 `_backup_agent_data/` → `agent_data/`）
2. 重启 App

**预期**：
- 我的精灵列表正常显示（横向滚动卡片）
- EmptyState 不出现

### Step 3 · 图片生成等待（_buildGeneratingView）

1. 进入 TextCustomPage
2. 填性别 + 气质 + 风格
3. 点"生成"

**预期**：
- 之前是裸 80×80 琥珀色 spinner
- 现在显示 240×240 圆角 shimmer 占位框（横向渐变流动）
- 下方"ta 正在成形…"状态文字不变
- 再下方"大约需要 30-60 秒"提示文字不变
- 整体观感从"工具感"变成"信札感"

### Step 4 · 视频生成等待（如果走视频流程）

如果你的精灵走的是视频生成（v0.2 图生视频），等待时也用 SkeletonBox 占位。

### Step 5 · 节奏测试

1. 多个 SkeletonBox 同时显示（比如图片生成 + 视频生成）
2. 观察 shimmer 动画是否流畅

**预期**：
- shimmer 动画不卡顿
- 多个 SkeletonBox 的 shimmer 不完全同步（因为每个有自己的 AnimationController）——这是有意的，避免视觉单调

### Step 6 · 异常边界

1. SkeletonBox 在小尺寸窗口（高度 < 300px）下显示
2. EmptyState 在超宽窗口（> 1920px）下显示

**预期**：
- SkeletonBox 的尺寸由调用方决定（240×240 是 TextCustomPage/PhotoCustomPage 约定）
- EmptyState 的居中布局在宽屏也居中（Center + Padding）

---

## 验证清单

| # | 项 | 通过 | 备注 |
|---|---|---|---|
| 1 | SplashPage 空状态显示 EmptyState | ☐ | |
| 2 | EmptyState 文案"还没有人被你想起" | ☐ | |
| 3 | EmptyState "记住第一个 ta" 按钮可点击 | ☐ | |
| 4 | EmptyState 按钮点击进入 TextCustomPage | ☐ | |
| 5 | SplashPage 有精灵时不显示 EmptyState | ☐ | |
| 6 | 图片生成等待显示 240×240 SkeletonBox | ☐ | |
| 7 | SkeletonBox shimmer 动画流畅 | ☐ | |
| 8 | 视频生成等待也用 SkeletonBox | ☐ | |
| 9 | 多个 SkeletonBox 不完全同步 | ☐ | |
| 10 | `flutter analyze` 无新增 error | ☐ | |
| 11 | `flutter test memory_smoke_test.dart` 12/12 | ☐ | |

---

## 已知问题

1. **未做错误兜底组件**：v2.2 不做 ErrorView。现有 SnackBar 错误处理够用，CLAUDE.md "don't design for hypothetical future requirements" 原则。如未来真有需要再做。
2. **EmptyState 只在 SplashPage 用**：聊天页 / 记忆 onboarding 没有 EmptyState 调用，因为这些页面不会"无数据"（chat 至少能进，onboarding 至少能填 0 张卡）。
3. **SkeletonBox 高度固定 240**：跟 TextCustomPage/PhotoCustomPage 的立绘尺寸约定。如果未来立绘尺寸变化，需要同步修改。

---

## 回退方案

```bash
git checkout HEAD~1 -- lib/main.dart
rm -rf lib/widgets/empty_state.dart lib/widgets/skeleton_box.dart
```