import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// ARK coding endpoint（实际底层 GLM-5.2）
const _arkBase = 'https://ark.cn-beijing.volces.com/api/coding/v3';
const _arkModel = 'ark-code-latest';

/// 从项目根 lumora.txt 读 API key
Future<String> loadApiKey() async {
  // 优先从环境变量
  final env = Platform.environment['LUMORA_API_KEY'];
  if (env != null && env.isNotEmpty) return env;

  // 找 lumora.txt：从可执行文件目录向上找，或从当前目录找
  final candidates = <File>[];
  // 当前工作目录
  candidates.add(File('lumora.txt'));
  // 可执行文件目录及向上
  final exeDir = File(Platform.resolvedExecutable).parent;
  for (var d = exeDir; d.path != d.parent.path; d = d.parent) {
    candidates.add(File('${d.path}/lumora.txt'));
  }

  for (final f in candidates) {
    if (await f.exists()) {
      final lines = await f.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('API')) {
          final sep = trimmed.contains('：') ? '：' : ':';
          final key = trimmed.split(sep).sublist(1).join(sep).trim();
          if (key.isNotEmpty) return key;
        }
      }
    }
  }
  throw Exception('lumora.txt not found or API key missing');
}

class LlmResponse {
  final String content;
  LlmResponse(this.content);
}

Future<LlmResponse> chat(
  String system,
  List<Map<String, String>> messages, {
  double temperature = 0.85,
  int maxTokens = 800,
}) async {
  final apiKey = await loadApiKey();
  final url = Uri.parse('$_arkBase/chat/completions');
  final body = jsonEncode({
    'model': _arkModel,
    'messages': [
      {'role': 'system', 'content': system},
      ...messages,
    ],
    'temperature': temperature,
    'max_tokens': maxTokens,
    'thinking': {'type': 'disabled'},
  });

  final resp = await http.post(
    url,
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: body,
  ).timeout(const Duration(seconds: 60));

  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
  }

  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final choices = data['choices'] as List;
  if (choices.isEmpty) throw Exception('empty choices');
  final msg = choices[0]['message'] as Map<String, dynamic>;
  return LlmResponse((msg['content'] as String?) ?? '');
}
