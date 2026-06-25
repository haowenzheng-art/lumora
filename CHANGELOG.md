# Changelog

本项目的所有重要变更都会记录在此文件。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## [Unreleased]

### 计划中

- onboarding 仪式：精灵创建时引导 5-15 条核心记忆 + 用户印象 + "她最后想跟你说的话"
- 声音：TTS 语音输出
- 多精灵记忆隔离与跨精灵检索
- dormant 事件的"显式唤醒"机制

---

## [1.1.1] - 2026-06-26

### Fixed

- **自定义精灵 prompt 污染**：罗罗等自定义精灵之前会被套进小雨/明远身份（"半年前车祸""明远男友"），现在 `buildSystemPrompt` 区分 demo 小雨与自定义精灵，自定义精灵只使用用户在 App 里写的 profile + seed memories + 通用 Lumora 精灵 prompt。
- 新增 smoke test `[7/7] custom spirit prompt is isolated from Xiaoyu demo`，断言自定义精灵 prompt 不含 `明远`、`半年前车祸`、`半糖去冰`、`小雨（温柔）`。

---

## [1.1.0] - 2026-06-25

### Added

- **App 内 DIY 记忆与 profile onboarding**：用户不再需要手写 `Memory.md` / `profile.md`。
  - 新建精灵流程改为：`生成形象 → 起名字 → 让 ta 先认识你 → 进入房间`
  - 新增 `MemoryOnboardingPage`：填写 `ta 对你的整体印象`（写入 profile.md）+ 多条 `想让 ta 记住的事`（写入 seed events），每条支持标题、内容、标签、重要度（低/中/高）。
  - 默认 3 张空记忆卡，最多 15 张，可跳过。
- **聊天页记忆编辑入口**：`ChatPage` 顶栏右侧新增书本图标按钮，可随时打开记忆编辑页，修改 profile、新增/编辑/删除 seed memories，保存后下一轮对话检索自动生效。
- `MemoryService` 新增 UI 门面方法：`readProfile`、`writeProfile`、`listSeedEvents`、`replaceSeedEvents`、`buildSeedEvent`。

### Changed

- 编辑 seed memories 只替换 `source == seed` 的事件，聊天自动抽取的 `derived` 事件被完整保留。
- seed events 强制 `dormant=false` + `permadormant=true`，永不沉睡。

### Tests

- 新增 smoke test `[6/7] DIY memory/profile data layer`，覆盖 profile 读写、seed 替换、derived 保留。

---

## [1.0.0] - 2026-06-24

### Added

- **三层记忆系统**（核心特性）：
  - **L1 `profile.md`**：抽象印象，soft 400 / hard 1200 字，超 hard 按段落自动裁剪。
  - **L2 `events.jsonl`**：具体事件，seed（onboarding 注入，permadormant）+ derived（聊天提取）。
  - **L3 `messages.jsonl`**：原始对话流水。
- **检索策略**（锚定人脑认知科学）：
  - tag 预筛（seed + active derived）
  - weight + recency 砍到 ≤ 40 条候选
  - LLM rerank 选 top-K 进 prompt
  - 默认 K=5（Cowan 工作记忆 4±1 + 扩散激活 3-7 节点，最像人）
  - 深度 K=8（用户主动回忆/长消息/连续同话题时启用，超越人脑生理极限）
  - 深度模式触发信号：回忆动词（"还记得"/"上次"/"那时候"/"以前"）/ 消息 > 60 字 / 连续 3 轮同话题
- **自动归档**：每 6 轮 user 消息后台触发 LLM 抽取，从最近 24 条对话提取事件 + 更新 profile。
- **遗忘机制**：active derived 超 soft 200 时按 `weight × recency × usedBoost` 综合分标 dormant，超 hard 500 强压到 180。seed 永不沉睡。
- **Memory.md 一次性迁移**：首次进入小雨房间时，把静态 `agent_data/xiaoyu/Memory.md` 解析为 seed events 入库。
- `MemoryService` 门面：`appendUserMessage`、`appendAssistantMessage`、`retrieveForPrompt`、`maybeRunBackgroundTasks`、`seed`、`hasSeedAlready`。
- 动态 system prompt：每轮对话按需检索记忆注入，不再硬编码整篇 Memory.md。

### Changed

- `buildSystemPrompt({String? dynamicMemory})` 接受动态记忆，无则回退到读 Memory.md。
- `ChatPage` 消息持久化改走 `MemoryService`，路径不变（`<docs>/Lumora/agents/<spirit>/messages.jsonl`）。

### Tests

- 新增 `test/memory_smoke_test.dart`：5 项端到端测试覆盖 Store 读写、Memory.md 解析、Retriever tag 预筛、深度模式分类、Decay 沉睡机制。

---

## [0.3.0] - 2026-06-23

### Added

- **图层分解 + 眨眼动画**（`lib/sprite_parts.dart`、`lib/sprite_view.dart`）：
  - 纯 Dart `image` 包在后台 isolate 把眼睛区域切成独立透明层。
  - 径向 smoothstep alpha 羽化，边缘自然融入。
  - 眨眼：间隔 2800ms + rand(0-2200ms)，闭/睁各 70ms，10% 双眨眼。
  - 调试可视化开关 `kShowPartsDebugBox`，每精灵 override 机制。
- **双 player 无缝循环视频**（`lib/loop_video_view.dart`）：
  - 两个 Player 错位播放 idle，尾部 450ms 交叉淡入，消除 5s 视频循环接缝。
  - 支持一次性 reaction 视频（淡入播完再淡回 idle）。
- **多 tag 视频缓存**：`<spiritId>_idle.mp4` / `<spiritId>_reaction.mp4`。
- `defaultReactionVideoPrompt`：被注视/被点到的轻微反应。

### Notes

- 用户评估后认为图层分解的 2.5D 效果上限不够，v1.0 起 pivot 到预生成视频方案（Path C）。图层代码保留作为 fallback。

---

## [0.2.0] - 2026-06-22

### Added

- **Agnes 图生视频集成**：
  - `createImageToVideoTask` + `queryVideoTask` + `pollVideoUntilDone` 轮询。
  - 默认 idle / reaction 双 prompt。
- **SpiritScenePage 视频生成与缓存**：进入房间时检查缓存，缺失则并行生成 idle + reaction。
- **聊天页 reaction 触发**：鼠标进入精灵区域时触发 reaction 视频，8 秒冷却。
- 危机拦截 `[[CRISIS_BREAK]]` 标记 + `quickProbe` 快速响应。

---

## [0.1.0] - 2026-06-22

### Added

- Flutter Windows desktop app 骨架。
- **文生图**（`generateSpriteFromText`）：性别 + 气质 + 风格（阳光/清冷/暖）+ 画质后缀。
- **图生图**（`generateSpriteFromPhoto`）：照片转日漫半身立绘，保留人物特征。
- **精灵索引**：`sprites_index.json` 持久化，支持删除（同步清理视频缓存）。
- **聊天页**：`ChatPage` + 消息持久化（messages.jsonl）+ 历史加载。
- **小雨 demo**：`agent_data/xiaoyu/` 含 Soul.md / Memory.md / Boundaries.md。
- **宪法**（`CONSTITUTION.md`）与**记忆行为文档**（`docs/MEMORY_BEHAVIOR.md`）。

---

[Unreleased]: https://github.com/haowenzheng-art/lumora/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/haowenzheng-art/lumora/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/haowenzheng-art/lumora/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/haowenzheng-art/lumora/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/haowenzheng-art/lumora/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/haowenzheng-art/lumora/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/haowenzheng-art/lumora/releases/tag/v0.1.0
