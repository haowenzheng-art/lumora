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
      );

  /// 该事件渲染进 prompt 的文本形式
  String renderForPrompt() {
    final tagStr = tags.isEmpty ? '' : '  tags: ${tags.join('、')}';
    return '【$date · $title】$summary$tagStr';
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
