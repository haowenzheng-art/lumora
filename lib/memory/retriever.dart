import 'dart:convert';

import '../llm.dart';
import 'store.dart';
import 'types.dart';

/// 检索器 v1.0
///
/// 流程：
///   1. tag 预筛（seed + active derived）：把用户消息分词成关键词，与事件 tags/title/summary 求交
///   2. weight + recency 砍到 ≤ candidateCap 条
///   3. LLM rerank 选 top-K（K=normalK 默认 5；K=deepK 默认 8 当深度模式）
///
/// 深度模式触发信号（任 1 满足即升级）：
///   - 用户消息含回忆动词：还记得 / 上次 / 那时候 / 以前 / 之前你说过 / 当初 / 那次
///   - 用户消息长度 > 60 字
///   - 连续 ≥3 轮同一话题（由 same-topic 简单判断：上一轮 user 消息与本轮共享≥2个关键词）
class MemoryRetriever {
  final MemoryStore store;
  final int normalK;
  final int deepK;
  final int candidateCap;

  MemoryRetriever({
    required this.store,
    this.normalK = 5,
    this.deepK = 8,
    this.candidateCap = 40,
  });

  static final _recallVerbs = <RegExp>[
    RegExp(r'还记得'),
    RegExp(r'上次'),
    RegExp(r'那时候'),
    RegExp(r'以前'),
    RegExp(r'之前你?说过'),
    RegExp(r'当初'),
    RegExp(r'那次'),
    RegExp(r'记不记得'),
    RegExp(r'有没有印象'),
  ];

  /// 判断深度模式
  Future<RetrievalDepth> classifyDepth(
      String userMessage, List<RawMessage> recent) async {
    final m = userMessage.trim();
    if (m.length > 60) return RetrievalDepth.deep;
    for (final r in _recallVerbs) {
      if (r.hasMatch(m)) return RetrievalDepth.deep;
    }
    // 连续 ≥3 轮同话题：取最近 6 条里的 user 消息，看是否有 ≥2 个共享关键词
    final userMsgs = recent
        .where((x) => x.role == 'user')
        .map((x) => x.content)
        .toList();
    if (userMsgs.length >= 3) {
      final curKw = _extractKeywords(m).toSet();
      int sameCount = 0;
      for (final prev in userMsgs.reversed.take(3)) {
        final prevKw = _extractKeywords(prev).toSet();
        final shared = curKw.intersection(prevKw).length;
        if (shared >= 2) sameCount++;
      }
      if (sameCount >= 2) return RetrievalDepth.deep;
    }
    return RetrievalDepth.normal;
  }

