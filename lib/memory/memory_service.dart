import 'dart:async';
import 'dart:io';

import 'decay.dart';
import 'extractor.dart';
import 'retriever.dart';
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
  Future<RetrievalResult> retrieveForPrompt(String userMessage) async {
    final recent = await store.readRecentMessages(12);
    return retriever.retrieve(
      userMessage: userMessage,
      recentMessages: recent,
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
        await decay.runOnce();
      } catch (_) {
        // 静默吞掉，不能影响聊天主路径
      } finally {
        _busy = false;
      }
    });
  }

  /// 读取 L1 profile
  Future<String> readProfile() => store.readProfile();

  /// 写入 L1 profile
  Future<void> writeProfile(String profile) => store.writeProfile(profile.trim());

  /// 读取所有 seed events（用户显式设定的初始记忆）
  Future<List<MemoryEvent>> listSeedEvents() async {
    final all = await store.readAllEvents();
    return all.where((e) => e.source == EventSource.seed).toList();
  }

  /// 替换 seed events，保留 derived events 不动。
  Future<void> replaceSeedEvents(List<MemoryEvent> events) async {
    final all = await store.readAllEvents();
    final derived = all.where((e) => e.source != EventSource.seed).toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    final hardened = events
        .where((e) => e.summary.trim().isNotEmpty)
        .map((e) => e.copyWith(
              id: e.id.isEmpty ? MemoryStore.newId() : e.id,
              source: EventSource.seed,
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
    await store.rewriteAllEvents([...derived, ...hardened]);
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
  }) {
    final now = DateTime.now();
    final dateText = date.trim().isEmpty
        ? '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        : date.trim();
    return MemoryEvent(
      id: id.isEmpty ? MemoryStore.newId() : id,
      source: EventSource.seed,
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
