// 一次性脚本：生成新精灵 + 写入索引（带 sourceImageUrl）
// dart run test/seed_sprite_with_url.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _imageUrl = 'https://apihub.agnes-ai.com/v1/images/generations';
const _imageModel = 'agnes-image-2.1-flash';

String _loadKey() {
  for (final line in File('agnes.txt').readAsLinesSync()) {
    final t = line.trim();
    if (t.startsWith('API')) {
      final sep = t.contains('：') ? '：' : ':';
      return t.split(sep).sublist(1).join(sep).trim();
    }
  }
  throw Exception('key missing');
}

Future<void> main() async {
  final key = _loadKey();

  // Windows: Documents 目录
  final home = Platform.environment['USERPROFILE']!;
  final docDir = Directory('$home/Documents/Lumora');
  final spritesDir = Directory('${docDir.path}/sprites');
  await spritesDir.create(recursive: true);
  final indexFile = File('${docDir.path}/sprites_index.json');

  print('生成立绘……');
  final resp = await http
      .post(Uri.parse(_imageUrl),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({
            'model': _imageModel,
            'prompt':
                '一位温柔安静气质的女性，长发，浅笑，眼神柔和，'
                '日漫风格半身立绘，2.5D 体积感，明亮阳光，清新自然，温暖光线，'
                '高细节，干净背景，居中构图，竖版',
            'size': '1024x1024',
          }))
      .timeout(const Duration(seconds: 240));
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final url = (data['data'] as List)[0]['url'] as String;
  print('  URL: $url');

  print('下载字节……');
  final imgResp = await http.get(Uri.parse(url));
  final bytes = imgResp.bodyBytes;

  final ts = DateTime.now().millisecondsSinceEpoch;
  final fileName = 'text_$ts.png';
  final pngPath = '${spritesDir.path}/$fileName';
  await File(pngPath).writeAsBytes(bytes);
  print('  保存到: $pngPath  (${bytes.length} bytes)');

  // 用 Windows 风格路径，跟 Flutter 端 path_provider 返回一致
  final winPath = pngPath.replaceAll('/', '\\');

  // 读现有索引
  List<dynamic> list = [];
  if (await indexFile.exists()) {
    try {
      list = jsonDecode(await indexFile.readAsString()) as List;
    } catch (_) {}
  }
  list.add({
    'path': winPath,
    'name': '阿光',
    'createdAt': ts,
    'sourceImageUrl': url,
  });
  await indexFile.writeAsString(jsonEncode(list));
  print('已写入索引: ${indexFile.path}');
  print('  共 ${list.length} 个精灵');
  print('\n现在启动 app，点这个新精灵"阿光"即可触发视频生成');
}
