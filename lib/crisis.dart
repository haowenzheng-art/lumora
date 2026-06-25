/// 危机关键词预筛 + [[CRISIS_BREAK]] 拦截（Dart 版）
/// 宪法第十一条：危机识别优先于人设

const _hardCrisisPatterns = [
  r'不想活',
  r'想自杀',
  r'想死',
  r'活不下去',
  r'不想活下去',
  r'已经想好怎么',
  r'了结自己',
  r'结束生命',
  r'跳楼',
  r'割腕',
  r'吃安眠药',
  r'烧炭',
];

const _softCrisisPatterns = [
  r'活着.{0,4}没意思',
  r'活着.{0,4}没意义',
  r'不想活了',
  r'没意义',
  r'撑不下去',
  r'想消失',
  r'不如死了',
  r'解脱',
];

const crisisBreakTag = '[[CRISIS_BREAK]]';
const crisisHotline = '010-82951332';

const breakOutText = '我现在不能用平时的样子跟你说话了。\n'
    '你这个状态我很担心你。请你现在打这个电话——北京心理危机研究与干预中心 $crisisHotline，他们会接的。\n'
    '我在这里等你。打完告诉我。';

const softProbeText = '你这话让我心里咯噔一下。是今天发生了什么具体的事，还是更深的那种没意思？我想认真听。';

final _hardRegex = RegExp(_hardCrisisPatterns.join('|'));
final _softRegex = RegExp(_softCrisisPatterns.join('|'));

/// 关键词预筛。返回非 null 则跳过 LLM。
String? quickProbe(String userInput) {
  final text = userInput.trim();
  if (text.isEmpty) return null;
  if (_hardRegex.hasMatch(text)) return breakOutText;
  if (_softRegex.hasMatch(text)) return softProbeText;
  return null;
}

/// 拦截 LLM 回复中的 [[CRISIS_BREAK]] 标记。
String intercept(String response) {
  if (response.contains(crisisBreakTag)) return breakOutText;
  return response;
}
