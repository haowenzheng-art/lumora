import 'dart:convert';

import '../llm.dart';
import 'store.dart';
import 'types.dart';

/// 会话级阶段推断器（v2.3-C-1b · 宪法第二条落地）
///
/// 职责：从最近 N 条对话推断用户当前所处的悲伤阶段（grieving /
/// transitioning / recovered），写入 `meta.currentStage` 等字段。
///
/// 宪法前提：
///   - **不主动问用户"你现在哪一阶段"**——阶段是系统推断的内部状态
///   - **不在 UI 暴露为标签 / 不打分**——C-3 才决定温和呈现方式
///   - **失败静默吞掉异常**——和 extractor 一样 robust，不影响主流程
///
/// 触发策略：
///   - 每 N 轮 user 消息触发一次（默认 6 轮），节流避免每轮都调 LLM
///   - 看最近 12 条消息（6 轮 user+assistant 各一）
///   - 失败时保留旧 stage，不清空（避免闪烁）
///
/// Meta 字段（写到 `meta.json`）：
///   - currentStage: String?       ('grieving' / 'transitioning' / 'recovered' / null)
///   - currentStageConfidence: num?  (0.0 - 1.0)
///   - currentStageAt: int?         (unix ms，最后一次推断时间)
///   - lastStageClassifyMsgCount: int? (节流用，记录上次推断时的消息数)
class StageClassifier {
  final MemoryStore store;

  /// 每多少轮 user 消息触发一次推断
  final int classifyEveryNTurns;

  /// 每次推断回看多少条消息
  final int windowMessages;

  /// LLM max_tokens
  final int maxTokens;

  StageClassifier({
    required this.store,
    this.classifyEveryNTurns = 6,
    this.windowMessages = 12,
    this.maxTokens = 300,
  });

  /// 是否到点了。基于 meta.lastStageClassifyMsgCount 与当前消息数对比
  Future<bool> shouldRunNow() async {
    final meta = await store.readMeta();
    final last = (meta['lastStageClassifyMsgCount'] as num?)?.toInt() ?? 0;
    final cur = await store.messagesCount();
    return (cur - last) >= classifyEveryNTurns * 2;
  }

  /// 运行一次推断；失败静默吞掉异常，返回 null
  Future<StageClassification?> runOnce() async {
    try {
      final cur = await store.messagesCount();
      final recent = await store.readRecentMessages(windowMessages);
      if (recent.length < 4) return null;

      final result = await _callLlm(recent);
      if (result == null) {
        // 失败：推进游标避免卡在同一处反复触发，但不写 stage
        await store.patchMeta({'lastStageClassifyMsgCount': cur});
        return null;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await store.patchMeta({
        'currentStage': result.stage.name,
        'currentStageConfidence': result.confidence,
        'currentStageAt': now,
        'lastStageClassifyMsgCount': cur,
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 读最近一次推断结果（无则返回 null）
  Future<StageClassification?> readLast() async {
    try {
      final meta = await store.readMeta();
      final stageStr = meta['currentStage'] as String?;
      final conf = (meta['currentStageConfidence'] as num?)?.toDouble();
      final at = (meta['currentStageAt'] as num?)?.toInt();
      if (stageStr == null || conf == null || at == null) return null;
      final stage = _parseStage(stageStr);
      if (stage == null) return null;
      return StageClassification(stage: stage, confidence: conf, at: at);
    } catch (_) {
      return null;
    }
  }

  Future<StageClassification?> _callLlm(List<RawMessage> recent) async {
    final transcript = recent.map((m) {
      final who = m.role == 'user' ? '用户' : '我';
      return '$who: ${m.content}';
    }).join('\n');
    final at = DateTime.now().millisecondsSinceEpoch;

    final system = '''
你是一个负责"会话阶段推断"的辅助系统。你不是聊天对象，不要扮演任何角色，只输出纯 JSON。

你的工作：阅读最近一段对话，推断用户当前所处的悲伤阶段。

三阶段定义：
- **grieving（悲伤期）**：强负面情绪高频词（哭 / 想 / 没意思 / 活不下去 / 撑不住 等）、
  反复回到过去、记忆调用密集到深处事件。
- **transitioning（过渡期）**：负面情绪频次下降、出现"最近 / 明天 / 下周"等未来时间词、
  对话中夹杂日常事件（工作 / 吃饭 / 天气 / 朋友）。
- **recovered（已走出）**：回到产品但不带强情绪、对话中性或带正情绪、
  提未来计划多于过去回忆。

判断原则：
1. **看语气词汇**，不要看字数。3 句话情绪崩溃仍是 grieving。
2. **看时间词**：经常出现"那一年 / 那时候 / 她" → grieving；"今天 / 明天 / 之后" → transitioning / recovered。
3. **看对话结构**：反复回到同一个人同一件事 → grieving；话题分散、聊日常 → transitioning / recovered。
4. **置信度（confidence）**：0.0（拿不准）到 1.0（很确定）。3 段对话已经够判断就给 0.7+。
5. **不要硬凑**：对话太短或信号模糊时，置信度 < 0.5 即可，不要猜。

输出严格 JSON（不要 ```json 包裹）：
{
  "stage": "grieving" | "transitioning" | "recovered",
  "confidence": 0.0 - 1.0,
  "reason": "≤30 字简述判断依据"
}

只输出 JSON，不要任何前后文字。
''';

    final user = '最近的对话片段：\n---\n$transcript\n---\n\n请按要求输出 JSON。';

    try {
      final resp = await chat(
        system,
        [
          {'role': 'user', 'content': user},
        ],
        temperature: 0.2,
        maxTokens: maxTokens,
      );
      return _parseLlmJson(resp.content, at);
    } catch (_) {
      return null;
    }
  }

  StageClassification? _parseLlmJson(String raw, int at) {
    try {
      var s = raw.trim();
      if (s.startsWith('```')) {
        final firstNl = s.indexOf('\n');
        if (firstNl > 0) s = s.substring(firstNl + 1);
        if (s.endsWith('```')) s = s.substring(0, s.length - 3);
        s = s.trim();
      }
      final lb = s.indexOf('{');
      final rb = s.lastIndexOf('}');
      if (lb < 0 || rb <= lb) return null;
      s = s.substring(lb, rb + 1);

      final j = jsonDecode(s) as Map<String, dynamic>;
      final stageStr = (j['stage'] as String? ?? '').trim();
      final stage = _parseStage(stageStr);
      if (stage == null) return null;
      final conf = (j['confidence'] as num?)?.toDouble();
      if (conf == null) return null;
      final clamped = conf < 0 ? 0.0 : (conf > 1 ? 1.0 : conf);
      final reason = (j['reason'] as String? ?? '').trim();
      return StageClassification(
        stage: stage,
        confidence: clamped,
        at: at,
        reason: reason.isEmpty ? null : reason,
      );
    } catch (_) {
      return null;
    }
  }

  /// 顶层私有 _parseStage（types.dart 那个）的实例版本。
  /// Dart library-private 不允许跨文件调用顶层函数，所以这里复制一份。
  GriefStage? _parseStage(String? s) {
    if (s == null) return null;
    for (final st in GriefStage.values) {
      if (st.name == s) return st;
    }
    return null;
  }
}

/// 阶段推断结果
class StageClassification {
  final GriefStage stage;
  final double confidence;
  final int at; // unix ms
  final String? reason;

  StageClassification({
    required this.stage,
    required this.confidence,
    required this.at,
    this.reason,
  });
}