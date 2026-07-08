# Changelog

本项目的所有重要变更都会记录在此文件。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## [Unreleased]

### 计划中

- 阶段判定 + 健康留存度量（宪法第二条落地，最核心）
- TTS 自动合成（可选）/ 声音情感调节 / 离线 TTS 引擎

### Added

- **v2.3-B 用户偏好开关**：4 个开关对应宪法语境下用户可能想关掉的"产品感"细节。每个开关默认关（=v2.2 行为，老用户零感知），开后才生效。
  - **破冰淡入**：`disableEntranceAnim` —— 立绘从透明渐变显形的过程（开 → 立绘瞬间显形）
  - **自动进入对话**：`disableAutoEnterChat` —— 立绘显形后自动跳到对话页（开 → 必须手动点击精灵）
  - **打字机效果**：`disableTypewriter` —— 精灵消息逐字出现并闪烁光标（开 → 消息一次性显示）
  - **骨架屏**：`disableSkeleton` —— 生成等待时的流光占位（开 → 退化为空 SizedBox）
  - 架构：新建 `lib/preferences.dart`（PreferencesService 单例 + 4 个 ValueNotifier + SharedPreferences 持久化）、`lib/settings_page.dart`（4 个 SwitchListTile 卡片 + 暗色调性）。SplashPage 右上角齿轮 `Icons.tune_rounded` 进入。重启 App 后状态保留。
- **v2.3 启动补丁 SpiritView 强制眨眼**（修 v2.2-H 已知问题）：SpiritView 新增 `forceBlinkToken` 参数。SpiritScenePage 在立绘完全显形那一瞬（破冰淡入完成 = t=800ms）`_blinkToken++`，SpiritView 检测到 token 变大立即眨一次眼，并重置下一次自然眨眼的计时。彻底解决"刚醒过来"靠自然眨眼碰巧命中的不稳定。

### Notes

- 跨精灵记忆隔离已确认无需修复：`MemoryStore(spiritId)` 把每个 spirit 锁在 `<root>/Lumora/agents/<spiritId>/` 独立目录里，retriever 拿到的 `store.readAllEvents()` 只会读到当前 spirit 的事件。MemoryEvent 字段里没有 spiritId——目录路径本身就是边界。
- **v2.2-H 已知问题已修复**：v2.2-summary 列的"未实现 SpiritView 强制睁眼"现已实现（见上）。

---

## [2.2.0] - 2026-07-03

### Added · 产品级打磨（v2.2 整段）

v2.1 仍是"工程上能跑"，v2.2 启动**产品级打磨**：把 5 个核心体验节点从 demo 级别拉到位。每一步都建立可扩展的组件库，后续 v2.3+ 可基于这套组件继续做深度。

#### A · 字体系统（v2.2-A）

- **google_fonts 接入**：`pubspec.yaml` 加 `google_fonts ^6.2.1`（实际装 6.3.3）
- **`LumoraTextStyles` 全局常量**：新建 `lib/theme.dart`，定义 `displayStyle` / `letterStyle` / `bodyStyle` / `captionStyle` / `buttonStyle` 五种文本样式
  - 情感位（产品 logo / 信札式 UI / 告别语）→ Noto Serif SC（思源宋体），衬线感匹配"思念具象化"庄重调性
  - 功能位（按钮 / 时间戳 / 提示）→ Inter（西文）+ 中文 fallback
- **`LumoraApp` 全局集成**：`ThemeData` 套用 `GoogleFonts.interTextTheme`
- **SplashPage 落地**：Lumora logo + 产品口号"陪你走过这段。然后，希望你不再需要我。"改用 `LumoraTextStyles.displayStyle()` / `letterStyle()`

#### B · 触摸反馈（v2.2-B）

