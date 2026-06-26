import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// v2.0 TTS 声音输出
///
/// 火山引擎豆包语音克隆 + 语音合成。结构参考 agnes.dart：
/// - _loadApiKey 照 agnes.dart L51-80 模式（环境变量 → voice.txt → exe 目录 → docs 目录）
/// - 轮询照 pollVideoUntilDone 模式
/// - 文件保存照 saveCustomSprite / downloadVideo 模式
///
/// 注意：火山豆包 API 的 endpoint / 请求体 / 响应格式基于公开文档推断，
/// 实际接入时需核对火山引擎控制台（语音技术 → 声音克隆 / 语音合成）。
/// 代码结构（http + Bearer + 轮询 + base64）是行业通用模式，细节可调整。

const _voiceCloneUrl = 'https://openspeech.bytedance.com/api/v1/voice_clone';
const _voiceCloneQueryUrl = 'https://openspeech.bytedance.com/api/v1/voice_clone/task';
const _ttsUrl = 'https://openspeech.bytedance.com/api/v1/tts';

/// 预设音色列表（onboarding 选项 A 用）。
/// voiceId 为空时，onboarding 保存时填入火山豆包对应预设 ID。
const voicePresets = <String>['温柔女声', '沉稳男声', '清亮少年'];

/// 声音配置（存 meta.json）
class VoiceConfig {
  final String voiceId;        // 火山豆包 voiceId（克隆完成返回 / 预设 ID）
  final String voicePreset;    // 'clone' | 预设名（温柔女声 等）
  final String? voiceRecPath;  // 克隆时的参考音频本地路径（可空）

  const VoiceConfig({
    required this.voiceId,
    required this.voicePreset,
    this.voiceRecPath,
  });

  bool get isClone => voicePreset == 'clone';
}

/// 从 voice.txt 读 API key（照 agnes.dart L51-80 模式）
Future<String> _loadApiKey() async {
  final env = Platform.environment['VOLC_API_KEY'];
  if (env != null && env.isNotEmpty) return env;

  final candidates = <File>[];
  candidates.add(File('voice.txt'));
  final exeDir = File(Platform.resolvedExecutable).parent;
  for (var d = exeDir; d.path != d.parent.path; d = d.parent) {
    candidates.add(File('${d.path}/voice.txt'));
  }
  try {
    final doc = await getApplicationDocumentsDirectory();
    candidates.add(File('${doc.path}/Lumora/voice.txt'));
  } catch (_) {}

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
  throw Exception('voice.txt 未找到或 API key 缺失。请在项目根创建 voice.txt，格式：API：你的_volc_key');
}

// ============================================================
// 声音克隆：上传参考音频 → 训练 → 拿 voiceId
// ============================================================

