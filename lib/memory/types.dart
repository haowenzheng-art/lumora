import 'dart:convert';

/// 记忆系统数据模型 v1.0
///
/// 三层：
///   L1 profile.md  —— 抽象印象（手写/LLM 维护，soft 400 / hard 1200 字）
///   L2 events.jsonl —— 具体事件（seed + derived，dormant 池无上限）
///   L3 messages.jsonl —— 原始对话流水
///
/// 事件来源：
///   - seed：onboarding/迁移注入，permadormant=true 永不沉睡
///   - derived：聊天提取，active soft 200 / hard 500，超额触发 dormant
enum EventSource { seed, derived }

EventSource _parseSource(String? s) {
  switch (s) {
    case 'seed':
      return EventSource.seed;
    case 'derived':
    default:
      return EventSource.derived;
  }
}

String _sourceToString(EventSource s) =>
    s == EventSource.seed ? 'seed' : 'derived';

/// 事件种类（v1.2 引入）：
///   - regular：普通 seed/derived，正常进检索池
///   - finalWords：用户在 onboarding 写的"最后想跟你说的话"，永不沉睡但
///     日常检索屏蔽，仅在用户表达告别意图触发 [[FINAL_WORDS]] 时由 agent 层
///     显式读取输出。一次性交付（consumeFinalWords 后标 delivered）
enum EventKind { regular, finalWords }

EventKind _parseKind(String? s) {
  switch (s) {
    case 'finalWords':
      return EventKind.finalWords;
    case 'regular':
    default:
      return EventKind.regular;
  }
}

String _kindToString(EventKind k) =>
    k == EventKind.finalWords ? 'finalWords' : 'regular';

/// 悲伤阶段（v2.3-C 引入 · 宪法第二条落地）
///
/// Lumora 不主动问用户"你现在哪一阶段"，也不让用户被阶段化打分。
/// 这是系统从对话行为推断的内部状态：用户感知得到的只有 UI 端的温和呈现
/// （SettingsPage 只读卡片，C-3 才接入），底层数据用于健康留存度量
/// （C-2 才计算）+ 抽取时的上下文标注（extractor 写 stage）。
///
/// 三阶段定义（仅供 LLM 推断参考，不在产品 UI 暴露为标签）：
///   - grieving      悲伤期：强负面情绪高频词，反复回到过去，记忆调用密集到深处事件
///   - transitioning 过渡期：负面情绪频次下降，出现"最近/明天"等未来词，夹杂日常事件
///   - recovered     已走出：回到产品但不带强情绪，对话中性或带正情绪，提未来计划多于过去
///
/// 字段语义：
///   - 写到 MemoryEvent 上的 stage：extractor 抽取时记录的"当时会话阶段"
///     （历史是历史——过去的 grieving 永远是 grieving，不会被改写为 recovered）
///   - 写到 meta 上的 currentStage：会话级当前阶段（每 N 轮 stage_classifier 更新，C-1b）
enum GriefStage { grieving, transitioning, recovered }

/// 解析 stage 字符串。容错：未知字符串返回 null（旧数据 / 未来字段扩展时不崩）。
GriefStage? _parseStage(String? s) {
  if (s == null || s.isEmpty) return null;
  for (final stage in GriefStage.values) {
    if (s == stage.name) return stage;
  }
  return null;
}

/// 单条事件
class MemoryEvent {
  /// 唯一 ID（uuid v4 风格的随机串）
  final String id;

  /// 事件来源
  final EventSource source;

  /// 事件发生时间（YYYY-MM-DD 或 YYYY-MM-DD HH:mm；模糊则用记录时间）
  final String date;

  /// 简短标题（≤20 字）
  final String title;

  /// 事件描述（≤200 字）
  final String summary;

  /// 标签集合（用于预筛检索）
  final List<String> tags;

  /// 权重：高 / 中 / 低
  final String weight;

  /// 创建时间（unix ms）
  final int createdAt;

  /// 最近一次进 prompt 的时间（recency 评分依据）
  final int lastUsedAt;

  /// dormant 状态：true 表示已沉睡，不进 tag 预筛池
  /// seed 事件即使 dormant=true 也永远不会被这样标记（permadormant=false）
  final bool dormant;

  /// 是否永不沉睡（seed=true，derived=false）
  final bool permadormant;

  /// 用户钉住的永久唤醒（v1.3）：true 表示这条 derived 事件被用户从 dormant 池
  /// 钉住，永不沉睡。与 permadormant 区别：permadormant 是 seed/finalWords 专属，
  /// wakified 是 derived 被用户手动钉住。
  final bool wakified;

  /// 事件种类（v1.2）：regular 或 finalWords
  final EventKind kind;

