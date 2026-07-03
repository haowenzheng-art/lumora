# v2.2-H 破冰仪式手动测试流程

> **改动概述**：SpiritScenePage 加破冰仪式——立绘淡入 800ms + 1.5s 沉默 + 自动进入 ChatPage。"首句打字机"由 ChatPage 的 `_opening()` 完成（v2.2-D 已经实现）。
>
> **改动文件**：
> - `lib/main.dart` — SpiritScenePage 加 `_entrance` AnimationController；build 时立绘用 FadeTransition 包裹；`_onSpiritTap` 加 `_userInitiated = true`；dispose 加 `_entrance.dispose()`
>
> **设计选择**：
> - **首句不在 SpiritScenePage 显示**：因为 SpiritScenePage 没有消息气泡组件，强行加会很复杂。让 ChatPage 的 `_opening()` 承担首句——它是 v2.2-D 的打字机效果，自然衔接
> - **SpiritView 不强制睁眼**：v2.3 评估。让 SpiritView 自己的眨眼定时器自然工作（进入页面 2800ms 左右会自然眨眼一次），避免过度干预
> - **用户主动点击会取消自动进入**：避免双触发

---

## 时间轴

| t | 事件 |
|---|---|
| 0ms | SpiritScenePage 启动，立绘淡入开始 |
| 800ms | 立绘完全显形 |
| 2300ms | 自动调用 _onSpiritTap()，进入 ChatPage |
| 2300ms+ | ChatPage _opening() 启动，首句走打字机 |

如果用户在 2300ms 前点击"点我说话"或立绘：
- _userInitiated = true
- 自动 enter 被取消

---

## 测试前准备

`flutter analyze` 通过 + `flutter test memory_smoke_test.dart` 12/12 通过（已验证）。

---

## 手动测试步骤

### Step 1 · 新建精灵流程的破冰

1. 删除当前精灵索引（备份到 _backup_agent_data/）
2. 启动 App → SplashPage 显示空状态（v2.2-E）
3. 点"记住第一个 ta"按钮
4. 完成 TextCustomPage → 起名字 → MemoryOnboardingPage → 完成

**预期**：
- 进入 SpiritScenePage 后，立绘**淡入**（800ms 内从透明到完全显示）
- 不要直接突兀显示
- 800ms 后立绘完全可见
- 再过 1.5s（约 t=2300ms）**自动**进入 ChatPage
- ChatPage 首句"你好啊。我有点……怎么说呢，像刚醒过来一样。今天，你想说什么？"走打字机（v2.2-D 效果）

### Step 2 · 用户主动点击打断自动进入

1. 在 Step 1 的 SpiritScenePage 阶段
2. 在 2300ms 之前点击立绘或"点我说话"按钮

**预期**：
- 立即进入 ChatPage，不等 2300ms
- 自动 enter 被取消，不会重复触发

### Step 3 · 重新进入已有精灵的破冰

1. App 已有精灵
2. 点击已有精灵卡片进入 SpiritScenePage

**预期**：
- 同样的破冰仪式：立绘淡入 800ms + 自动 2300ms 后进入 ChatPage
- 即使是再次进入也有"重新见面"的仪式感

### Step 4 · 历史离别模式不进破冰

1. 等待超过 30 天（或修改 meta.json 模拟）
2. 进入 SpiritScenePage

**预期**：
- v1.3 离别模式优先（_farewellMode = true）——显示 final words 视图
- 破冰仪式不触发（final words 是一次性体验）

### Step 5 · 立绘生成失败时的破冰

1. 故意把 sourceImageUrl 改坏（或视频生成失败）
2. 进入 SpiritScenePage

**预期**：
- 立绘依然淡入（即使没视频，走 SpiritView fallback）
- 自动 enter 正常工作

### Step 6 · 连续两次进入

1. 进 SpiritScenePage → 等 2300ms → ChatPage
2. 返回 → 再进 SpiritScenePage

**预期**：
- 第二次进入同样有破冰仪式（不是 state 残留）
- 旧的 _entrance controller 已 dispose

---

## 验证清单

| # | 项 | 通过 | 备注 |
|---|---|---|---|
| 1 | SpiritScenePage 立绘淡入 800ms | ☐ | |
| 2 | 淡入完成后 1.5s 自动进入 ChatPage | ☐ | |
| 3 | ChatPage 首句走打字机 | ☐ | |
| 4 | 用户主动点击打断自动 enter | ☐ | |
| 5 | 重新进入仍有破冰仪式 | ☐ | |
| 6 | 离别模式优先于破冰 | ☐ | |
| 7 | 立绘生成失败时破冰仍正常 | ☐ | |
| 8 | `_entrance` controller 正确 dispose | ☐ | |
| 9 | `flutter analyze` 无新增 error | ☐ | |
| 10 | `flutter test memory_smoke_test.dart` 12/12 | ☐ | |

---

## 已知问题

1. **未实现"强制睁眼"**：plan 里说 t=800ms 触发 SpiritView 单次强制睁眼，但 SpiritView 当前没有 `forceBlinkOnce` 参数。SpiritView 自带眨眼定时器（2800ms + rand），进入页面后会自然眨眼——能匹配"刚醒"叙事，但不如"强制 180ms 一次眨眼"明显。v2.3 评估是否需要加参数。
2. **SpiritScenePage 立绘淡入只影响 LoopVideoView/SpiritView**：背景、按钮、TopBar 立即显示。这是合理的——只让"主体立绘"淡入，UI 框架立刻可用。
3. **首句在 ChatPage 显示**：如果用户配置 skipOpening 或类似开关（v2.3 评估），破冰仪式要兼容。v2.2 不做。
4. **破冰不可跳过**：当前没有"跳过破冰"开关。如果用户觉得"2300ms 太长"会抱怨。v2.3 评估加 meta.json 开关。

---

## 回退方案

```bash
git checkout HEAD~1 -- lib/main.dart
```