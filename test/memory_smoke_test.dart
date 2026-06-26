// Lumora 记忆系统端到端烟雾测试
//
// 跑法：
//   cd Lumora
//   flutter test test/memory_smoke_test.dart
//
// 测什么：
//   - MemoryStore 三层文件读写
//   - Memory.md 解析为 seed events
//   - MemoryRetriever tag 预筛（不调 LLM rerank）
//   - 深度模式分类
//   - MemoryDecay dormant 标记
//
// 不测（必须人工目视）：
//   - LLM 抽取出来的事件质量 / profile_patch 是否像人话
//   - LLM rerank 选的 5 条是不是"最自然联想"
//   - UI 视觉 / 视频淡入 / 动画流畅度

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lumora/memory/decay.dart';
import 'package:lumora/memory/memory_service.dart';
import 'package:lumora/memory/migrate.dart';
import 'package:lumora/memory/retriever.dart';
import 'package:lumora/memory/store.dart';
import 'package:lumora/memory/types.dart';
import 'package:lumora/prompt.dart';
import 'package:lumora/voice.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lumora_smoke_');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('[1/5] MemoryStore 三层文件读写', () async {
    final store = MemoryStore('test_spirit', baseDirOverride: tmp);

    await store.appendMessage(RawMessage(role: 'user', content: '你好', ts: 1));
    await store.appendMessage(RawMessage(role: 'assistant', content: '嗯', ts: 2));
    final msgs = await store.readAllMessages();
    expect(msgs.length, 2, reason: 'messages.jsonl 读回 2 条');
    expect(msgs[0].role, 'user');
    expect(msgs[0].content, '你好');
    expect(await store.messagesCount(), 2);

    final e = MemoryEvent(
      id: MemoryStore.newId(),
      source: EventSource.derived,
      date: '2026-06-24',
      title: '测试事件',
      summary: '这是一条测试事件',
      tags: ['测试', '烟雾'],
      weight: '中',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      lastUsedAt: 0,
      dormant: false,
      permadormant: false,
    );
    await store.appendEvent(e);
    final allEvents = await store.readAllEvents();
    expect(allEvents.length, 1);
    expect(allEvents.first.title, '测试事件');

    await store.updateEvents({e.id: e.copyWith(weight: '高')});
    final after = await store.readAllEvents();
    expect(after.first.weight, '高', reason: 'updateEvents 改 weight 成功');

    await store.writeProfile('一段印象');
    expect(await store.readProfile(), '一段印象');

    await store.patchMeta({'x': 1});
    await store.patchMeta({'y': 2});
    final meta = await store.readMeta();
    expect(meta['x'], 1);
    expect(meta['y'], 2);
  });

  test('[2/5] Memory.md 解析为 seed events', () {
    const md = '''
# Memory · 测试

---

## 2024-12-01 · 雪天围巾

冬天大雪那天，我把围巾给他。后来他弄丢了。

tags: 地铁、雪、围巾
weight: 高

---

## 2023-08-15 · 海底捞

我们一起去海底捞吃番茄锅。

tags: 火锅、海底捞
weight: 中

---

## 不规则标题没分隔符

这条应该被跳过。
''';
    final events = MemoryMigrator.parseMemoryMd(md);
    expect(events.length, 2, reason: '只解析出 2 条合法事件（不规则的被跳过）');
    expect(events.every((e) => e.source == EventSource.seed), true);
    expect(events.every((e) => e.permadormant == true), true);
    expect(events[0].weight, '高');
    expect(events[1].weight, '中');
    expect(events[0].tags.contains('围巾'), true);
  });

  test('[3/5] Retriever tag 预筛（不触发 LLM rerank）', () async {
    final store = MemoryStore('xiaoyu', baseDirOverride: tmp);
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.appendEvents([
      MemoryEvent(
        id: MemoryStore.newId(),
        source: EventSource.seed,
        date: '2024-12-01',
        title: '雪天地铁围巾',
        summary: '冬天大雪那天我把围巾给他',
        tags: ['地铁', '雪', '围巾'],
        weight: '高',
        createdAt: now,
        lastUsedAt: 0,
        dormant: false,
        permadormant: true,
      ),
      MemoryEvent(
        id: MemoryStore.newId(),
        source: EventSource.seed,
        date: '2024-XX-XX',
        title: '奶茶店半糖去冰',
        summary: '他常买半糖去冰',
        tags: ['奶茶', '半糖', '烤红薯'],
        weight: '高',
        createdAt: now,
        lastUsedAt: 0,
        dormant: false,
        permadormant: true,
      ),
      MemoryEvent(
        id: MemoryStore.newId(),
        source: EventSource.derived,
        date: '2026-06-20',
        title: '加班骗人',
        summary: '说不加班结果加到夜里两点',
        tags: ['加班', '骗人'],
        weight: '中',
        createdAt: now,
        lastUsedAt: 0,
        dormant: false,
        permadormant: false,
      ),
    ]);

    // 候选总数 3 ≤ normalK=5，retriever 不会调 LLM rerank
    final retriever = MemoryRetriever(store: store);

    final r1 = await retriever.retrieve(
      userMessage: '我刚路过那家奶茶店了',
      recentMessages: [],
    );
    expect(r1.events.any((e) => e.title == '奶茶店半糖去冰'), true,
        reason: '关键词"奶茶店"召回"奶茶店半糖去冰"');

    final r2 = await retriever.retrieve(
      userMessage: '今天坐地铁有点冷',
      recentMessages: [],
    );
    expect(r2.events.any((e) => e.title == '雪天地铁围巾'), true,
        reason: '关键词"地铁"召回"雪天地铁围巾"');

    final r3 = await retriever.retrieve(
      userMessage: 'asdfasdf',
      recentMessages: [],
    );
    expect(r3.events.isNotEmpty, true,
        reason: '无关键词时走兜底，仍返回结果');

    // dormant 事件不应进检索池
    final all = await store.readAllEvents();
    final derived = all.firstWhere((e) => e.source == EventSource.derived);
    await store.updateEvents({derived.id: derived.copyWith(dormant: true)});
    final r4 = await retriever.retrieve(
      userMessage: '加班',
      recentMessages: [],
    );
    expect(r4.events.any((e) => e.title == '加班骗人'), false,
        reason: 'dormant=true 的事件不进检索池');
  });

  test('[4/5] 深度模式分类', () async {
    final store = MemoryStore('test_depth', baseDirOverride: tmp);
    final r = MemoryRetriever(store: store);

    expect(await r.classifyDepth('嗯', []), RetrievalDepth.normal,
        reason: '短消息无关键词 → normal');
    expect(await r.classifyDepth('你还记得那次地铁的事吗？', []),
        RetrievalDepth.deep,
        reason: '含"还记得" → deep');
    expect(
        await r.classifyDepth(
            '今天工作上发生了一件很烦的事，老板又开始那一套不公平的对待了，'
            '我真的快撑不住了，想跟你好好讲讲这件事的整个来龙去脉，'
            '这样我心里能舒服一点点也好。',
            []),
        RetrievalDepth.deep,
        reason: '消息 > 60 字 → deep');
    expect(await r.classifyDepth('上次那个事', []), RetrievalDepth.deep,
        reason: '含"上次" → deep');
  });

  test('[5/6] MemoryDecay 沉睡机制', () async {
    final store = MemoryStore('test_decay', baseDirOverride: tmp);
    final now = DateTime.now().millisecondsSinceEpoch;
    final events = <MemoryEvent>[];
    for (int i = 0; i < 5; i++) {
      events.add(MemoryEvent(
        id: MemoryStore.newId(),
        source: EventSource.seed,
        date: '2024-01-01',
        title: 'seed-$i',
        summary: 'seed event $i',
        tags: ['seed'],
        weight: '高',
        createdAt: now,
        lastUsedAt: 0,
        dormant: false,
        permadormant: true,
      ));
    }
    for (int i = 0; i < 12; i++) {
      events.add(MemoryEvent(
        id: MemoryStore.newId(),
        source: EventSource.derived,
        date: '2024-01-01',
        title: 'derived-$i',
        summary: 'derived $i',
        tags: ['x'],
        weight: i < 3 ? '高' : '低',
        createdAt: now - i * 86400000 * 5,
        lastUsedAt: 0,
        dormant: false,
        permadormant: false,
      ));
    }
    await store.appendEvents(events);

    final decay = MemoryDecay(store: store, softLimit: 8, hardLimit: 20);
    final dormantCount = await decay.runOnce();
    expect(dormantCount, 4,
        reason: '12 - 8 = 4 条 derived 被标 dormant');

    final after = await store.readAllEvents();
    final seedDormant =
        after.where((e) => e.source == EventSource.seed && e.dormant).length;
    expect(seedDormant, 0, reason: 'seed 永不被沉睡');

    final activeDerived = after
        .where((e) => e.source == EventSource.derived && !e.dormant)
        .length;
    expect(activeDerived, 8, reason: 'active derived 缩回 softLimit=8');
  });


  test('[6/7] DIY memory/profile data layer', () async {
    final service = MemoryService(spiritId: 'diy_test', baseDirOverride: tmp);
    final store = service.store;

    await service.writeProfile('他很重视被认真记住。');
    expect(await service.readProfile(), '他很重视被认真记住。');

    final seedA = service.buildSeedEvent(
      title: '旧种子A',
      summary: '第一条旧 seed 记忆',
      tags: ['旧', 'A'],
      weight: '高',
    );
    final seedB = service.buildSeedEvent(
      title: '旧种子B',
      summary: '第二条旧 seed 记忆',
      tags: ['旧', 'B'],
      weight: '中',
    );
    final derived = MemoryEvent(
      id: MemoryStore.newId(),
      source: EventSource.derived,
      date: '2026-06-25',
      title: '聊天长出的记忆',
      summary: '这条 derived 不应该被 replaceSeedEvents 删除',
      tags: ['derived'],
      weight: '中',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      lastUsedAt: 0,
      dormant: false,
      permadormant: false,
    );

    await service.replaceSeedEvents([seedA, seedB]);
    await store.appendEvent(derived);

    final newSeed = service.buildSeedEvent(
      title: '',
      summary: '新的 seed 记忆会替换旧 seed，但保留 derived',
      tags: ['新'],
      weight: '高',
    );
    await service.replaceSeedEvents([newSeed]);

    final all = await store.readAllEvents();
    final seeds = all.where((e) => e.source == EventSource.seed).toList();
    final derivedEvents = all.where((e) => e.source == EventSource.derived).toList();

    expect(seeds.length, 1, reason: 'seed 被整体替换为新列表');
    expect(seeds.first.summary, '新的 seed 记忆会替换旧 seed，但保留 derived');
    expect(seeds.first.permadormant, true);
    expect(seeds.first.dormant, false);
    expect(seeds.first.weight, '高');
    expect(derivedEvents.length, 1, reason: 'derived 事件被保留');
    expect(derivedEvents.first.title, '聊天长出的记忆');
  });

  test('[7/7] custom spirit prompt is isolated from Xiaoyu demo', () async {
    final prompt = await buildSystemPrompt(
      spiritName: '罗罗',
      demoXiaoyu: false,
      dynamicMemory: '## 你对用户的整体印象\n用户喜欢安静地表达情绪。\n',
    );

    expect(prompt.contains('你叫罗罗'), true);
    expect(prompt.contains('用户喜欢安静地表达情绪'), true);
    expect(prompt.contains('明远'), false,
        reason: '自定义精灵 prompt 不能污染小雨/明远 demo 身份');
    expect(prompt.contains('半年前车祸'), false,
        reason: '自定义精灵不能继承小雨已逝设定');
    expect(prompt.contains('半糖去冰'), false,
        reason: '自定义精灵不能注入小雨 Memory.md / few-shot 专属记忆');
    expect(prompt.contains('小雨（温柔）'), false,
        reason: '自定义精灵不能使用小雨专属 few-shot');
  });

  test('[8/9] final words seed is isolated from regular retrieval', () async {
    final service = MemoryService(spiritId: 'fw_test', baseDirOverride: tmp);
    final store = service.store;

    // 写一条 final words + 一条普通 seed
    await service.writeFinalWords('谢谢你愿意把我做出来。去过你自己的日子吧。');
    final regularSeed = service.buildSeedEvent(
      title: '奶茶店',
      summary: '他常买半糖去冰',
      tags: ['奶茶'],
      weight: '高',
    );
    await service.replaceSeedEvents([regularSeed]);

    // readFinalWords 能读到
    final fw = await service.readFinalWords();
    expect(fw, isNotNull);
    expect(fw!.kind, EventKind.finalWords);
    expect(fw.summary.contains('谢谢你愿意把我做出来'), true);
    expect(fw.permadormant, true, reason: 'finalWords 永不沉睡');
    expect(fw.dormant, false);
    expect(fw.weight, '高');

    // listSeedEvents 不含 finalWords
    final seeds = await service.listSeedEvents();
    expect(seeds.any((e) => e.kind == EventKind.finalWords), false,
        reason: 'listSeedEvents 应排除 finalWords');
    expect(seeds.length, 1);
    expect(seeds.first.title, '奶茶店');

    // 普通检索不召回 finalWords
    final retriever = MemoryRetriever(store: store);
    final r = await retriever.retrieve(
      userMessage: '谢谢你',
      recentMessages: [],
    );
    expect(r.events.any((e) => e.kind == EventKind.finalWords), false,
        reason: 'finalWords 永不进日常检索池');
    expect(r.events.any((e) => e.title == '奶茶店'), true,
        reason: '普通 seed 仍能被召回');

    // replaceSeedEvents 不应冲掉 finalWords
    expect((await service.readFinalWords())?.summary.contains('谢谢你愿意把我做出来'),
        true,
        reason: 'replaceSeedEvents 应保留 finalWords seed');
  });

  test('[9/9] recall mode retrieves dormant events', () async {
    final store = MemoryStore('recall_test', baseDirOverride: tmp);
    final now = DateTime.now().millisecondsSinceEpoch;

    // 一条 active seed（基线，不命中"加班"）
    await store.appendEvent(MemoryEvent(
      id: MemoryStore.newId(),
      source: EventSource.seed,
      date: '2024-01-01',
      title: '雪天围巾',
      summary: '冬天大雪那天我把围巾给他',
      tags: ['雪', '围巾'],
      weight: '高',
      createdAt: now,
      lastUsedAt: 0,
      dormant: false,
      permadormant: true,
    ));
    // 一条 dormant derived（已沉睡，命中"加班"）
    await store.appendEvent(MemoryEvent(
      id: MemoryStore.newId(),
      source: EventSource.derived,
      date: '2024-06-01',
      title: '加班骗人',
      summary: '说不加班结果加到夜里两点',
      tags: ['加班', '骗人'],
      weight: '中',
      createdAt: now,
      lastUsedAt: 0,
      dormant: true,
      permadormant: false,
    ));

    final retriever = MemoryRetriever(store: store);

    // 普通模式：dormant 不进池
    final r1 = await retriever.retrieve(
      userMessage: '加班',
      recentMessages: [],
    );
    expect(r1.events.any((e) => e.title == '加班骗人'), false,
        reason: '普通模式下 dormant 事件不进检索池');

    // 回忆模式：dormant 全开
    final r2 = await retriever.retrieve(
      userMessage: '加班',
      recentMessages: [],
      recallMode: true,
    );
    expect(r2.events.any((e) => e.title == '加班骗人'), true,
        reason: 'recallMode=true 时 dormant 事件应被召回');
  });

  test('[10/11] lastSeenAt tracking', () async {
    final service = MemoryService(spiritId: 'farewell_test', baseDirOverride: tmp);

    expect(await service.lastSeenAt(), 0, reason: '初始 lastSeenAt=0');

    await service.markSeen();
    final t1 = await service.lastSeenAt();
    expect(t1 > 0, true, reason: 'markSeen 后 lastSeenAt 非 0');

    // 模拟 31 天前的时间戳
    final oldTs = DateTime.now()
        .subtract(const Duration(days: 31))
        .millisecondsSinceEpoch;
    await service.store.patchMeta({'lastSeenAt': oldTs});
    final t2 = await service.lastSeenAt();
    final days = (DateTime.now().millisecondsSinceEpoch - t2) /
        (1000 * 60 * 60 * 24);
    expect(days > 30, true, reason: '写入 31 天前的时间戳后应判定为超期');

    // finalWordsDelivered 初始为 false
    expect(await service.finalWordsDelivered(), false,
        reason: 'finalWordsDelivered 初始 false');
  });

  test('[11/11] wakify permanently wakes dormant events', () async {
    final service = MemoryService(spiritId: 'wakify_test', baseDirOverride: tmp);
    final store = service.store;

    // 写一条 dormant derived
    final e = MemoryEvent(
      id: 'dormant1',
      source: EventSource.derived,
      date: '2024-01-01',
      title: '加班骗人',
      summary: '说不加班结果加到夜里两点',
      tags: ['加班'],
      weight: '中',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      lastUsedAt: 0,
      dormant: true,
      permadormant: false,
      wakified: false,
    );
    await store.appendEvent(e);

    // 写一条 active derived（供 decay 尝试沉睡）
    final active = MemoryEvent(
      id: 'active1',
      source: EventSource.derived,
      date: '2024-01-02',
      title: '另一条活跃的',
      summary: '这条还没沉睡',
      tags: ['其他'],
      weight: '低',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      lastUsedAt: 0,
      dormant: false,
      permadormant: false,
      wakified: false,
    );
    await store.appendEvent(active);

    // wakify dormant1
    await service.wakify(['dormant1']);
    final after = await store.readAllEvents();
    final woken = after.firstWhere((x) => x.id == 'dormant1');
    expect(woken.dormant, false, reason: 'wakify 后 dormant=false');
    expect(woken.wakified, true, reason: 'wakify 后 wakified=true');

    // listDormantEvents 应不再返回已唤醒的
    final dormantList = await service.listDormantEvents();
    expect(dormantList.any((e) => e.id == 'dormant1'), false,
        reason: 'wakified 事件不在 dormant 列表中');

    // decay 不应重新沉睡 wakified 事件
    final decay = MemoryDecay(store: store, softLimit: 0, hardLimit: 1);
    await decay.runOnce();
    final after2 = await store.readAllEvents();
    final still = after2.firstWhere((x) => x.id == 'dormant1');
    expect(still.dormant, false, reason: 'wakified 事件不会被 decay 重新沉睡');
    expect(still.wakified, true, reason: 'wakified 状态保持');

    // unwakify 后可重新沉睡
    await service.unwakify(['dormant1']);
    final after3 = await store.readAllEvents();
    final unpinned = after3.firstWhere((x) => x.id == 'dormant1');
    expect(unpinned.wakified, false, reason: 'unwakify 后 wakified=false');
    // dormant 仍为 false（unwakify 不主动沉睡，只是移除保护）
    expect(unpinned.dormant, false,
        reason: 'unwakify 不主动沉睡，只是移除保护，下次 decay 才会沉睡');
  });

  test('[12/12] v2.0 voice config read/write via meta.json', () async {
    final service =
        MemoryService(spiritId: 'voice_test', baseDirOverride: tmp);

    expect(await service.readVoiceConfig(), null,
        reason: '初始无 voice 配置');

    // v2.1: 预设音色 voiceId 留空（Edge TTS 用 voicePreset 映射）
    await service.setVoiceConfig(const VoiceConfig(
      voiceId: '',
      voicePreset: '温柔女声',
    ));
    final cfg1 = await service.readVoiceConfig();
    expect(cfg1, isNotNull, reason: '预设模式 voiceId 空也能读到');
    expect(cfg1!.voiceId, '', reason: '预设模式 voiceId 为空');
    expect(cfg1.voicePreset, '温柔女声');
    expect(cfg1.voiceRecPath, null, reason: '预设音色无参考音频路径');
    expect(cfg1.isClone, false, reason: '预设音色 isClone=false');
    expect(cfg1.isPreset, true, reason: '预设音色 isPreset=true');

    // 克隆真人声音配置（需 voiceId）
    await service.setVoiceConfig(const VoiceConfig(
      voiceId: 'clone_xxxx',
      voicePreset: 'clone',
      voiceRecPath: '/path/to/ref.wav',
    ));
    final cfg2 = await service.readVoiceConfig();
    expect(cfg2, isNotNull);
    expect(cfg2!.voiceId, 'clone_xxxx');
    expect(cfg2.voicePreset, 'clone');
    expect(cfg2.voiceRecPath, '/path/to/ref.wav');
    expect(cfg2.isClone, true, reason: '克隆模式 isClone=true');
    expect(cfg2.isPreset, false, reason: '克隆模式 isPreset=false');

    // 克隆模式 voiceId 空 → readVoiceConfig 返回 null（未训练完）
    await service.setVoiceConfig(const VoiceConfig(
      voiceId: '',
      voicePreset: 'clone',
      voiceRecPath: '/path/to/ref.wav',
    ));
    expect(await service.readVoiceConfig(), null,
        reason: '克隆模式 voiceId 空视为未配置');

    // 清除配置
    await service.clearVoiceConfig();
    expect(await service.readVoiceConfig(), null,
        reason: 'clearVoiceConfig 后 readVoiceConfig 返回 null');

    // 验证 meta.json 浅合并：其他字段不受影响
    final store = service.store;
    await store.patchMeta({'lastSeenAt': 12345});
    await service.setVoiceConfig(const VoiceConfig(
      voiceId: '',
      voicePreset: '沉稳男声',
    ));
    final meta = await store.readMeta();
    expect(meta['lastSeenAt'], 12345, reason: 'voice 写入不影响 lastSeenAt');
    expect(meta['voicePreset'], '沉稳男声');
  });
}

