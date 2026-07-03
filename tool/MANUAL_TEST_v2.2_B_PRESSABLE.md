# v2.2-B 触摸反馈手动测试流程

> **改动概述**：新建 `Pressable` 组件（AnimatedScale 按下 0.96，150ms easeOut，松手回弹），替换关键交互组件的 `GestureDetector`：`_PrimaryButton` / `_RadioChip` / `_WeightChip` / `_TopBar` 返回箭头 / `_CustomButton`（创建流程的圆形图标按钮）。不替换 SpiritScenePage / ChatPage / 卡片等非关键交互路径。
>
> **改动文件**：
> - `lib/widgets/pressable.dart` — 新建，封装按下缩放反馈
> - `lib/main.dart` — 5 处组件改用 Pressable；加 `import 'widgets/pressable.dart';`
>
> **设计选择**：用 `AnimatedScale` 而非 `InkWell` 水波纹——避免跟背景 60 个浮动粒子视觉冲突，跟 Lumora 暗色夜色调性更搭。

---

## 测试前准备

1. 确保 `flutter analyze` 通过 + `flutter test test/memory_smoke_test.dart` 12/12 通过（已验证）
2. `flutter run -d windows` 启动 App

---

## 手动测试步骤

### Step 1 · 主按钮按下反馈（_PrimaryButton）

进入新建流程或任意页面，找到琥珀金色"主按钮"（如"记住 ta""开始"等）。

1. **鼠标按住按钮不松开**（约 200ms）
2. 观察：按钮应该**缩小到 96%**，松开后**平滑回弹**（约 150ms）
3. 松开后按钮正常触发点击事件

**预期**：视觉上有"按下去"的实感，回弹顺滑无卡顿。

### Step 2 · 单选芯片（_RadioChip）

记忆 onboarding 中有"重要度"等单选芯片（待定/重要/最重要）。

1. **悬停鼠标** → 不应该有视觉变化（只在按下时反馈）
2. **按住某个芯片** → 缩小到 96%，松开回弹
3. **点击后状态切换** → 选中态应该有 amber 描边 + 微光阴影（已有行为）
4. **连续快速点击多个芯片** → 每次都有按下缩放，无卡顿

### Step 3 · 权值芯片（_WeightChip）

跟 _RadioChip 类似，但样式不同（更小、更圆润）。

1. 在记忆编辑器中找"轻/重"等权值芯片
2. 按住 → 缩放反馈

### Step 4 · 顶栏返回箭头（_TopBar）

进入任意二级页面（如 TextCustomPage / ChatPage），左上角的圆形返回按钮。

1. **悬停** → 不变化
2. **按住** → 整个圆形按钮（含箭头图标）缩小到 96%
3. **松开** → 回弹后执行 onBack

**预期**：返回按钮的反馈跟主按钮一致，都是缩放而非水波纹。

### Step 5 · 创建流程圆形图标按钮（_CustomButton）

SplashPage 底部"温柔/灵动"等 8 个圆形气质按钮。

1. **悬停** → 不变化（已有 boxShadow 静态发光）
2. **按住任意按钮** → 整个圆形（含图标 + 下方 label）缩小到 96%
3. **松开** → 回弹后触发 onTap

**预期**：缩放作用于整个 Column（圆形 + 文字标签），不是仅作用于圆形。这是有意的——避免文字标签脱离圆形浮动。

### Step 6 · Disabled 状态测试

某些按钮在条件不满足时是 disabled 状态（onTap=null）。比如 _PrimaryButton 没填完表单时灰显。

1. 找到任意 disabled 按钮（amber 灰掉的状态）
2. **按住** → **不应该有缩放反馈**（Pressable.enabled=false 时不响应触摸）
3. **松开** → 不触发任何事件

**预期**：disabled 状态完全无视觉反馈，避免误导用户。

### Step 7 · 回归测试（确认未改坏的）

1. **长按**（不是单击）某些按钮（如 _CustomButton）→ 不应该触发 onLongPress（除非组件单独支持）
2. **多指点击** → 不应该崩
3. **快速连续点击** → 不应该丢事件或卡死

---

## 验证清单

| # | 项 | 通过 | 备注 |
|---|---|---|---|
| 1 | _PrimaryButton 按下缩放 0.96 | ☐ | |
| 2 | _PrimaryButton 松手 150ms 内回弹 | ☐ | |
| 3 | _RadioChip 按下缩放反馈 | ☐ | |
| 4 | _WeightChip 按下缩放反馈 | ☐ | |
| 5 | _TopBar 返回箭头按下缩放 | ☐ | |
| 6 | _CustomButton 按下整个 Column 缩放 | ☐ | |
| 7 | disabled 按钮无缩放反馈 | ☐ | |
| 8 | 无 Material 水波纹（与 Lumora 调性匹配） | ☐ | |
| 9 | 长按不触发 onLongPress（除非组件支持） | ☐ | |
| 10 | `flutter analyze` 无新增 error | ☐ | |
| 11 | `flutter test memory_smoke_test.dart` 12/12 | ☐ | |

---

## 已知问题

1. **缩进不一致**：替换 GestureDetector → Pressable 后，原 Container 的 children 层级没有重新缩进。功能正确，但代码可读性下降。v2.2 全部完成后会做一次代码格式化（`flutter format`）。
2. **仅改 5 个组件**：其他 21 处 GestureDetector（如卡片、消息气泡、立绘）保持原样。v2.3 评估是否继续扩展。
3. **缩放作用于整个 widget**：如果组件内部有 boxShadow 或复杂装饰，缩放会作用于它们（_PrimaryButton 的琥珀色光晕会一起缩）。这是有意的——视觉一致性优先。

---

## 回退方案

```bash
git checkout HEAD~1 -- lib/main.dart
rm -rf lib/widgets/pressable.dart
```