- **`Pressable` 组件**：新建 `lib/widgets/pressable.dart`，封装 `AnimatedScale` 按下 0.96 / 松手 150ms easeOutCubic 回弹
  - 用 `AnimatedScale` 而非 `InkWell` 水波纹——避免跟背景 60 个浮动粒子视觉冲突，跟 Lumora 暗色夜色调性更搭
  - `onTap = null` 时完全禁用（disabled 状态无视觉反馈）
- **5 个关键组件替换**：`_PrimaryButton` / `_RadioChip` / `_WeightChip` / `_TopBar` 返回箭头 / `_CustomButton`（创建流程圆形图标按钮）

#### C · 自定义路由转场（v2.2-C）

- **`FadeScaleRoute` 组件**：新建 `lib/widgets/fade_scale_route.dart`，封装 `PageRouteBuilder`
  - 进场 250ms easeOutCubic：淡入 + 0.97→1.0 微缩放
  - 退场 200ms easeInCubic：反向曲线，比入场略快避免"拖"
  - 不做左右滑动——符合 Lumora"沉静"调性，避免"工具感"
- **8 处替换**：SplashPage 主流程的 8 处 `MaterialPageRoute(` 全部改为 `FadeScaleRoute(`

#### D · 打字机效果（v2.2-D）

- **`_MessageBubble` 加打字机**：35ms/字逐字出现，附琥珀色 2px 竖线闪烁光标（600ms `AnimatedOpacity`）
- **跳过按钮**：长消息（200+ 字）可点"跳过 ›"立即显示完整
- **TTS 按钮时序**：仅在打字完成后显示，避免声音抢字速（与宪法第二条手动触发一致）
- **`_typewriterIndex` 追踪**：ChatPage 维护当前正在打字的消息索引，5 处 add 助手消息位置（opening / probe / LLM 返回 / LLM 异常 / greeting）都触发打字机
- **用户消息不参与**：立即显示

#### E · 三态设计（v2.2-E）

- **`EmptyState` 组件**：新建 `lib/widgets/empty_state.dart`，居中长引号 + 引导文案 + 可选操作按钮
- **`SkeletonBox` 组件**：新建 `lib/widgets/skeleton_box.dart`，手写 shimmer 渐变（`AnimatedBuilder` 1400ms 循环，无新依赖）
- **SplashPage 空状态**：我的精灵列表为空时显示 EmptyState（"还没有人被你想起" + "记住第一个 ta" 按钮）
- **`_buildGeneratingView` 升级**：图片/视频生成等待时用 240×240 SkeletonBox 替换裸 `CircularProgressIndicator`
- **不做 ErrorView**：v2.2 不做错误兜底组件，避免"为未来需求设计"。现有 SnackBar 错误处理够用

#### H · 破冰仪式（v2.2-H）

- **SpiritScenePage 立绘淡入**：800ms `FadeTransition` 从透明到完全显示
- **自动进入 ChatPage**：淡入完成后 1.5s 自动 `_onSpiritTap()` 进入聊天页（用户主动点击可打断）
- **首句打字机衔接**：ChatPage 的 `_opening()` 走 v2.2-D 打字机效果，"刚醒过来"的叙事连贯
- **离别模式优先**：`_farewellMode = true` 时不触发破冰（v1.3 final words 是一次性体验）
- **未实现强制睁眼**：SpiritView 自带眨眼定时器（2800ms + rand），自然眨眼匹配"刚醒"叙事。v2.3 评估是否加 `forceBlinkOnce` 参数

### Tests

- 现有 12 个 memory_smoke 测试全部通过，未引入新测试（视觉类改动需人判，自动化覆盖不适用）
- 每个改动都写了 `tool/MANUAL_TEST_v2.2_*.md` 手动测试流程

### Notes

