import 'store.dart';
import 'types.dart';

/// 遗忘机制 v1.0
///
/// 规则：
///   - seed 永不沉睡（permadormant=true 时跳过）
///   - 当 active derived 超过 [softLimit]，按 weight × recency × lastUsedRecency 综合分
///     把分数最低的那些标记为 dormant，直到 active 缩回到 [softLimit]
///   - 当 active derived 超过 [hardLimit]，强制压到 softLimit*0.9 防止失控
///
/// 沉睡 ≠ 删除：dormant 事件仍在 events.jsonl 里，只是不会进 retrieval 池。
/// 后续可以做"被显式问起来时唤醒"机制（v1.1）。
class MemoryDecay {
  final MemoryStore store;
  final int softLimit;
  final int hardLimit;

  MemoryDecay({
    required this.store,
    this.softLimit = 200,
    this.hardLimit = 500,
  });

  /// 运行一次维护。返回被新标记 dormant 的事件数。
  Future<int> runOnce() async {
    final all = await store.readAllEvents();
    final activeDerived = all.where((e) =>
        e.source == EventSource.derived && !e.dormant && !e.permadormant).toList();
    if (activeDerived.length <= softLimit) return 0;

    final overflow = activeDerived.length - softLimit;
    final target = activeDerived.length > hardLimit
        ? activeDerived.length - (softLimit * 0.9).round()
        : overflow;

    // 综合分越低越优先沉睡
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    activeDerived.sort((a, b) =>
        _decayScore(a, nowMs).compareTo(_decayScore(b, nowMs)));

    final toDormant = activeDerived.take(target).map((e) => e.id).toSet();
    if (toDormant.isEmpty) return 0;

    final patches = <String, MemoryEvent>{};
    for (final e in all) {
      if (toDormant.contains(e.id)) {
        patches[e.id] = e.copyWith(dormant: true);
      }
    }
    await store.updateEvents(patches);
    await store.patchMeta(
        {'lastDecayAt': nowMs, 'lastDecayDormantCount': toDormant.length});
    return toDormant.length;
  }

  double _decayScore(MemoryEvent e, int nowMs) {
    final w = switch (e.weight) {
      '高' => 3.0,
      '低' => 1.0,
      _ => 2.0,
    };
    final ageDays =
        (nowMs - e.createdAt).abs() / (1000 * 60 * 60 * 24);
    final recency = ageDays < 30 ? 1.0 : (1.0 / (1.0 + (ageDays - 30) / 90));
    final usedDays = e.lastUsedAt <= 0
        ? 9999.0
        : (nowMs - e.lastUsedAt) / (1000 * 60 * 60 * 24);
    final usedBoost = usedDays < 7 ? 1.5 : (usedDays < 30 ? 1.0 : 0.4);
    return w * recency * usedBoost;
  }
}
