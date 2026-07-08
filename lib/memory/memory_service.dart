import 'dart:async';
import 'dart:io';

import '../voice.dart';
import 'decay.dart';
import 'extractor.dart';
import 'retriever.dart';
import 'stage_classifier.dart';
import 'store.dart';
import 'types.dart';

/// 记忆系统对外门面 v1.0
///
/// 设计目标：聊天页只跟它打交道，内部协调 store / extractor / retriever / decay。
///
/// 用法：
///   final mem = MemoryService(spiritId: 'xiaoyu');
///   await mem.appendUserMessage(text);          // 用户消息落 L3
///   final r = await mem.retrieveForPrompt(text); // 检索 → 渲染
///   await mem.appendAssistantMessage(reply);    // assistant 消息落 L3
///   mem.maybeRunBackgroundTasks();              // 后台异步：抽取 + 遗忘
class MemoryService {
  final String spiritId;
  final MemoryStore store;
  final MemoryExtractor extractor;
  final MemoryRetriever retriever;
  final MemoryDecay decay;

  /// v2.3-C：会话级阶段推断器（从最近 N 条对话推断用户当前阶段）
  final StageClassifier stageClassifier;

  bool _busy = false;

  MemoryService({
    required this.spiritId,
    int extractEveryNTurns = 6,
    int normalK = 5,
    int deepK = 8,
    int activeSoftLimit = 200,
    int activeHardLimit = 500,
    Directory? baseDirOverride,
  })  : store = MemoryStore(spiritId, baseDirOverride: baseDirOverride),
        extractor = MemoryExtractor(
          store: MemoryStore(spiritId, baseDirOverride: baseDirOverride),
          extractEveryNTurns: extractEveryNTurns,
        ),
        retriever = MemoryRetriever(
          store: MemoryStore(spiritId, baseDirOverride: baseDirOverride),
          normalK: normalK,
          deepK: deepK,
        ),
        decay = MemoryDecay(
          store: MemoryStore(spiritId, baseDirOverride: baseDirOverride),
          softLimit: activeSoftLimit,
          hardLimit: activeHardLimit,
        ),
        stageClassifier = StageClassifier(
          store: MemoryStore(spiritId, baseDirOverride: baseDirOverride),
        );