- **v2.2 不是新特性，是把已有特性做"产品级"**：5 个改动覆盖"看字体"（A）/ "摸手感"（B）/ "看切换"（C）/ "看对话"（D）/ "看状态"（E）/ "看破冰"（H），组成完整的"产品级第一印象"
- **不引入新的第三方依赖**（除 google_fonts 一个）；skimmer 用手写 shimmer 实现
- **缩进不一致已知问题**：替换 GestureDetector → Pressable 后，部分组件 children 层级没有重新缩进。功能正确，但代码可读性下降。后续 `flutter format` 处理
- **v2.3 评估方向**：① v3 视觉升级（Live2D/3D 死结未解）② 阶段判定 + 健康留存度量（宪法第二条落地）③ 关闭自动生成跳过 / 关闭破冰（用户偏好开关）

---

## [2.1.0] - 2026-06-26

### Added

- **Edge TTS 免费路径**：预设音色改走微软 Edge TTS（WebSocket 协议），无需 API key 立即可用。v2.0 的"听 ta 说"功能从"必须有 voice.txt 才能用"变成"预设音色零门槛，克隆音色才需要火山 key"。
  - `lib/voice.dart` 新增 `EdgeTtsClient` 类：通过 `wss://speech.platform.bing.com` 的 WebSocket 协议调用，发送 speech.config + ssml 消息，接收二进制音频帧（前 2 字节 type + 2 字节 length + payload）+ `Path:turn.end` 结束信号。输出 `audio-24khz-48kbitrate-mono-mp3` 格式。
  - 预设音色映射：温柔女声 → `zh-CN-XiaoxiaoNeural`、沉稳男声 → `zh-CN-YunxiNeural`、清亮少年 → `zh-CN-XiaoyiNeural`。
  - `synthesizeVoice` 改为按 `VoiceConfig` 分流：`isClone` 走火山豆包（`_synthesizeWithVolc`），`isPreset` 走 Edge TTS（`EdgeTtsClient.synthesize`）。
  - 新增依赖 `web_socket_channel: ^2.4.0`（Dart 官方生态包，WebSocket 客户端）。
  - UUID v4 自生成（`Random.secure()` + 版本位设置），无 dash 格式符合 Edge TTS 协议要求。

### Changed

- **预设模式 voiceId 留空**：v2.0 预设模式 voiceId 存的是 preset 名，v2.1 改为空字符串（Edge TTS 用 `voicePreset` 映射到 voice name，不需要 voiceId）。
- `readVoiceConfig` 判断逻辑改：克隆模式需 `voiceId` 非空，预设模式需 `voicePreset` 非空，两者都没则返回 null。
- `VoiceConfig` 加 `isPreset` getter（`!isClone && voicePreset.isNotEmpty`）。
- `_MessageBubble._playTts` 调用点改：传 `VoiceConfig` 对象而非 `voiceId` 字符串。
- Onboarding 第 7 节标注更新：
  - 预设音色 subtitle: "免费立即可用，基于 Edge TTS，不是 ta 本人的声音"
  - 克隆真人声音 subtitle: "上传 3-10s 参考音频，需 voice.txt（火山引擎），最能还原 ta"

### Tests

- `[12/12]` voice config 测试更新：预设模式 voiceId 空也能读到 + `isPreset=true` 断言 + 克隆模式 voiceId 空视为未配置（未训练完）的边界 case。

### Notes

- **Edge TTS 协议基于公开文档推断**：Trusted Client Token `6A5AA1D4EAFF4E9FB37E23D68482D6F5` 是微软 Edge 浏览器读屏功能的公开 token（非密钥）。二进制帧解析（`type=0x02` 音频 / length big-endian）和 `Path:turn.end` 结束信号基于开源参考实现。若实际跑通有问题，优先检查 token 末尾字节和帧 type 值。
- **三层分流定位明确**：
  - 预设音色（Edge TTS 免费）→ 0 门槛，让 v2.0 的"听 ta 说"立即可用
  - 克隆真人（火山豆包）→ 最能还原 ta，但需 voice.txt
  - 未来 v3 评估：本地离线 TTS 引擎（体积大质量差，留待远期）