/// 创建声音克隆任务。referenceAudioPath 是用户上传的 3-10s 参考音频。
/// 返回 taskId，后续用 pollVoiceCloneUntilDone 轮询。
Future<String> createVoiceCloneTask(String referenceAudioPath) async {
  final apiKey = await _loadApiKey();
  final bytes = await File(referenceAudioPath).readAsBytes();
  final base64Audio = base64Encode(bytes);
  final ext = referenceAudioPath.toLowerCase().endsWith('.wav') ? 'wav' : 'mp3';

  final resp = await http.post(
    Uri.parse(_voiceCloneUrl),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: jsonEncode({
      'audio': base64Audio,
      'audio_format': ext,
      'language': 'zh',
    }),
  ).timeout(const Duration(seconds: 180));

  if (resp.statusCode != 200) {
    throw Exception('声音克隆任务创建失败 HTTP ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final taskId = (data['data']?['task_id'] ?? data['task_id']) as String?;
  if (taskId == null || taskId.isEmpty) {
    throw Exception('声音克隆未返回 task_id: ${resp.body}');
  }
  return taskId;
}

/// 查询声音克隆任务状态
Future<Map<String, dynamic>> queryVoiceCloneTask(String taskId) async {
  final apiKey = await _loadApiKey();
  final resp = await http.get(
    Uri.parse('$_voiceCloneQueryUrl/$taskId'),
    headers: {'Authorization': 'Bearer $apiKey'},
  ).timeout(const Duration(seconds: 30));
  if (resp.statusCode != 200) {
    throw Exception('查询克隆状态失败 HTTP ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  return (data['data'] as Map<String, dynamic>?) ?? data;
}

/// 轮询直到声音克隆完成，返回 voiceId
Future<String> pollVoiceCloneUntilDone(
  String taskId, {
  Duration interval = const Duration(seconds: 5),
  Duration timeout = const Duration(minutes: 10),
  void Function(int progress)? onProgress,
}) async {
  final start = DateTime.now();
  while (true) {
    if (DateTime.now().difference(start) > timeout) {
      throw Exception('声音克隆超时');
    }
    try {
      final status = await queryVoiceCloneTask(taskId);
      final state = (status['status'] as String?) ?? 'unknown';
      final progress = (status['progress'] as num?)?.toInt() ?? 0;
      onProgress?.call(progress);
      if (state == 'success' || state == 'completed') {
        final vid = (status['voice_id'] ?? status['voiceId']) as String?;
        if (vid == null || vid.isEmpty) {
          throw Exception('克隆完成但无 voice_id: $status');
        }
        return vid;
      }
      if (state == 'failed') {
        throw Exception('声音克隆失败: ${status['error'] ?? status['message'] ?? "未知错误"}');
      }
    } catch (e) {
      // 单次查询失败不终止，等下一轮（网络抖动等）
    }
    await Future.delayed(interval);
  }
}

// ============================================================
// TTS 合成
// ============================================================

/// 用 voiceId 合成文本，返回 mp3 bytes
Future<List<int>> synthesizeVoice(String text, String voiceId) async {
  final apiKey = await _loadApiKey();
  final resp = await http.post(
    Uri.parse(_ttsUrl),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: jsonEncode({
      'voice_id': voiceId,
      'text': text,
      'audio_format': 'mp3',
      'speed': 1.0,
    }),
  ).timeout(const Duration(seconds: 60));
  if (resp.statusCode != 200) {
    throw Exception('TTS 合成失败 HTTP ${resp.statusCode}: ${resp.body}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final audioStr = (data['data']?['audio'] ?? data['audio']) as String?;
  if (audioStr == null || audioStr.isEmpty) {
    throw Exception('TTS 未返回音频: ${resp.body}');
  }
  return base64Decode(audioStr);
}

// ============================================================
// 音频文件保存（照 agnes.dart saveCustomSprite / downloadVideo 模式）
// ============================================================

Future<String> _audioDir() async {
  final doc = await getApplicationDocumentsDirectory();
  final dir = Directory('${doc.path}/Lumora/voices');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir.path;
}

/// 保存 TTS 音频到 <docs>/Lumora/voices/<spiritId>/<msgId>.mp3
Future<String> saveTtsAudio(String spiritId, String msgId, List<int> mp3Bytes) async {
  final dir = await _audioDir();
  final spiritDir = Directory('$dir/$spiritId');
  if (!await spiritDir.exists()) await spiritDir.create(recursive: true);
  final path = '${spiritDir.path}/$msgId.mp3';
  await File(path).writeAsBytes(mp3Bytes);
  return path;
}

/// 缓存命中检查：若本地音频文件存在且非空，返回路径；否则 null
Future<String?> cachedTtsPath(String spiritId, String msgId) async {
  final dir = await _audioDir();
  final f = File('$dir/$spiritId/$msgId.mp3');
  if (await f.exists() && (await f.length()) > 1000) return f.path;
  return null;
}

// ============================================================
// VoicePlayer：media_kit 纯音频封装（照 loop_video_view.dart 去 VideoController）
// ============================================================

class VoicePlayer {
  Player? _player;
  StreamSubscription<bool>? _completedSub;
  void Function()? onComplete;
  bool _isPlaying = false;

  VoicePlayer({this.onComplete});

  bool get isPlaying => _isPlaying;

  Future<void> play(String path) async {
    await stop();
    _player ??= Player();
    _completedSub ??= _player!.stream.completed.listen((done) {
      if (done) {
        _isPlaying = false;
        onComplete?.call();
      }
    });
    await _player!.open(Media(path));
    _isPlaying = true;
  }

  Future<void> stop() async {
    if (_player != null && _isPlaying) {
      try {
        await _player!.stop();
      } catch (_) {}
      _isPlaying = false;
    }
  }

  Future<void> dispose() async {
    await _completedSub?.cancel();
    _completedSub = null;
    await _player?.dispose();
    _player = null;
  }
}
