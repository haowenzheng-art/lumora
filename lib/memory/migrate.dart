import 'package:flutter/services.dart' show rootBundle;

import 'memory_service.dart';
import 'store.dart';
import 'types.dart';

/// 一次性把 agent_data/<spirit>/Memory.md 迁移为 seed events。
///
/// 解析格式：
///   ## YYYY-MM-DD · 标题
///   （多行正文）
///   tags: a、b、c
///   weight: 高 / 中 / 低
///
/// 调用条件：MemoryService.hasSeedAlready() == false 时调用一次。
class MemoryMigrator {
  /// 解析 Memory.md 的全部条目
  static List<MemoryEvent> parseMemoryMd(String md) {
    final out = <MemoryEvent>[];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final blocks = md.split(RegExp(r'^## ', multiLine: true));
    for (final raw in blocks) {
      final b = raw.trim();
      if (b.isEmpty) continue;
      // 第一行是 "YYYY-MM-DD · 标题"
      final lines = b.split('\n');
      if (lines.isEmpty) continue;
      final header = lines.first.trim();
      if (!header.contains('·')) continue;
      final parts = header.split('·');
      final date = parts.first.trim();
      final title = parts.sublist(1).join('·').trim();

      // 收集正文（直到 tags: 或 weight: 之前）
      final body = <String>[];
      List<String>? tags;
      String? weight;
      for (int i = 1; i < lines.length; i++) {
        final ln = lines[i].trim();
        if (ln.isEmpty) continue;
        if (ln.startsWith('tags:') || ln.startsWith('tags：')) {
          final sep = ln.contains('：') ? '：' : ':';
          final v = ln.substring(ln.indexOf(sep) + 1).trim();
          tags = v
              .split(RegExp(r'[、,，\s]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          continue;
        }
        if (ln.startsWith('weight:') || ln.startsWith('weight：')) {
          final sep = ln.contains('：') ? '：' : ':';
          weight = ln.substring(ln.indexOf(sep) + 1).trim();
          continue;
        }
        if (ln == '---') continue;
        body.add(ln);
      }
      if (title.isEmpty || body.isEmpty) continue;

      final w = (weight ?? '中').contains('高')
          ? '高'
          : (weight ?? '中').contains('低')
              ? '低'
              : '中';

      out.add(MemoryEvent(
        id: MemoryStore.newId(),
        source: EventSource.seed,
        date: date,
        title: title,
        summary: body.join(' '),
        tags: tags ?? const [],
        weight: w,
        createdAt: nowMs,
        lastUsedAt: 0,
        dormant: false,
        permadormant: true,
      ));
    }
    return out;
  }

  /// 尝试从 asset 路径读 Memory.md 并迁移；返回写入的条数
  static Future<int> migrateFromAssetIfNeeded({
    required MemoryService service,
    required String assetPath,
  }) async {
    if (await service.hasSeedAlready()) return 0;
    String md;
    try {
      md = await rootBundle.loadString(assetPath);
    } catch (_) {
      return 0;
    }
    final events = parseMemoryMd(md);
    if (events.isEmpty) return 0;
    await service.seed(events);
    return events.length;
  }
}
