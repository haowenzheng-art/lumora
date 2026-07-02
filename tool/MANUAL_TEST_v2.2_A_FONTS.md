# v2.2-A 字体系统手动测试流程

> **改动概述**：接入 `google_fonts` 包，全局默认 Inter（西文/数字）+ 中文 fallback；情感性文本（Lumora logo + 产品口号）改用 Noto Serif SC（思源宋体），建立 `LumoraTextStyles` 字体系统。
>
> **改动文件**：
> - `pubspec.yaml` — 加 `google_fonts: ^6.2.1`
> - `lib/theme.dart` — 新建，定义 `LumoraTextStyles`（display / letter / body / caption / button）
> - `lib/main.dart` — `LumoraApp` 集成 `GoogleFonts.interTextTheme`；L290-L307 用 `LumoraTextStyles.displayStyle` / `letterStyle` 替换 Lumora logo + 口号
>
> **预期效果**：SplashPage 启动后，Logo "Lumora" 和产品口号 "陪你走过这段。然后，希望你不再需要我。" 应用思源宋体；其他文本保持系统字体（首次启动会有 1-3s 字体下载）。

---

## 测试前准备

1. **环境**：
   - Flutter SDK 已装（`C:\src\flutter\bin\flutter.bat`）
   - 中国镜像已配置（`PUB_HOSTED_URL` + `FLUTTER_STORAGE_BASE_URL`）
   - `agnes.txt` / `lumora.txt` / `voice.txt` 已就位（让 App 能跑通）

2. **首次启动**：
   ```bash
   flutter pub get     # 已跑过
   flutter analyze     # 已通过（2 个 pre-existing warning）
   flutter test test/memory_smoke_test.dart   # 已 12/12 通过
   ```

3. **清缓存**（让字体重新下载验证）：
   ```bash
   # 删除 google_fonts 缓存目录（如果存在）
   # Windows: C:\Users\<你>\AppData\Local\google_fonts
   ```
   （**不删除也行**，首次启动应用新字体本身就能验证）

---

## 手动测试步骤

### Step 1 · 启动 App，观察 SplashPage 字体变化

1. 在项目根运行：
   ```bash
   flutter run -d windows
   ```
2. **首次启动会卡 1-3 秒**（google_fonts 在下载 Noto Serif SC 字体的 ttf 文件），属于正常现象
3. App 启动到 SplashPage，**第一眼看到的**：
   - 顶部居中 "**Lumora**" 大字 → 应该是**思源宋体**（衬线感、有"印刷感"）
   - 下方两行小字 "陪你走过这段。" + "然后，希望你不再需要我。" → 也是**思源宋体**，但字号更小、字距更宽

**预期效果**：
- Logo 字形比改前**更有"庄重"感**（衬线笔画有粗细变化）
- 口号字距宽（letterSpacing 4），呼吸感强
- 如果还是系统默认（无衬线），说明字体下载失败，看 console 报错

**验证方法**：用截图工具截 SplashPage 启动后画面，肉眼对比 README 里 v2.1 的截图（应该字体明显不同）

### Step 2 · 启动页其他文本对比

1. 进入 SplashPage 主视图（已有精灵列表区）
2. 观察：
   - 已有精灵卡片标题（"温柔"、"小雨" 等名字）→ 系统字体（**不应该是思源宋体**，这些是功能性文本）
   - "选一只精灵" / "新建精灵" 按钮文字 → Inter（**现代无衬线**）

**预期**：只有"情感位"用衬线，其余保持系统字体或 Inter，对比清晰。

### Step 3 · 路由导航测试（不依赖其他改动）

1. 点击"新建精灵" → 进入 TextCustomPage
2. 观察：所有标题、按钮、表单 placeholder
3. 返回 → 回到 SplashPage

**预期**：路由切换流畅（暂时用平台默认），新字体在 TextCustomPage 也生效（因为 `interTextTheme` 是全局 ThemeData）。

### Step 4 · 错误兜底测试（验证字体不影响错误显示）

1. 故意把 `lumora.txt` 内容改坏（或备份后清空）
2. 重启 App → 走到聊天页
3. 触发一次对话（精灵消息尝试调 LLM）

**预期**：错误 snackbar / Toast 文字依然清晰可读，字体应用正确。

### Step 5 · 退出测试

1. 关闭 App
2. 再次启动

**预期**：第二次启动**几乎无延迟**（google_fonts 缓存了字体），字体立即显示。

---

## 验证清单

| # | 项 | 通过 | 备注 |
|---|---|---|---|
| 1 | SplashPage "Lumora" logo 用思源宋体 | ☐ | |
| 2 | SplashPage 口号用思源宋体 | ☐ | |
| 3 | 全局默认 Inter 西文字体生效 | ☐ | |
| 4 | 中文 fallback 不崩（系统字体兜底） | ☐ | |
| 5 | 首次启动有 1-3s 字体下载延迟（可接受） | ☐ | |
| 6 | 二次启动几乎无延迟 | ☐ | |
| 7 | `flutter analyze` 无新增 error | ☐ | |
| 8 | `flutter test memory_smoke_test.dart` 12/12 通过 | ☐ | |
| 9 | 错误兜底场景字体依然清晰 | ☐ | |
| 10 | 整体观感"产品级"了（vs 改前 demo） | ☐ | |

---

## 已知问题

1. **首次启动慢 1-3s**：google_fonts 下载 Noto Serif SC（~5MB）。可选优化：把字体打包到 `assets/fonts/`，但 v2.2 先不动。
2. **字体大小限制**：中文 ttf 完整包 5-10MB，google_fonts 会按需下载字符子集。如果某字符不在缓存里，下次仍可能重新下载。
3. **没有覆盖到 onboarding 标题**：A 阶段只改了 SplashPage logo + 口号，onboarding 各章节标题、final words 标题、Soul 自述还是系统字体。这些会在后续阶段（B/C/D/H）按需补充。

---

## 回退方案

如果测试发现问题要回退：

```bash
git checkout HEAD~1 -- pubspec.yaml lib/main.dart
rm -rf lib/theme.dart
flutter pub get
```

git 提交尚未 push 到 main，可以直接 reset。