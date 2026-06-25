import 'dart:convert';

import '../llm.dart';
import 'store.dart';
import 'types.dart';

/// 自动归档 / LLM 抽取层 v1.0
///
/// 触发时机：聊天达到 [extractEveryNTurns] 轮 user 消息后异步触发。
/// 单次抽取范围：上次抽取游标 → 当前末尾（取最近 maxWindowMessages 条）。
///
/// LLM 输出 JSON：
///   {
///     "events": [
///       {"date":"2026-06-24","title":"...","summary":"...","tags":[...],"weight":"高|中|低"},
///       ...
///     ],
///     "profile_patch": "...（一段中文，描述对用户的新增/修正印象，可空）"
///   }
class MemoryExtractor {
  final MemoryStore store;

  /// 每多少轮 user 消息触发一次抽取
  final int extractEveryNTurns;

  /// 每次抽取最多回看多少条原始消息
  final int maxWindowMessages;

  /// 抽取时给 LLM 的 max_tokens
  final int maxTokens;

  MemoryExtractor({
    required this.store,
    this.extractEveryNTurns = 6,
    this.maxWindowMessages = 24,
    this.maxTokens = 1200,
  });

  /// 是否到点了。基于 meta.lastExtractMsgCount 与当前 messages 数对比
  Future<bool> shouldRunNow() async {
    final meta = await store.readMeta();
    final last = (meta['lastExtractMsgCount'] as num?)?.toInt() ?? 0;
    final cur = await store.messagesCount();
    // 每多 extractEveryNTurns*2 条消息（user+assistant 各一）触发
    return (cur - last) >= extractEveryNTurns * 2;
  }

