import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
/// v2.1 起预设音色走 Edge TTS（免费免 key）；克隆走火山豆包（需 voice.txt）。
const voicePresets = <String>['温柔女声', '沉稳男声', '清亮少年'];

/// 预设音色 → Edge TTS voice 名映射
const _edgeVoiceMap = <String, String>{
  '温柔女声': 'zh-CN-XiaoxiaoNeural',
  '沉稳男声': 'zh-CN-YunxiNeural',
  '清亮少年': 'zh-CN-XiaoyiNeural',
};

/// 声音配置（存 meta.json）
class VoiceConfig {
  final String voiceId;        // 火山豆包 voiceId（克隆完成返回）
  final String voicePreset;    // 'clone' | 预设名（温柔女声 等）
  final String? voiceRecPath;  // 克隆时的参考音频本地路径（可空）

  const VoiceConfig({
    required this.voiceId,
    required this.voicePreset,
    this.voiceRecPath,
  });

  bool get isClone => voicePreset == 'clone';
  bool get isPreset => !isClone && voicePreset.isNotEmpty;
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
// TTS 合成（分流：克隆→火山豆包，预设→Edge TTS 免费）
// ============================================================

/// 按 VoiceConfig 合成文本，返回 mp3 bytes。
/// - isClone → 火山豆包（需 voice.txt）
/// - isPreset → Edge TTS（免费免 key）
Future<List<int>> synthesizeVoice(String text, VoiceConfig config) async {
  if (config.isClone) {
    return _synthesizeWithVolc(text, config.voiceId);
  }
  if (config.isPreset) {
    return EdgeTtsClient.synthesize(text, config.voicePreset);
  }
  throw Exception('VoiceConfig 既非 clone 也非 preset: ${config.voicePreset}');
}

/// 火山豆包 TTS 合成（克隆音色专用）
Future<List<int>> _synthesizeWithVolc(String text, String voiceId) async {
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
// Edge TTS（微软免费 TTS，无需 API key）
//
// 通过 wss://speech.platform.bing.com 的 WebSocket 协议调用。
// 协议要点：
//   1. 连接时带 TrustedClientToken + ConnectionId
//   2. 发送 speech.config 消息（指定 outputFormat）
//   3. 发送 ssml 消息（含 voice name + 文本）
//   4. 接收二进制音频帧（前 2 字节 type, 2 字节 length, 后是 payload）
//   5. 接收 Path:turn.end 表示结束
//
// Token 是微软公开的 Edge 浏览器读屏 token，非密钥。
// ============================================================

class EdgeTtsClient {
  static const _wsUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  static const _token = '6A5AA1D4EAFF4E9FB37E23D68482D6F5';

  /// 合成文本，返回 mp3 bytes
  static Future<List<int>> synthesize(
    String text,
    String presetName, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final voice = _edgeVoiceMap[presetName] ?? 'zh-CN-XiaoxiaoNeural';
    final connId = _uuidV4NoDash();
    final uri = Uri.parse('$_wsUrl?TrustedClientToken=$_token&ConnectionId=$connId');

    final channel = WebSocketChannel.connect(uri);

    // 1. 发送 speech.config
    final configTs = _timestamp();
    final configMsg =
        'X-Timestamp:$configTs\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
    channel.sink.add(configMsg);

    // 2. 发送 ssml
    final reqId = _uuidV4NoDash();
    final ssmlTs = _timestamp();
    final escaped = _escapeXml(text);
    final ssml =
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>"
        "<voice name='$voice'>$escaped</voice></speak>";
    final ssmlMsg =
        'X-RequestId:$reqId\r\nContent-Type:application/ssml+xml\r\n'
        'X-Timestamp:$ssmlTs\r\nPath:ssml\r\n\r\n$ssml';
    channel.sink.add(ssmlMsg);

    // 3. 接收音频帧 + 等待 turn.end
    final audio = <int>[];
    final completer = Completer<List<int>>();
    late StreamSubscription sub;
    sub = channel.stream.listen(
      (msg) {
        if (msg is String) {
          if (msg.contains('Path:turn.end')) {
            sub.cancel();
            channel.sink.close();
            if (!completer.isCompleted) completer.complete(audio);
          }
        } else if (msg is List<int>) {
          // 二进制帧：前 2 字节 type（大端 uint16）, 2 字节 length, 后是 payload
          if (msg.length >= 4) {
            final typeHi = msg[0];
            if (typeHi == 0x02) {
              // 音频帧
              final len = (msg[2] << 8) | msg[3];
              if (msg.length >= 4 + len) {
                audio.addAll(msg.sublist(4, 4 + len));
              }
            }
          }
        }
      },
      onError: (e) {
        sub.cancel();
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        sub.cancel();
        if (!completer.isCompleted) completer.complete(audio);
      },
    );

    try {
      return await completer.future.timeout(timeout);
    } catch (e) {
      await sub.cancel();
      try {
        await channel.sink.close();
      } catch (_) {}
      rethrow;
    }
  }

  static String _uuidV4NoDash() {
    final r = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    r[6] = (r[6] & 0x0F) | 0x40;
    r[8] = (r[8] & 0x3F) | 0x80;
    return r.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _timestamp() {
    return DateTime.now().toUtc().toIso8601String();
  }

  static String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll("'", '&apos;')
        .replaceAll('"', '&quot;');
  }
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