  Future<void> appendUserMessage(String content) async {
    await store.appendMessage(RawMessage(
      role: 'user',
      content: content,
      ts: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> appendAssistantMessage(String content) async {
    await store.appendMessage(RawMessage(
      role: 'assistant',
      content: content,
      ts: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 检索当前 user 消息相关的记忆（含 profile）
  ///
  /// recallMode=true 时召回 dormant 池（用户主动触发回忆模式）。
  Future<RetrievalResult> retrieveForPrompt(
    String userMessage, {
    bool recallMode = false,
  }) async {
    final recent = await store.readRecentMessages(12);
    return retriever.retrieve(
      userMessage: userMessage,
      recentMessages: recent,
      recallMode: recallMode,
    );
  }

  /// 后台任务（抽取 + 维护）。不 await，自己异步跑；并发保护避免重入。
  void maybeRunBackgroundTasks() {
    if (_busy) return;
    _busy = true;
    Future(() async {
      try {
        if (await extractor.shouldRunNow()) {
          await extractor.runOnce();
        }
        // v2.3-C：阶段推断——每 N 轮 user 消息触发，写 meta.currentStage
        // 注意：必须在 extractor 之后跑（这样这次抽取的 events 能拿到最新 stage）
        if (await stageClassifier.shouldRunNow()) {
          await stageClassifier.runOnce();
        }
        await decay.runOnce();
      } catch (_) {
        // 静默吞掉，不能影响聊天主路径
      } finally {
        _busy = false;
      }
    });
  }

  /// v2.3-C：读当前会话阶段（null = 未触发推断或推断失败）
  /// C-2 健康留存度量 + C-3 UI 接入都消费这个。
  Future<StageClassification?> currentStage() => stageClassifier.readLast();

  /// 读取 L1 profile
  Future<String> readProfile() => store.readProfile();

  /// 写入 L1 profile
  Future<void> writeProfile(String profile) => store.writeProfile(profile.trim());

  /// 读取所有 seed events（用户显式设定的初始记忆，不含 finalWords）
  Future<List<MemoryEvent>> listSeedEvents() async {
    final all = await store.readAllEvents();
    return all
        .where((e) =>
            e.source == EventSource.seed && e.kind != EventKind.finalWords)
        .toList();
  }

  /// 替换 seed events，保留 derived events 与 finalWords seed 不动。
  Future<void> replaceSeedEvents(List<MemoryEvent> events) async {
    final all = await store.readAllEvents();
    // 保留：derived 事件 + finalWords seed（不被普通编辑冲掉）
    final keep = all
        .where((e) => e.source != EventSource.seed || e.kind == EventKind.finalWords)
        .toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    final hardened = events
        .where((e) => e.summary.trim().isNotEmpty)
        .map((e) => e.copyWith(
              id: e.id.isEmpty ? MemoryStore.newId() : e.id,
              source: EventSource.seed,
              kind: EventKind.regular,
              title: e.title.trim().isEmpty
                  ? _fallbackTitle(e.summary)
                  : e.title.trim(),
              summary: e.summary.trim(),
              tags: e.tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
              weight: _normalizeWeight(e.weight),
              createdAt: e.createdAt == 0 ? now : e.createdAt,
              dormant: false,
              permadormant: true,
            ))
        .toList();
    await store.rewriteAllEvents([...keep, ...hardened]);
  }

  /// 构造一条 seed event，供 onboarding/editor UI 使用。
  MemoryEvent buildSeedEvent({
    String id = '',
    String date = '',
    String title = '',
    required String summary,
    List<String> tags = const [],
    String weight = '中',
    int createdAt = 0,
    EventKind kind = EventKind.regular,
  }) {
    final now = DateTime.now();
    final dateText = date.trim().isEmpty
        ? '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        : date.trim();
    return MemoryEvent(
      id: id.isEmpty ? MemoryStore.newId() : id,
      source: EventSource.seed,
      kind: kind,
      date: dateText,
      title: title.trim().isEmpty ? _fallbackTitle(summary) : title.trim(),
      summary: summary.trim(),
      tags: tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      weight: _normalizeWeight(weight),
      createdAt: createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : createdAt,
      lastUsedAt: 0,
      dormant: false,
      permadormant: true,
    );
  }

  // ============ Final Words API（v1.2） ============

  /// 读取 finalWords seed（若有）。返回 null 表示用户没写过。
  Future<MemoryEvent?> readFinalWords() async {
    final all = await store.readAllEvents();
    for (final e in all) {
      if (e.kind == EventKind.finalWords) return e;
    }
    return null;
  }

  /// 写入或覆盖 finalWords seed。text 为空则删除已有 finalWords。
  Future<void> writeFinalWords(String text) async {
    final trimmed = text.trim();
    final all = await store.readAllEvents();
    final withoutFinal = all.where((e) => e.kind != EventKind.finalWords).toList();
    if (trimmed.isEmpty) {
      await store.rewriteAllEvents(withoutFinal);
      return;
    }
    final existing = all.firstWhere(
      (e) => e.kind == EventKind.finalWords,
      orElse: () => MemoryEvent(
        id: MemoryStore.newId(),
        source: EventSource.seed,
        kind: EventKind.finalWords,
        date: '',
        title: '最后想跟你说的话',
        summary: '',
        tags: const ['最后的话'],
        weight: '高',
        createdAt: 0,
        lastUsedAt: 0,
        dormant: false,
        permadormant: true,
      ),
    );
    final now = DateTime.now();
    final dateText = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final updated = existing.copyWith(
      summary: trimmed,
      createdAt: existing.createdAt == 0
          ? DateTime.now().millisecondsSinceEpoch
          : existing.createdAt,
      date: existing.date.isEmpty ? dateText : existing.date,
      dormant: false,
      permadormant: true,
    );
    await store.rewriteAllEvents([...withoutFinal, updated]);
  }

  /// 是否已交付过 final words（一次性标志）。
  Future<bool> finalWordsDelivered() async {
    final meta = await store.readMeta();
    return (meta['finalWordsDelivered'] as bool?) ?? false;
  }

  /// 消费 final words：返回内容并写 finalWordsDelivered=true 防止重复输出。
  /// 若未写过或已交付过，返回空字符串。
  Future<String> consumeFinalWords() async {
    final delivered = await finalWordsDelivered();
    if (delivered) return '';
    final fw = await readFinalWords();
    if (fw == null) return '';
    await store.patchMeta({'finalWordsDelivered': true});
    return fw.summary;
  }

  // ============ v1.3: 长期不活跃检测 + wakify ============

  /// 上次见到用户的时间（unix ms）。0 表示从未记录（首次进入）。
  Future<int> lastSeenAt() async {
    final meta = await store.readMeta();
    return (meta['lastSeenAt'] as num?)?.toInt() ?? 0;
  }

  /// 标记"现在见到了用户"。在 SpiritScenePage initState 调用。
  Future<void> markSeen() async {
    await store.patchMeta(
        {'lastSeenAt': DateTime.now().millisecondsSinceEpoch});
  }

  /// 列出所有 dormant derived 事件（不含 seed / finalWords）。
  Future<List<MemoryEvent>> listDormantEvents() async {
    final all = await store.readAllEvents();
    return all
        .where((e) =>
            e.source == EventSource.derived &&
            e.dormant &&
            e.kind != EventKind.finalWords)
        .toList();
  }

  /// 永久唤醒指定 dormant 事件（钉住，永不再沉睡）。
  Future<void> wakify(List<String> ids) async {
    if (ids.isEmpty) return;
    final all = await store.readAllEvents();
    final idSet = ids.toSet();
    final patches = <String, MemoryEvent>{};
    for (final e in all) {
      if (idSet.contains(e.id) && e.dormant) {
        patches[e.id] = e.copyWith(dormant: false, wakified: true);
      }
    }
    await store.updateEvents(patches);
  }

  /// 取消钉住（让事件重新可被 decay 沉睡）。
  Future<void> unwakify(List<String> ids) async {
    if (ids.isEmpty) return;
    final all = await store.readAllEvents();
    final idSet = ids.toSet();
    final patches = <String, MemoryEvent>{};
    for (final e in all) {
      if (idSet.contains(e.id) && e.wakified) {
        patches[e.id] = e.copyWith(wakified: false);
      }
    }
    await store.updateEvents(patches);
  }

  // ============ v2.0: 声音配置 ============

  /// 读取声音配置。未配置返回 null。
  /// v2.1: 预设模式 voiceId 可空，靠 voicePreset 判断；克隆模式需 voiceId。
  Future<VoiceConfig?> readVoiceConfig() async {
    final meta = await store.readMeta();
    final voiceId = (meta['voiceId'] as String?) ?? '';
    final voicePreset = (meta['voicePreset'] as String?) ?? '';
    final voiceRecPath = meta['voiceRecPath'] as String?;
    // 克隆模式需 voiceId；预设模式需 voicePreset；都没则未配置
    final isClone = voicePreset == 'clone';
    if (isClone && voiceId.isEmpty) return null;
    if (!isClone && voicePreset.isEmpty) return null;
    return VoiceConfig(
      voiceId: voiceId,
      voicePreset: voicePreset,
      voiceRecPath: voiceRecPath,
    );
  }

  /// 写入声音配置（浅合并到 meta.json）。
  Future<void> setVoiceConfig(VoiceConfig config) async {
    await store.patchMeta({
      'voiceId': config.voiceId,
      'voicePreset': config.voicePreset,
      if (config.voiceRecPath != null) 'voiceRecPath': config.voiceRecPath,
    });
  }

  /// 清除声音配置（用户在记忆编辑页删除音色时调用）。
  Future<void> clearVoiceConfig() async {
    await store.patchMeta({
      'voiceId': '',
      'voicePreset': '',
      'voiceRecPath': null,
    });
  }

  String _fallbackTitle(String summary) {
    final s = summary.trim();
    if (s.isEmpty) return '一件想记住的事';
    return s.length <= 12 ? s : s.substring(0, 12);
  }

  String _normalizeWeight(String w) {
    if (w.contains('高')) return '高';
    if (w.contains('低')) return '低';
    return '中';
  }

  /// 注入若干 seed 事件（onboarding / 迁移用）
  Future<void> seed(List<MemoryEvent> events) async {
    if (events.isEmpty) return;
    final hardened = events
        .map((e) => e.copyWith(
              source: EventSource.seed,
              permadormant: true,
              dormant: false,
              createdAt: e.createdAt == 0
                  ? DateTime.now().millisecondsSinceEpoch
                  : e.createdAt,
            ))
        .toList();
    await store.appendEvents(hardened);
  }

  /// 是否已经迁移过 Memory.md（用于 main.dart 一次性条件触发）
  Future<bool> hasSeedAlready() async {
    final all = await store.readAllEvents();
    return all.any((e) => e.source == EventSource.seed);
  }
}