  /// 主入口：根据当前 user 消息检索相关记忆
  ///
  /// recallMode=true 时全开 dormant 池（用户主动触发回忆模式），但 finalWords
  /// seed 永远不进普通检索池——它只在 [[FINAL_WORDS]] 触发时由 agent 层显式读取。
  Future<RetrievalResult> retrieve({
    required String userMessage,
    required List<RawMessage> recentMessages,
    bool recallMode = false,
  }) async {
    final depth = await classifyDepth(userMessage, recentMessages);
    final K = depth == RetrievalDepth.deep ? deepK : normalK;

    final all = await store.readAllEvents();
    final profile = await store.readProfile();

    // 池：seed + active derived（recallMode 时含 dormant derived）
    // finalWords seed 永远被屏蔽
    final pool = all.where((e) {
      if (e.kind == EventKind.finalWords) return false;
      if (e.source == EventSource.seed) return true;
      return !e.dormant || recallMode;
    }).toList();

    if (pool.isEmpty) {
      return RetrievalResult(events: [], depth: depth, profile: profile);
    }

    // 1) tag 预筛
    final kw = _extractKeywords(userMessage).toSet();
    final scored = <_Scored>[];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final e in pool) {
      final s = _preScore(e, kw, nowMs);
      if (s > 0) scored.add(_Scored(e, s));
    }
    // 如果一个都没命中（冷启动 / 用户消息无关键词），把"高 weight + 最近"前 K*3 拉进候选
    if (scored.isEmpty) {
      for (final e in pool) {
        scored.add(_Scored(e, _baseScore(e, nowMs)));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final candidates = scored.take(candidateCap).map((s) => s.event).toList();

    if (candidates.length <= K) {
      await _markUsed(candidates, nowMs);
      return RetrievalResult(
          events: candidates, depth: depth, profile: profile);
    }

    // 2) LLM rerank
    final reranked = await _llmRerank(userMessage, candidates, K);
    final picked = reranked ?? candidates.take(K).toList();
    await _markUsed(picked, nowMs);
    return RetrievalResult(events: picked, depth: depth, profile: profile);
  }

  /// 把 picked 的 lastUsedAt 更新到 store
  Future<void> _markUsed(List<MemoryEvent> picked, int nowMs) async {
    if (picked.isEmpty) return;
    final patches = <String, MemoryEvent>{
      for (final e in picked) e.id: e.copyWith(lastUsedAt: nowMs),
    };
    await store.updateEvents(patches);
  }

  /// 预筛打分：标签命中 + weight + recency
  double _preScore(MemoryEvent e, Set<String> kw, int nowMs) {
    if (kw.isEmpty) return _baseScore(e, nowMs);
    int hits = 0;
    for (final t in e.tags) {
      if (kw.any((k) => t.contains(k) || k.contains(t))) hits++;
    }
    // title / summary 子串命中也算
    for (final k in kw) {
      if (k.length >= 2 &&
          (e.title.contains(k) || e.summary.contains(k))) {
        hits++;
      }
    }
    if (hits == 0) return 0;
    return hits * 2.0 + _baseScore(e, nowMs);
  }

  /// 兜底分：weight + 时间衰减
  double _baseScore(MemoryEvent e, int nowMs) {
    final w = switch (e.weight) {
      '高' => 3.0,
      '低' => 1.0,
      _ => 2.0,
    };
    // recency：30 天内 +1，更久衰减
    final dt = (nowMs - e.createdAt).abs();
    final days = dt / (1000 * 60 * 60 * 24);
    final recency = days < 30 ? 1.0 : math_clamp(1.0 - (days - 30) / 365, 0, 1);
    return w + recency;
  }

  static double math_clamp(num v, num lo, num hi) =>
      v < lo ? lo.toDouble() : (v > hi ? hi.toDouble() : v.toDouble());

  /// 粗暴中文关键词抽取：去掉标点和短虚词，剩下的 2-4 字片段作为关键词候选
  static List<String> _extractKeywords(String text) {
    final cleaned = text.replaceAll(
        RegExp(r'[，。！？、；：""''（）()【】《》\.\?!,;:"\s]+'), ' ');
    final stop = <String>{
      '的', '了', '是', '我', '你', '他', '她', '它', '们', '吗', '呢',
      '吧', '啊', '哦', '嗯', '在', '有', '和', '与', '就', '都', '也',
      '还', '又', '才', '不', '没', '没有', '可以', '什么', '怎么', '这个',
      '那个', '这样', '那样', '一个', '一下', '会', '要', '能', '应该',
    };
    final out = <String>[];
    for (final raw in cleaned.split(' ')) {
      final w = raw.trim();
      if (w.isEmpty) continue;
      if (stop.contains(w)) continue;
      // 全是 ASCII 字母数字时整体保留（人名/英文词）
      if (RegExp(r'^[A-Za-z0-9]+$').hasMatch(w)) {
        if (w.length >= 2) out.add(w);
        continue;
      }
      // 中文：抽 2-grams 和 3-grams
      for (int n = 2; n <= 3; n++) {
        for (int i = 0; i + n <= w.length; i++) {
          final g = w.substring(i, i + n);
          if (stop.contains(g)) continue;
          out.add(g);
        }
      }
      // 整段也保留一份（短词如"火锅"会被 2-gram 命中；长词如"海底捞"被 3-gram 命中）
      if (w.length >= 2 && w.length <= 8) out.add(w);
    }
    return out;
  }

  Future<List<MemoryEvent>?> _llmRerank(
      String userMessage, List<MemoryEvent> candidates, int K) async {
    try {
      final indexed = <Map<String, dynamic>>[];
      for (int i = 0; i < candidates.length; i++) {
        final e = candidates[i];
        indexed.add({
          'i': i,
          'title': e.title,
          'summary': e.summary,
          'tags': e.tags,
        });
      }

      final system = '''
你是一个"记忆联想"辅助系统。给你一段用户当前说的话，以及若干条历史记忆候选。
你的任务：从候选里挑出**最自然会被联想到**的 $K 条（按相关度由强到弱排序），只输出索引 JSON 数组。

判断"自然联想"的依据（综合）：
- 主题/对象重合（同一个人、同一件事、同一类活动）
- 情绪共振（同样的难过/开心/愤怒）
- 时间或场景接近
- 用户在此刻可能希望对方记得的事

如果候选数 ≤ $K，全部返回。
如果候选里没一条真的相关，就只返回最像的 1-2 条，宁缺毋滥。

只输出 JSON 数组，例如：[3, 0, 7, 12, 5]
不要任何其他文字。
''';

      final user = '''
用户当前说："$userMessage"

候选记忆（共 ${candidates.length} 条）：
${jsonEncode(indexed)}

请按要求输出索引数组（最多 $K 个）。
''';

      final resp = await chat(
        system,
        [
          {'role': 'user', 'content': user},
        ],
        temperature: 0.2,
        maxTokens: 200,
      );

      var s = resp.content.trim();
      // 容错：找第一个 [
      final lb = s.indexOf('[');
      final rb = s.lastIndexOf(']');
      if (lb < 0 || rb <= lb) return null;
      s = s.substring(lb, rb + 1);
      final arr = jsonDecode(s) as List;
      final picked = <MemoryEvent>[];
      final seen = <int>{};
      for (final v in arr) {
        final i = (v as num).toInt();
        if (i < 0 || i >= candidates.length) continue;
        if (seen.add(i)) picked.add(candidates[i]);
        if (picked.length >= K) break;
      }
      return picked;
    } catch (_) {
      return null;
    }
  }
}

class _Scored {
  final MemoryEvent event;
  final double score;
  _Scored(this.event, this.score);
}
