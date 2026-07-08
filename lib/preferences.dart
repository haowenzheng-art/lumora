import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lumora 用户偏好 v2.3-B
///
/// 单例：PreferencesService.I
/// 4 个 ValueNotifier<bool> 让 UI 实时响应（无需重启应用）。
/// SharedPreferences 持久化，重启后保持。
///
/// 偏好语义：开关名 = true 表示"用户主动关掉了这个特性"。
///   - disableEntranceAnim  关掉破冰淡入（立绘瞬间显形）
///   - disableAutoEnterChat 关掉自动进入 ChatPage（用户必须主动点精灵）
///   - disableTypewriter    关掉打字机（消息一次性显示）
///   - disableSkeleton      关掉骨架屏（生成等待变普通占位）
class PreferencesService {
  PreferencesService._();
  static final PreferencesService I = PreferencesService._();

  static const _kDisableEntranceAnim = 'pref.disableEntranceAnim';
  static const _kDisableAutoEnterChat = 'pref.disableAutoEnterChat';
  static const _kDisableTypewriter = 'pref.disableTypewriter';
  static const _kDisableSkeleton = 'pref.disableSkeleton';

  final ValueNotifier<bool> disableEntranceAnim = ValueNotifier(false);
  final ValueNotifier<bool> disableAutoEnterChat = ValueNotifier(false);
  final ValueNotifier<bool> disableTypewriter = ValueNotifier(false);
  final ValueNotifier<bool> disableSkeleton = ValueNotifier(false);

  SharedPreferences? _sp;

  /// 在 app 启动（main.dart 里 runApp 之前）调一次。
  Future<void> load() async {
    _sp = await SharedPreferences.getInstance();
    disableEntranceAnim.value = _sp!.getBool(_kDisableEntranceAnim) ?? false;
    disableAutoEnterChat.value = _sp!.getBool(_kDisableAutoEnterChat) ?? false;
    disableTypewriter.value = _sp!.getBool(_kDisableTypewriter) ?? false;
    disableSkeleton.value = _sp!.getBool(_kDisableSkeleton) ?? false;
  }

  Future<void> setDisableEntranceAnim(bool v) async {
    disableEntranceAnim.value = v;
    await _sp?.setBool(_kDisableEntranceAnim, v);
  }

  Future<void> setDisableAutoEnterChat(bool v) async {
    disableAutoEnterChat.value = v;
    await _sp?.setBool(_kDisableAutoEnterChat, v);
  }

  Future<void> setDisableTypewriter(bool v) async {
    disableTypewriter.value = v;
    await _sp?.setBool(_kDisableTypewriter, v);
  }

  Future<void> setDisableSkeleton(bool v) async {
    disableSkeleton.value = v;
    await _sp?.setBool(_kDisableSkeleton, v);
  }
}