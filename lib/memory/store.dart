import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'types.dart';

/// 记忆存储层 v1.0
///
/// 目录约定：
///   <docs>/Lumora/agents/<spiritId>/
///     messages.jsonl   L3 原始流水
///     events.jsonl     L2 事件
///     profile.md       L1 抽象印象
///     meta.json        {lastExtractIdx, lastMaintenanceAt, ...}
class MemoryStore {
  final String spiritId;

  /// 测试时可注入自定义根目录；为 null 走 path_provider
  final Directory? _baseDirOverride;

  MemoryStore(this.spiritId, {Directory? baseDirOverride})
      : _baseDirOverride = baseDirOverride;

  static final math.Random _rng = math.Random.secure();

  /// 生成事件 ID（短随机串，避免依赖 uuid 包）
  static String newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final sb = StringBuffer();
    for (int i = 0; i < 16; i++) {
      sb.write(chars[_rng.nextInt(chars.length)]);
    }
    return sb.toString();
  }

  Future<Directory> _agentDir() async {
    final Directory root;
    if (_baseDirOverride != null) {
      root = _baseDirOverride;
    } else {
      root = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${root.path}/Lumora/agents/$spiritId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> messagesFile() async =>
      File('${(await _agentDir()).path}/messages.jsonl');

  Future<File> eventsFile() async =>
      File('${(await _agentDir()).path}/events.jsonl');

  Future<File> profileFile() async =>
      File('${(await _agentDir()).path}/profile.md');

  Future<File> metaFile() async =>
      File('${(await _agentDir()).path}/meta.json');

  // ============ messages ============

  Future<void> appendMessage(RawMessage m) async {
    final f = await messagesFile();
    await f.create(recursive: true);
    await f.writeAsString('${m.toJsonLine()}\n',
        mode: FileMode.append, encoding: utf8);
  }

  Future<List<RawMessage>> readAllMessages() async {
    final f = await messagesFile();
    if (!await f.exists()) return [];
    final lines = await f.readAsLines();
    final out = <RawMessage>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(RawMessage.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  /// 取最近 N 条原始消息（保持时间正序）
  Future<List<RawMessage>> readRecentMessages(int n) async {
    final all = await readAllMessages();
    if (all.length <= n) return all;
    return all.sublist(all.length - n);
  }

  Future<int> messagesCount() async {
    final f = await messagesFile();
    if (!await f.exists()) return 0;
    int n = 0;
    final stream = f.openRead().transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in stream) {
      if (line.trim().isNotEmpty) n++;
    }
    return n;
  }

  // ============ events ============

  Future<void> appendEvent(MemoryEvent e) async {
    final f = await eventsFile();
    await f.create(recursive: true);
    await f.writeAsString('${e.toJsonLine()}\n',
        mode: FileMode.append, encoding: utf8);
  }

  Future<void> appendEvents(Iterable<MemoryEvent> events) async {
    final f = await eventsFile();
    await f.create(recursive: true);
    final buf = StringBuffer();
    for (final e in events) {
      buf.writeln(e.toJsonLine());
    }
    if (buf.isEmpty) return;
    await f.writeAsString(buf.toString(),
        mode: FileMode.append, encoding: utf8);
  }

  Future<List<MemoryEvent>> readAllEvents() async {
    final f = await eventsFile();
    if (!await f.exists()) return [];
    final lines = await f.readAsLines();
    final out = <MemoryEvent>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(MemoryEvent.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  /// 整体重写 events.jsonl（用于 dormant 标记 / 更新 lastUsedAt）
  Future<void> rewriteAllEvents(List<MemoryEvent> events) async {
    final f = await eventsFile();
    await f.create(recursive: true);
    final buf = StringBuffer();
    for (final e in events) {
      buf.writeln(e.toJsonLine());
    }
    await f.writeAsString(buf.toString(), encoding: utf8);
  }

  /// 部分更新：根据 id 替换若干条事件，其余保持不动
  Future<void> updateEvents(Map<String, MemoryEvent> patches) async {
    if (patches.isEmpty) return;
    final all = await readAllEvents();
    for (int i = 0; i < all.length; i++) {
      final p = patches[all[i].id];
      if (p != null) all[i] = p;
    }
    await rewriteAllEvents(all);
  }

  // ============ profile.md ============

  Future<String> readProfile() async {
    final f = await profileFile();
    if (!await f.exists()) return '';
    try {
      return await f.readAsString();
    } catch (_) {
      return '';
    }
  }

  Future<void> writeProfile(String content) async {
    final f = await profileFile();
    await f.create(recursive: true);
    await f.writeAsString(content, encoding: utf8);
  }

  // ============ meta ============

  Future<Map<String, dynamic>> readMeta() async {
    final f = await metaFile();
    if (!await f.exists()) return {};
    try {
      final raw = await f.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> writeMeta(Map<String, dynamic> meta) async {
    final f = await metaFile();
    await f.create(recursive: true);
    await f.writeAsString(jsonEncode(meta), encoding: utf8);
  }

  Future<void> patchMeta(Map<String, dynamic> patch) async {
    final cur = await readMeta();
    cur.addAll(patch);
    await writeMeta(cur);
  }
}