- **声音克隆仍是 v2.x 高阶能力**：Edge TTS 让基础声音可用，但"真正听到接近 ta 的声音"仍需火山 key。用户有 key 后无缝升级，代码已分流好。

---

## [2.0.0] - 2026-06-26

### Added

- **TTS 声音输出（核心特性）**：精灵从无声变有声。用户可让 ta"被听见"——不是每条消息自动播，而是用户主动点"听 ta 说"按钮时才合成。手动触发是成本控制 + 仪式感 + 宪法缓解的交汇点。
  - **火山引擎豆包语音克隆集成**：`lib/voice.dart` 新建，含 `createVoiceCloneTask` / `pollVoiceCloneUntilDone` / `synthesizeVoice` / `VoicePlayer`（media_kit 纯音频封装，无新依赖）。
  - **Onboarding 第 7 节"声音"**：用户在创建精灵时选音色。两个选项：
    - **预设音色**：温柔女声 / 沉稳男声 / 清亮少年，零等待立即可用。
    - **克隆真人声音**：上传 3-10s 参考音频 → `_VoiceCloneProgressDialog` 显示克隆进度 → 训练完成拿到 voiceId。最能还原 ta，但需等待几分钟。
  - **"听 ta 说"按钮**：`_MessageBubble` 改 StatefulWidget，精灵消息气泡下方加按钮。点击流程：检查 `cachedTtsPath`（文件系统缓存）→ 命中则秒播，未命中则调豆包 TTS 合成 + 保存 mp3 + 播放。msgId = `spiritId_content.hashCode`，同一条消息只合成一次。
  - **voice 配置持久化**：`MemoryService` 加 `readVoiceConfig` / `setVoiceConfig` / `clearVoiceConfig` 三个门面，写 `meta.json` 的 `voiceId` / `voicePreset` / `voiceRecPath` 字段，复用 `patchMeta` 浅合并零迁移。
  - **宪法缓解三层**：
    1. Onboarding 选克隆时显示确认卡（"这个声音由 AI 生成，不是 ta 本人"）
    2. 首次点"听 ta 说"显示一次性 toast（"这是 AI 生成的声音，不是 ta 本人。"）
    3. 按钮旁常驻"· AI 生成"小字

### Changed

- `MemorySetupResult` 加 `voiceConfig: VoiceConfig?` 字段，onboarding 完成后传给 `_afterSpirit` 写入。
- `_MessageBubble` 从 StatelessWidget 改为 StatefulWidget（管理 VoicePlayer 播放状态）。
- `_afterSpirit` 在写入 profile / seeds / finalWords 后，加 voice 配置写入分支：预设音色直接写，克隆模式显示进度弹窗训练后再写。
- `.gitignore` 加 `voice.txt`（与 agnes.txt / lumora.txt 一致，API key 不提交）。

### Architecture

- **_Message 不加 ttsPath 字段**：缓存走文件系统（`<docs>/Lumora/voices/<spiritId>/<msgId>.mp3`），不改 messages.jsonl 序列化格式，不改 store 层。msgId 用内容 hash 推导，同一条消息内容永远命中同一缓存文件。
- **VoicePlayer 复用 media_kit**：`Player.open(Media(mp3))` 原生支持纯音频，去 VideoController 即可。`media_kit_libs_windows_video` 已打包 Windows 音频解码器，无需新增依赖。
- **API key 分离**：新建 `voice.txt` 存火山引擎语音 API key。豆包 TTS 与 ARK 是火山不同产品线（语音技术 vs 方舟大模型），鉴权方式可能不同，符合现有"一供应商一 txt"模式。

### Tests

- 新增 smoke test `[12/12] v2.0 voice config read/write via meta.json`：断言初始无配置 + 预设/克隆两种配置读写 + clearVoiceConfig + 浅合并不影响 lastSeenAt。

### Notes