  /// v2.3-C 引入：抽取/记录时的会话阶段（grieving/transitioning/recovered）
  /// null = 阶段未确定（旧数据 + 阶段化之前的 derived event 都是 null）。
  /// 这是历史快照——不会被改写为"现在的阶段"。
  final GriefStage? stage;

  MemoryEvent({
    required this.id,
    required this.source,
    required this.date,
    required this.title,
    required this.summary,
    required this.tags,
    required this.weight,
    required this.createdAt,
    required this.lastUsedAt,
    required this.dormant,
    required this.permadormant,
    this.wakified = false,
    this.kind = EventKind.regular,
    this.stage,
  });

  factory MemoryEvent.fromJson(Map<String, dynamic> j) => MemoryEvent(
        id: j['id'] as String,
        source: _parseSource(j['source'] as String?),
        date: j['date'] as String? ?? '',
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        tags: ((j['tags'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        weight: j['weight'] as String? ?? '中',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        lastUsedAt: (j['lastUsedAt'] as num?)?.toInt() ?? 0,
        dormant: (j['dormant'] as bool?) ?? false,
        permadormant: (j['permadormant'] as bool?) ?? false,
        wakified: (j['wakified'] as bool?) ?? false,
        kind: _parseKind(j['kind'] as String?),
        stage: _parseStage(j['stage'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': _sourceToString(source),
        'date': date,
        'title': title,
        'summary': summary,
        'tags': tags,
        'weight': weight,
        'createdAt': createdAt,
        'lastUsedAt': lastUsedAt,
        'dormant': dormant,
        'permadormant': permadormant,
        'wakified': wakified,
        'kind': _kindToString(kind),
        // v2.3-C：stage 为 null 时不写入（向前兼容：旧 event 序列化后不带 stage 字段）
        if (stage != null) 'stage': stage!.name,
      };

  String toJsonLine() => jsonEncode(toJson());

  MemoryEvent copyWith({
    String? id,
    EventSource? source,
    String? date,
    String? title,
    String? summary,
    List<String>? tags,
    String? weight,
    int? createdAt,
    int? lastUsedAt,
    bool? dormant,
    bool? permadormant,
    bool? wakified,
    EventKind? kind,
    GriefStage? stage,
    bool clearStage = false,
  }) =>
      MemoryEvent(
        id: id ?? this.id,
        source: source ?? this.source,
        date: date ?? this.date,
        title: title ?? this.title,
        summary: summary ?? this.summary,
        tags: tags ?? this.tags,
        weight: weight ?? this.weight,
        createdAt: createdAt ?? this.createdAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        dormant: dormant ?? this.dormant,
        permadormant: permadormant ?? this.permadormant,
        wakified: wakified ?? this.wakified,
        kind: kind ?? this.kind,
        // v2.3-C：stage 是 nullable——通过 clearStage 显式置 null，默认保留旧值
        stage: clearStage ? null : (stage ?? this.stage),
      );

  /// 该事件渲染进 prompt 的文本形式
  String renderForPrompt() {
    final tagStr = tags.isEmpty ? '' : '  tags: ${tags.join('、')}';
    final stageStr = stage == null ? '' : '  [阶段:${stage!.name}]';
    return '【$date · $title】$summary$tagStr$stageStr';
  }
}

/// 单条原始消息（messages.jsonl 的一行）
class RawMessage {
  final String role; // user / assistant
  final String content;
  final int ts; // unix ms

  RawMessage({
    required this.role,
    required this.content,
    required this.ts,
  });

  factory RawMessage.fromJson(Map<String, dynamic> j) {
    int ts;
    final raw = j['ts'];
    if (raw is num) {
      ts = raw.toInt();
    } else if (raw is String) {
      ts = DateTime.tryParse(raw)?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
    } else {
      ts = DateTime.now().millisecondsSinceEpoch;
    }
    return RawMessage(
      role: j['role'] as String? ?? 'user',
      content: j['content'] as String? ?? '',
      ts: ts,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'ts': ts,
      };

  String toJsonLine() => jsonEncode(toJson());
}

/// 检索深度
enum RetrievalDepth { normal, deep }

/// 检索结果
class RetrievalResult {
  final List<MemoryEvent> events;
  final RetrievalDepth depth;
  final String profile;

  RetrievalResult({
    required this.events,
    required this.depth,
    required this.profile,
  });

  /// 直接渲染成给 prompt 用的字符串
  String renderForPrompt() {
    final buf = StringBuffer();
    if (profile.trim().isNotEmpty) {
      buf.writeln('## 你对用户的整体印象');
      buf.writeln(profile.trim());
      buf.writeln();
    }
    if (events.isNotEmpty) {
      buf.writeln(
          '## 与用户的共同记忆（当下被想起的 ${events.length} 条，按相关度排）');
      for (final e in events) {
        buf.writeln('- ${e.renderForPrompt()}');
      }
    }
    return buf.toString();
  }
}