  /// 运行一次抽取；失败静默吞掉异常
  Future<MemoryExtractionResult?> runOnce() async {
    try {
      final cur = await store.messagesCount();
      final recent = await store.readRecentMessages(maxWindowMessages);
      if (recent.length < 4) return null;

      final result = await _callLlm(recent);
      if (result == null) {
        await store.patchMeta({'lastExtractMsgCount': cur});
        return null;
      }

      // 写事件
      if (result.events.isNotEmpty) {
        await store.appendEvents(result.events);
      }

      // 写 profile patch（追加为一段）
      if (result.profilePatch.trim().isNotEmpty) {
        final old = await store.readProfile();
        final merged = _mergeProfile(old, result.profilePatch.trim());
        await store.writeProfile(merged);
      }

      await store.patchMeta({
        'lastExtractMsgCount': cur,
        'lastExtractAt': DateTime.now().millisecondsSinceEpoch,
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 简单合并：旧 profile + 空行 + patch。超过 hard 上限按段落从头裁剪。
  String _mergeProfile(String old, String patch) {
    const softLimit = 400;
    const hardLimit = 1200;
    final oldTrim = old.trim();
    final merged = oldTrim.isEmpty ? patch : '$oldTrim\n\n$patch';
    if (merged.length <= hardLimit) return '$merged\n';

    // 超出 hard：按段落从最早开始砍，直到落到 softLimit~hardLimit 之间
    final paragraphs = merged.split(RegExp(r'\n\s*\n')).toList();
    while (paragraphs.length > 1 &&
        paragraphs.join('\n\n').length > softLimit) {
      paragraphs.removeAt(0);
    }
    return '${paragraphs.join('\n\n')}\n';
  }

  Future<MemoryExtractionResult?> _callLlm(List<RawMessage> recent) async {
    final transcript = recent.map((m) {
      final who = m.role == 'user' ? '用户' : '我';
      return '$who: ${m.content}';
    }).join('\n');

    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final system = '''
你是一个负责"记忆归档"的辅助系统。你不是聊天对象，不要扮演任何角色，只输出纯 JSON。

你的工作：阅读最近一段对话，从中提取**值得长期记住**的事件（具体经历、用户偏好、关系细节、情绪转折点），并简短更新对用户的整体印象。

输出严格 JSON（不要 ```json 包裹），结构：
{
  "events": [
    {
      "date": "YYYY-MM-DD",
      "title": "≤20字短标题",
      "summary": "≤200字事件描述，写人写事，不要写'用户说...'",
      "tags": ["3-6个中文短词"],
      "weight": "高|中|低"
    }
  ],
  "profile_patch": "≤120字的一段中文，更新对用户的整体印象。如无新发现则填空字符串。"
}

抽取原则：
1. **只抽具体事件 / 偏好 / 关系细节**，不要抽寒暄、问候、模型自我陈述。
2. **不重复**：如果这件事像是之前提过的，不要重复抽。
3. **写第三人称叙事**："他今天去了奶茶店"，不是"用户说今天去了奶茶店"。
4. **weight 评分**：
   - 高：情绪强烈 / 关系核心 / 用户主动强调要记住
   - 中：普通生活事件、偏好、习惯
   - 低：闲聊里偶然提到的小细节
5. **date**：能从对话推断具体日期就写具体；否则用今天 $dateStr。
6. **没东西可抽就返回 {"events": [], "profile_patch": ""}**。绝对不要硬凑。

只输出 JSON，不要任何前后文字。
''';

    final user = '''
今天是 $dateStr。

最近的对话片段：
---
$transcript
---

请按要求输出 JSON。
''';

    final resp = await chat(
      system,
      [
        {'role': 'user', 'content': user},
      ],
      temperature: 0.2,
      maxTokens: maxTokens,
    );

    return _parseLlmJson(resp.content);
  }

  MemoryExtractionResult? _parseLlmJson(String raw) {
    try {
      var s = raw.trim();
      // 容错：剥掉 ```json ... ``` 或 ``` ... ```
      if (s.startsWith('```')) {
        final firstNl = s.indexOf('\n');
        if (firstNl > 0) s = s.substring(firstNl + 1);
        if (s.endsWith('```')) s = s.substring(0, s.length - 3);
        s = s.trim();
      }
      // 容错：截到第一个 { 与最后一个 }
      final lb = s.indexOf('{');
      final rb = s.lastIndexOf('}');
      if (lb < 0 || rb <= lb) return null;
      s = s.substring(lb, rb + 1);

      final j = jsonDecode(s) as Map<String, dynamic>;
      final eventsRaw = (j['events'] as List?) ?? const [];
      final now = DateTime.now().millisecondsSinceEpoch;
      final events = <MemoryEvent>[];
      for (final eRaw in eventsRaw) {
        if (eRaw is! Map) continue;
        final e = (eRaw).cast<String, dynamic>();
        final title = (e['title'] as String? ?? '').trim();
        final summary = (e['summary'] as String? ?? '').trim();
        if (title.isEmpty || summary.isEmpty) continue;
        events.add(MemoryEvent(
          id: MemoryStore.newId(),
          source: EventSource.derived,
          date: (e['date'] as String? ?? '').trim(),
          title: title,
          summary: summary,
          tags: ((e['tags'] as List?) ?? const [])
              .map((x) => x.toString().trim())
              .where((x) => x.isNotEmpty)
              .toList(),
          weight: _normalizeWeight(e['weight'] as String? ?? '中'),
          createdAt: now,
          lastUsedAt: 0,
          dormant: false,
          permadormant: false,
        ));
      }
      final patch = (j['profile_patch'] as String? ?? '').trim();
      return MemoryExtractionResult(events: events, profilePatch: patch);
    } catch (_) {
      return null;
    }
  }

  String _normalizeWeight(String w) {
    final t = w.trim();
    if (t.contains('高') || t.toLowerCase() == 'high') return '高';
    if (t.contains('低') || t.toLowerCase() == 'low') return '低';
    return '中';
  }
}

class MemoryExtractionResult {
  final List<MemoryEvent> events;
  final String profilePatch;
  MemoryExtractionResult({required this.events, required this.profilePatch});
}
