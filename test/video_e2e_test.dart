// 视频生成端到端验证：文生图 → 拿 URL → 创视频任务 → 轮询 → 下载 mp4
// 直接 dart run test/video_e2e_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _imageUrl = 'https://apihub.agnes-ai.com/v1/images/generations';
const _imageModel = 'agnes-image-2.1-flash';
const _videoUrl = 'https://apihub.agnes-ai.com/v1/videos';
const _videoQueryUrl = 'https://apihub.agnes-ai.com/agnesapi';
const _videoModel = 'agnes-video-v2.0';

const _idlePrompt =
    'The character stays in place with subtle breathing motion, '
    'occasional natural eye blinks, very slight head tilt, hair gently '
    'swaying in soft breeze, calm and warm cinematic lighting, '
    'consistent character identity, no large movement, loopable ambient scene';

String _loadKey() {
  final f = File('agnes.txt');
  if (!f.existsSync()) {
    throw Exception('agnes.txt 不存在');
  }
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.startsWith('API')) {
      final sep = t.contains('：') ? '：' : ':';
      final k = t.split(sep).sublist(1).join(sep).trim();
      if (k.isNotEmpty) return k;
    }
  }
  throw Exception('key missing');
}

Future<String> _genImage(String key) async {
  print('[1/4] 文生图……');
  final body = jsonEncode({
    'model': _imageModel,
    'prompt': '一位温柔气质的女性，日漫风格半身立绘，2.5D 体积感，柔和光线，干净背景，居中构图，竖版',
    'size': '1024x1024',
  });
  final resp = await http
      .post(Uri.parse(_imageUrl),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: body)
      .timeout(const Duration(seconds: 240));
  if (resp.statusCode != 200) {
    throw Exception('图像 HTTP ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final items = data['data'] as List;
  final url = (items[0] as Map<String, dynamic>)['url'] as String?;
  if (url == null || url.isEmpty) throw Exception('无 URL: ${resp.body}');
  print('     URL: $url');
  return url;
}

Future<String> _createVideo(String key, String imgUrl) async {
  print('[2/4] 创建视频任务……');
  final body = jsonEncode({
    'model': _videoModel,
    'prompt': _idlePrompt,
    'image': imgUrl,
    'num_frames': 121,
    'frame_rate': 24,
  });
  final resp = await http
      .post(Uri.parse(_videoUrl),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: body)
      .timeout(const Duration(seconds: 180));
  if (resp.statusCode != 200) {
    throw Exception('创建视频 HTTP ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  print('     完整响应: ${resp.body}');
  final videoId = data['video_id'] as String?;
  if (videoId == null) throw Exception('无 video_id');
  print('     video_id: $videoId');
  return videoId;
}

Future<String> _pollVideo(String key, String videoId) async {
  print('[3/4] 轮询直到完成……');
  final start = DateTime.now();
  int lastProgress = -1;
  while (true) {
    if (DateTime.now().difference(start) > const Duration(minutes: 15)) {
      throw Exception('超时');
    }
    try {
      final uri = Uri.parse('$_videoQueryUrl?video_id=$videoId&model_name=$_videoModel');
      final resp = await http
          .get(uri, headers: {'Authorization': 'Bearer $key'})
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        print('     查询 HTTP ${resp.statusCode}: ${resp.body}');
      } else {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = data['status'] as String?;
        final progress = data['progress'] as int? ?? 0;
        if (progress != lastProgress) {
          print('     status=$status progress=$progress');
          lastProgress = progress;
        }
        if (status == 'completed') {
          final url = data['remixed_from_video_id'] as String?;
          print('     完整完成响应: ${resp.body}');
          if (url == null || !url.startsWith('http')) {
            throw Exception('完成但 URL 异常: ${resp.body}');
          }
          return url;
        }
        if (status == 'failed') {
          throw Exception('视频失败: ${resp.body}');
        }
      }
    } catch (e) {
      print('     轮询异常: $e');
    }
    await Future.delayed(const Duration(seconds: 5));
  }
}

Future<void> _download(String url) async {
  print('[4/4] 下载 mp4……');
  final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 180));
  if (resp.statusCode != 200) {
    throw Exception('下载 HTTP ${resp.statusCode}');
  }
  final out = File('test/_e2e_video.mp4');
  await out.writeAsBytes(resp.bodyBytes);
  print('     保存: ${out.path}  ${resp.bodyBytes.length} bytes');
}

Future<void> main() async {
  final key = _loadKey();
  print('key loaded: ${key.substring(0, 12)}...');
  final imgUrl = await _genImage(key);
  final vid = await _createVideo(key, imgUrl);
  final mp4Url = await _pollVideo(key, vid);
  print('     mp4 URL: $mp4Url');
  await _download(mp4Url);
  print('\n=== 端到端通过 ===');
}
