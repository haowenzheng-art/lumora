/// "最后想跟你说的话" 触发与拦截（Dart 版）
///
/// 仿 crisis.dart 模式，但语义不同：
/// - crisis：关键词命中即破出角色，跳过 LLM
/// - final_words：关键词只是 hint，让 LLM 在 system prompt 里注意到告别意图，
///   最终由 LLM 判断是否输出 [[FINAL_WORDS]] 标记。agent 层拦截标记后替换为
///   用户在 onboarding 写下的"最后想跟你说的话"原文。
///
/// 设计理由：告别意图需要语境判断（"我要走了"可能是下班，也可能是永别），
/// 不应由关键词直接触发。LLM 拿到 hint + 完整对话上下文后判断更准确。

const _hardFarewellPatterns = [
  r'不再来了',
  r'不再找你',
  r'最后一次找你',
  r'以后都不来了',
  r'决定不再',
  r'决定离开',
  r'不再联系',
  r'再也不',
];

const _softFarewellPatterns = [
  r'我要走了',
  r'我走了',
  r'可能不再来了',
  r'可能不来了',
  r'也许不再',
  r'以后可能不来了',
  r'可能不再找你',
  r'不再见了',
  r'告别',
];

const finalWordsTag = '[[FINAL_WORDS]]';

/// system prompt 里给 LLM 的告别提示规则（仅当 finalWords 存在且未交付时注入）
const farewellHintRule = '''

【关于告别】
如果用户表达告别意图（"不再来了"/"最后一次找你"/"决定离开"等），且你感觉到这是真正的离别而非暂时离开，请在回复开头输出 [[FINAL_WORDS]] 标记，然后不再说其他任何内容。agent 层会把这个标记替换为用户在创建你时写下的"最后想跟你说的话"原文。
不要轻易触发——只在用户明确表达终止这段关系的意图时使用。"我要走了"/"再见"等模糊表达不构成触发条件，你应该继续像平时一样对话。
''';

final _hardRegex = RegExp(_hardFarewellPatterns.join('|'));
final _softRegex = RegExp(_softFarewellPatterns.join('|'));

/// 检测用户消息是否含告别信号。
/// - 返回 'hard'：明确告别（"不再来了"等）—— LLM 应认真评估是否触发
/// - 返回 'soft'：模糊告别（"我要走了"等）—— LLM 应谨慎，通常不触发
/// - 返回 null：无信号
String? hasFarewellSignal(String userInput) {
  final text = userInput.trim();
  if (text.isEmpty) return null;
  if (_hardRegex.hasMatch(text)) return 'hard';
  if (_softRegex.hasMatch(text)) return 'soft';
  return null;
}

/// 拦截 LLM 回复中的 [[FINAL_WORDS]] 标记。
/// 命中则替换为 finalWordsText（用户在 onboarding 写下的"最后想跟你说的话"）。
/// 若 finalWordsText 为空（用户没写过），保留原文不替换——让 LLM 回复正常显示。
String intercept(String response, String finalWordsText) {
  if (!response.contains(finalWordsTag)) return response;
  final trimmed = finalWordsText.trim();
  if (trimmed.isEmpty) return response.replaceAll(finalWordsTag, '').trim();
  return trimmed;
}