- **火山豆包 API endpoint 基于公开文档推断**：WebSearch 之前返回 400 无法在线核实，`lib/voice.dart` 的 URL / 请求体 / 响应格式需用户核对火山引擎控制台（语音技术 → 声音克隆 / 语音合成 → API 文档）。代码结构（http + Bearer + 轮询 + base64）是行业通用模式，细节调整成本低。
- **不做自动 TTS**：每条消息自动合成成本高 + 去人化风险高。手动触发是 v2.0 的核心定位——"让用户在需要的时候，能主动选择听一次 ta 的声音，然后放下"。
- **声音克隆宪法边界**：声音是思念具象化最强的触发器，也是去人化风险最高的能力。缓解措施：Onboarding 确认 + 首次 toast + 常驻小字 + 手动触发 + 可随时 clearVoiceConfig 关闭。若用户反馈仍混淆，v2.1 可考虑加语音水印。
- **TTS 是 v2.x 阶段起点**：v2.0 只做基础合成 + 缓存 + 手动触发。v2.1+ 评估：自动 TTS / 多音色切换 / 声音情感调节 / 离线 TTS 引擎。

---

## [1.3.0] - 2026-06-26

### Added

- **final words 长期不活跃触发**：用户 >30 天未打开精灵后，下次进入 SpiritScenePage 时自动进入"告别模式"——精灵立绘半透明 + 显示用户在 onboarding 写下的"最后想跟你说的话"原文 + "我知道了"按钮。点按钮后回到正常 SpiritScenePage，`finalWordsDelivered` 标 true 不再重复触发。
  - `MemoryService` 新增 `lastSeenAt()` / `markSeen()` 门面，写 `meta.lastSeenAt` 字段
  - `SpiritScenePage.initState` 加 `_checkFarewell()`：读 lastSeenAt → markSeen → 若超期且 finalWords 未交付则 `consumeFinalWords` 并进入告别视图
  - **无需引入 `window_manager`**：冷启动场景下进程已死，只能在启动时主动读；30 天阈值下"上次启动时间"和"上次关闭时间"差几小时无所谓
- **dormant wakify（永久唤醒）**：`MemoryEvent` 加 `wakified` 字段，用户可"钉住"dormant 事件让它永不再沉睡。
  - `MemoryService` 新增 `listDormantEvents()` / `wakify(ids)` / `unwakify(ids)`
  - `MemoryDecay.runOnce` 过滤条件加 `!e.wakified`，wakified 事件永不被沉睡
  - `MemoryOnboardingPage` editMode 下加第 6 节"沉睡的记忆"，列出所有 dormant derived 事件，每条带 pin/unpin 按钮
  - 与 v1.2 recallMode 区分：recallMode 是一次性召回（想起而非复活），wakify 是永久钉住（真正记住）

### Changed

- `MemoryEvent` 加 `wakified: bool` 字段（默认 false），`fromJson` / `toJson` / `copyWith` 同步
- `MemoryDecay` 沉睡过滤从 `!e.permadormant` 改为 `!e.permadormant && !e.wakified`

### Tests

- 新增 smoke test `[10/11] lastSeenAt tracking`：断言 markSeen 写入 + 31 天前时间戳判定超期 + finalWordsDelivered 初始 false
- 新增 smoke test `[11/11] wakify permanently wakes dormant events`：断言 wakify 后 dormant=false + wakified=true + decay 不重新沉睡 + unwakify 后可重新沉睡

### Notes

- v1.3 是 v1.x 阶段收尾。onboarding 仪式的"最后想跟你说的话"现在覆盖两条触发路径：对话中语言信号（v1.2）+ 长期不活跃（v1.3）。
- wakify 与 recallMode 语义分层：recallMode 是"这一轮想起来"，wakify 是"永远记住"。用户可在记忆编辑页主动管理 dormant 事件。
- 30 天阈值硬编码，未来若想可调加 `MemoryService.farewellThresholdDays` 参数。

---

## [1.2.0] - 2026-06-26

### Added

