# v2.2-C 自定义路由转场手动测试流程

> **改动概述**：新建 `FadeScaleRoute` 自定义路由（淡入 250ms + 微缩放 0.97→1.0，easeOutCubic），替代 8 处 `MaterialPageRoute`。退场 200ms easeInCubic。
>
> **改动文件**：
> - `lib/widgets/fade_scale_route.dart` — 新建，封装 PageRouteBuilder
> - `lib/main.dart` — 加 `import 'widgets/fade_scale_route.dart';`，全文 8 处 `MaterialPageRoute(` 替换为 `FadeScaleRoute(`
>
> **设计选择**：不做左右滑动，只做淡入 + 缩放——符合 Lumora"沉静"调性，避免"工具感"。

---

## 测试前准备

`flutter analyze` 通过 + `flutter test memory_smoke_test.dart` 12/12 通过（已验证）。

---

## 手动测试步骤

### Step 1 · SplashPage → 创建精灵流程

1. 启动 App → SplashPage
2. 点击底部"温柔" / "灵动" / "沉稳" / "清冷" / "阳光" / "文艺" / "酷飒" / "治愈" 任意气质卡片
3. 观察页面切换

**预期**：
- 进入 SpiritScenePage 是**淡入**（不是从右滑入）
- 整页有轻微的缩放（0.97→1.0），不是突变
- 总时长约 250ms，不超过 300ms

### Step 2 · 创建流程的多步切换

按 v2.1 README 截图流程依次点：

1. SplashPage → 选气质 → SpiritScenePage（破冰）
2. SpiritScenePage → 进入精灵 → NamePage（起名字）
3. NamePage → 填名字 → MemoryOnboardingPage（记忆 onboarding）
4. MemoryOnboardingPage → 完成 → ChatPage

**预期**：每一步都是淡入 + 微缩放，没有平台默认的左滑。

### Step 3 · 返回方向测试

进入任意二级页面，按左上角返回箭头。

**预期**：
- 返回也是淡出 + 微缩放（reverseTransitionDuration 200ms）
- 比入场略快（250ms → 200ms），避免"拖"
- 曲线反过来 easeInCubic（开头慢，收尾快）

### Step 4 · Hero 动画保留测试

SplashPage 卡片网格中的精灵立绘，通过 Hero 标签传到 SpiritScenePage。

1. 已有精灵的小卡片 → 立绘应该是同一张图
2. 进入 SpiritScenePage 时立绘应该有"飞过去"的过渡（Hero 动画）

**预期**：Hero 动画依然生效（FadeScaleRoute 不影响 Hero，因为 Hero 在 child 上，不在 transitions 上）。

### Step 5 · ChatPage 入口测试

1. SpiritScenePage → 点击立绘 → ChatPage
2. 进入聊天页的过渡

**预期**：也是淡入 + 微缩放。

### Step 6 · pushReplacement 测试

`_enterChat` 用了 `Navigator.pushReplacement`（不是 push）。验证替换后能否正确返回到上一层。

1. SpiritScenePage → ChatPage（pushReplacement）
2. 在 ChatPage 按系统返回键（如果 Windows 桌面有）

**预期**：行为正常，无"卡在 ChatPage 出不去"的问题。pushReplacement 路由栈正常弹栈。

### Step 7 · 节奏测试

连续快速切换多个页面。

1. SplashPage → 气质 → SpiritScenePage → 返回 → 选另一个气质 → ...
2. 快速点击 5-10 次

**预期**：
- 每次过渡都流畅
- 没有动画叠加导致的 jank
- 没有"上一个过渡还没结束下一个就开始"的视觉混乱

---

## 验证清单

| # | 项 | 通过 | 备注 |
|---|---|---|---|
| 1 | 创建流程入场淡入 250ms | ☐ | |
| 2 | 缩放 0.97→1.0 easeOutCubic | ☐ | |
| 3 | 返回淡出 200ms easeInCubic | ☐ | |
| 4 | Hero 动画仍生效（立绘连续） | ☐ | |
| 5 | pushReplacement 行为正常 | ☐ | |
| 6 | 快速切换无 jank | ☐ | |
| 7 | `flutter analyze` 无新增 error | ☐ | |
| 8 | `flutter test memory_smoke_test.dart` 12/12 | ☐ | |

---

## 已知问题

1. **Hero 位置偶有偏差**：如果 child widget tree 太深，Hero 动画的源/目标位置可能有轻微偏移（MaterialPageRoute 也有这问题，FadeScaleRoute 不引入新问题）。
2. **8 处替换**：未排除 dialog / showDialog 内部的 MaterialPageRoute（如果有）。dialog 一般不走 Navigator.push，不影响。
3. **未改 WebView 外的系统路由**：AlertDialog、showMenu 等仍用 Material 默认（这些是 modal，跟路由切换不同）。

---

## 回退方案

```bash
git checkout HEAD~1 -- lib/main.dart
rm -rf lib/widgets/fade_scale_route.dart
```