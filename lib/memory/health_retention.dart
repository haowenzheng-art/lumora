import 'store.dart';
import 'types.dart';

/// 健康留存度量（v2.3-C-2 · 宪法第二条北极星指标计算器）
///
/// 职责：消费 [StageClassifier] 已经写好的 `currentStage` 等 meta，
/// 加上 `lastSeenAt`，算出"用户当前是否处于健康留存状态"，写到 meta。
///
/// 北极星定义：
///   healthy = (stage ∈ {transitioning, recovered})
///          && (confidence >= [confidenceThreshold])
///          && (距上次访问 ≤ [maxDaysSinceVisit] 天)
///
/// 关键纪律（v2.3-C 整个阶段的宪法前提延续）：
///   - **不调 LLM** —— 纯本地计算，成本 0（C-1b 已经替我们跑过 stage 推断）
///   - **失败静默吞掉** —— 不能影响聊天主路径
///   - **不在 UI 暴露为打分** —— C-3 才决定温和呈现方式，本类只产出布尔 + 元数据
///   - **没有 stage 数据时不判定** —— 返回 null，不强行用历史 stage 算（避免误判）
///
/// 触发策略：
///   - 在 [MemoryService.maybeRunBackgroundTasks] 中跑（stageClassifier 之后）
///   - 节流交给调用方决定（读 meta 自己判断是否要重算）
///
/// Meta 字段（写到 `meta.json`）：
///   - healthyRetention: bool?              — 是否健康留存
///   - healthyRetentionAt: int?             — 计算时间（unix ms）
///   - healthyRetentionDaysSinceVisit: int? — 距上次访问天数（-1/null = 从未记录）
///   - healthyRetentionStage: String?       — 计算时的 stage snapshot
///   - healthyRetentionConfidence: num?     — 计算时的 confidence snapshot
class HealthRetentionComputer {
  final MemoryStore store;

  /// 阶段置信度阈值。低于此值认为 stage 不确定，不算健康。
  final double confidenceThreshold;

  /// 距上次访问的最大天数。超过则视作"已流失"。
  final int maxDaysSinceVisit;

  HealthRetentionComputer({
    required this.store,
    this.confidenceThreshold = 0.6,
    this.maxDaysSinceVisit = 14,
  });

  /// 计算一次健康留存状态。返回 null 表示：
  ///   - 没有 stage 数据（stageClassifier 从未跑过）
  ///   - stage 字符串无法解析（容错）
  ///   - 任何异常被捕获
  Future<HealthRetentionState?> compute() async {
    try {
      final meta = await store.readMeta();
      final stageStr = meta['currentStage'] as String?;
      final confidence = (meta['currentStageConfidence'] as num?)?.toDouble();
      final stageAt = (meta['currentStageAt'] as num?)?.toInt();
      if (stageStr == null || confidence == null || stageAt == null) {
        // 还没跑过 stageClassifier，先不算健康留存
        return null;
      }

      final stage = _parseStage(stageStr);
      if (stage == null) return null;

      final lastSeenAt = (meta['lastSeenAt'] as num?)?.toInt() ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final daysSinceVisit = lastSeenAt == 0
          ? -1 // 从未记录过（首次进入还没调 markSeen）
          : ((now - lastSeenAt) / 86400000).floor();

      final isHealthyStage =
          stage == GriefStage.transitioning || stage == GriefStage.recovered;
      final isConfident = confidence >= confidenceThreshold;
      // daysSinceVisit == -1 表示从未记录，按"未流失"算（用户当前正在使用）
      final isActive = daysSinceVisit == -1 ||
          (daysSinceVisit >= 0 && daysSinceVisit <= maxDaysSinceVisit);

      final healthy = isHealthyStage && isConfident && isActive;

      await store.patchMeta({
        'healthyRetention': healthy,
        'healthyRetentionAt': now,
        'healthyRetentionDaysSinceVisit': daysSinceVisit >= 0 ? daysSinceVisit : null,
        'healthyRetentionStage': stage.name,
        'healthyRetentionConfidence': confidence,
      });

      return HealthRetentionState(
        healthy: healthy,
        stage: stage,
        confidence: confidence,
        daysSinceVisit: daysSinceVisit,
        at: now,
      );
    } catch (_) {
      return null;
    }
  }

  /// 读上次计算结果（无则返回 null）。纯读 meta，不重算。
  Future<HealthRetentionState?> readLast() async {
    try {
      final meta = await store.readMeta();
      final healthy = meta['healthyRetention'] as bool?;
      final at = (meta['healthyRetentionAt'] as num?)?.toInt();
      if (healthy == null || at == null) return null;

      final stageStr = meta['healthyRetentionStage'] as String?;
      final stage = _parseStage(stageStr);
      final confidence =
          (meta['healthyRetentionConfidence'] as num?)?.toDouble() ?? 0;
      final daysSinceVisit =
          (meta['healthyRetentionDaysSinceVisit'] as num?)?.toInt() ?? -1;

      return HealthRetentionState(
        healthy: healthy,
        stage: stage,
        confidence: confidence,
        daysSinceVisit: daysSinceVisit,
        at: at,
      );
    } catch (_) {
      return null;
    }
  }

  GriefStage? _parseStage(String? s) {
    if (s == null) return null;
    for (final st in GriefStage.values) {
      if (st.name == s) return st;
    }
    return null;
  }
}

/// 健康留存状态（v2.3-C-2）
///
/// 字段：
///   - [healthy]          : 是否处于"健康留存"状态（北极星指标的布尔投影）
///   - [stage]            : 计算时的会话阶段 snapshot（debug / 透明性用）
///   - [confidence]       : 计算时的 stage 置信度 snapshot
///   - [daysSinceVisit]   : 距上次访问天数（-1 = 从未记录过）
///   - [at]               : 计算时间（unix ms）
class HealthRetentionState {
  final bool healthy;
  final GriefStage? stage;
  final double confidence;
  final int daysSinceVisit;
  final int at;

  HealthRetentionState({
    required this.healthy,
    required this.stage,
    required this.confidence,
    required this.daysSinceVisit,
    required this.at,
  });

  @override
  String toString() =>
      'HealthRetentionState(healthy=$healthy, stage=$stage, '
      'confidence=$confidence, daysSinceVisit=$daysSinceVisit, at=$at)';
}