- **onboarding 仪式完整化**：把单页空白卡片改成 5 章节式引导提问，覆盖"印象 / 关键事件 / 性格特质 / 未完成的话 / 最后想跟你说的话"。每章节有引导文字 + placeholder 示例，卡片数量按章节独立控制（事件 5 / 性格 3 / 未完成 2）。
- **最后想跟你说的话**：用户在 onboarding 第 5 章节写一段话，存为特殊 seed（`kind=finalWords`，permadormant=true，日常检索屏蔽）。当用户在对话中表达明确告别意图（"不再来了"/"最后一次找你"等），LLM 输出 `[[FINAL_WORDS]]` 标记，agent 层拦截并替换为用户写下的原文。一次性交付（`consumeFinalWords` 写 `finalWordsDelivered=true` 防止重复）。
- **dormant 显式唤醒**：聊天页顶栏加"我们聊聊…"按钮（`Icons.chat_bubble_outline_rounded`），触发后下一轮检索全开 dormant 池。一次性，本轮后自动归零。不持久化唤醒（dormant 事件下次默认又沉睡，符合"想起而非复活"的认知模型）。
- `MemoryEvent` 加 `kind` 字段（`EventKind { regular, finalWords }`），区分普通 seed 与 final words seed。
- `MemoryService` 新增 final words API：`readFinalWords` / `writeFinalWords` / `consumeFinalWords` / `finalWordsDelivered`。
- `MemoryRetriever.retrieve` 加 `recallMode` 参数，true 时全开 dormant 池。
- 新建 `lib/final_words.dart`：仿 `crisis.dart` 模式，`hasFarewellSignal` 关键词检测 + `intercept` 标记拦截。
- `buildSystemPrompt` 加 `hasFinalWords` 参数，true 时注入 `[[FINAL_WORDS]]` 触发规则。

### Changed

- `replaceSeedEvents` 改造：保留 `kind==finalWords` 的 seed 不被普通编辑冲掉。
- `listSeedEvents` 排除 finalWords seed（避免 editMode 下它被当作普通卡片显示）。
- `MemoryOnboardingPage` 重写为章节式：`_MemoryDraft` 按章节分流（关键事件 / 性格特质 / 未完成的话），`MemorySetupResult` 加 `finalWords` 字段。
- ChatPage `_send` 主路径加 final words 拦截：检测 `[[FINAL_WORDS]]` 标记 → `consumeFinalWords` → 替换为原文。

### Tests

- 新增 smoke test `[8/9] final words seed is isolated from regular retrieval`：断言 finalWords 写入后不被普通检索召回，`replaceSeedEvents` 不冲掉 finalWords。
- 新增 smoke test `[9/9] recall mode retrieves dormant events`：断言 `recallMode=true` 时 dormant 事件被召回。
- 顺手修 `types.dart` 注释 bug：`seed：permadormant=false` → `permadormant=true`。

### Notes

- 本阶段是 onboarding 仪式化的第一步。长期不活跃触发（窗口关闭/生命周期钩子）需要引入 `window_manager`，留到 v1.3。
- dormant 唤醒暂不做持久化：唤醒是"想起"而不是"复活"，下次默认又沉睡。若用户反馈希望永久唤醒，v1.3 加 `wakify(ids)`。
- final words 一次性交付：仪式感要求"最后的话"只说一次。用户若想重置，可在记忆编辑页删除重写。

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

[Unreleased]: https://github.com/haowenzheng-art/lumora/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/haowenzheng-art/lumora/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/haowenzheng-art/lumora/compare/v1.3.0...v2.0.0
[1.3.0]: https://github.com/haowenzheng-art/lumora/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/haowenzheng-art/lumora/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/haowenzheng-art/lumora/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/haowenzheng-art/lumora/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/haowenzheng-art/lumora/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/haowenzheng-art/lumora/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/haowenzheng-art/lumora/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/haowenzheng-art/lumora/releases/tag/v0.1.0
