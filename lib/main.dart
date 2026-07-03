import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'agnes.dart';
import 'llm.dart';
import 'prompt.dart';
import 'crisis.dart';
import 'final_words.dart' as fw;
import 'sprite_view.dart';
import 'sprite_parts.dart';
import 'loop_video_view.dart';
import 'memory/memory_service.dart';
import 'memory/migrate.dart';
import 'memory/types.dart';
import 'voice.dart';
import 'theme.dart';
import 'widgets/pressable.dart';
import 'widgets/fade_scale_route.dart';
import 'widgets/empty_state.dart';
import 'widgets/skeleton_box.dart';

void main() {
  MediaKit.ensureInitialized();
  runApp(const LumoraApp());
}

class LumoraApp extends StatelessWidget {
  const LumoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    // v2.2: 全局默认 Inter（西文）+ 中文 fallback；情感位用 theme.dart 的 Noto Serif SC 覆盖
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFE8B576),
        secondary: Color(0xFF8B9DC3),
        surface: Color(0xFF0E1424),
      ),
    );
    return MaterialApp(
      title: 'Lumora',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
        primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
      ),
      home: const SplashPage(),
    );
  }
}

// ============================================================
// 色彩系统
// ============================================================

class LumoraColors {
  static const bgTop = Color(0xFF1A2138);
  static const bgBottom = Color(0xFF070A14);
  static const glass = Color(0x14FFFFFF);
  static const glassBorder = Color(0x24FFFFFF);
  static const amber = Color(0xFFE8B576);
  static const amberSoft = Color(0x33E8B576);
  static const moonBlue = Color(0xFF8B9DC3);
  static const textPrimary = Color(0xFFF2E9DC);
  static const textSecondary = Color(0xFF9B8FB5);
  static const textMuted = Color(0xFF5A5070);
  static const userBubble = Color(0x40E8B576);
  static const assistantBubble = Color(0x1A8B9DC3);
}

// ============================================================
// 气质标签（真实气质路线，不走二次元 tropes）
// ============================================================
const _kTemperaments = <String>[
  '温柔', '灵动', '沉稳', '清冷', '阳光', '文艺', '酷飒', '治愈',
];

// ============================================================
// 启动页：选择精灵
// ============================================================

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  List<SpriteRecord> _mySprites = [];

  @override
  void initState() {
    super.initState();
    buildSystemPrompt();
    _refreshIndex();
  }

  Future<void> _refreshIndex() async {
    final list = await loadSpriteIndex();
    if (!mounted) return;
    setState(() {
      _mySprites = list..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  Future<void> _openTextCustom() async {
    final result = await Navigator.push<_CustomResult>(
      context,
      FadeScaleRoute(builder: (_) => const TextCustomPage()),
    );
    if (result != null) _afterSpirit(result, isCustom: true);
  }

  Future<void> _openPhotoCustom() async {
    final result = await Navigator.push<_CustomResult>(
      context,
      FadeScaleRoute(builder: (_) => const PhotoCustomPage()),
    );
    if (result != null) _afterSpirit(result, isCustom: true);
  }

  Future<void> _enterPreset(String spritePath, String name) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      FadeScaleRoute(
        builder: (_) => SpiritScenePage(
          spritePath: spritePath,
          spiritName: name,
          sourceImageUrl: null,
        ),
      ),
    );
  }

  String _spiritIdFromPath(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final name = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _afterSpirit(_CustomResult result, {bool isCustom = false}) async {
    final spritePath = result.spritePath;
    if (!mounted) return;
    final name = await Navigator.push<String>(
      context,
      FadeScaleRoute(builder: (_) => NamePage(spritePath: spritePath)),
    );
    if (name == null || !mounted) return;

    final spiritId = _spiritIdFromPath(spritePath);
    final setup = await Navigator.push<MemorySetupResult>(
      context,
      FadeScaleRoute(
        builder: (_) => MemoryOnboardingPage(
          spiritId: spiritId,
          spiritName: name,
          spritePath: spritePath,
          initialProfile: '',
          initialSeeds: const [],
          initialFinalWords: '',
        ),
      ),
    );
    if (setup == null || !mounted) return;

    final memory = MemoryService(spiritId: spiritId);
    await memory.writeProfile(setup.profile);
    await memory.replaceSeedEvents(setup.seedEvents);
    await memory.writeFinalWords(setup.finalWords);

    // v2.0: 保存声音配置
    if (setup.voiceConfig != null) {
      final vc = setup.voiceConfig!;
      if (vc.isClone && vc.voiceId.isEmpty) {
        // 克隆真人声音：需要训练
        if (!mounted) return;
        final voiceId = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _VoiceCloneProgressDialog(recPath: vc.voiceRecPath!),
        );
        if (voiceId != null && voiceId.isNotEmpty) {
          await memory.setVoiceConfig(VoiceConfig(
            voiceId: voiceId,
            voicePreset: 'clone',
            voiceRecPath: vc.voiceRecPath,
          ));
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('声音克隆失败，可稍后在记忆编辑页重试。')),
          );
        }
      } else {
        await memory.setVoiceConfig(vc);
      }
    }

    if (isCustom) {
      await addSpriteToIndex(SpriteRecord(
        path: spritePath,
        name: name,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        sourceImageUrl: result.sourceImageUrl,
      ));
      await _refreshIndex();
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      FadeScaleRoute(
        builder: (_) => SpiritScenePage(
          spritePath: spritePath,
          spiritName: name,
          sourceImageUrl: result.sourceImageUrl,
        ),
      ),
    );
    if (!mounted) return;
    _refreshIndex();
  }

  Future<void> _enterExisting(SpriteRecord r) async {
    await Navigator.push(
      context,
      FadeScaleRoute(
        builder: (_) => SpiritScenePage(
          spritePath: r.path,
          spiritName: r.name,
          sourceImageUrl: r.sourceImageUrl,
        ),
      ),
    );
    if (!mounted) return;
    _refreshIndex();
  }

  Future<void> _confirmDelete(SpriteRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2138),
        title: const Text('删除这只精灵？',
            style: TextStyle(color: LumoraColors.textPrimary, fontSize: 15)),
        content: Text('"${r.name}" 会被永久删除，对话记录会保留。',
            style: const TextStyle(
                color: LumoraColors.textSecondary, fontSize: 12, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
                style: TextStyle(color: LumoraColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: LumoraColors.amber)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await removeSpriteFromIndex(r.path);
      await _refreshIndex();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundGradient(),
          ..._buildParticles(60),
          SafeArea(child: Center(child: _buildMainView())),
        ],
      ),
    );
  }

  Widget _buildMainView() {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Lumora',
            style: LumoraTextStyles.displayStyle(),
          ),
          const SizedBox(height: 12),
          Text(
            '陪你走过这段。',
            style: LumoraTextStyles.letterStyle(),
          ),
          Text(
            '然后，希望你不再需要我。',
            style: LumoraTextStyles.letterStyle(),
          ),
          const SizedBox(height: 72),
          const Text(
            '选一只精灵',
            style: TextStyle(
              fontSize: 13,
              color: LumoraColors.textSecondary,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SpiritChoice(
                name: '温柔',
                asset: 'agent_data/xiaoyu/sprites/spirit_gentle.png',
                onTap: () => _enterPreset(
                  'agent_data/xiaoyu/sprites/spirit_gentle.png',
                  '温柔',
                ),
              ),
              const SizedBox(width: 48),
              _SpiritChoice(
                name: '灵动',
                asset: 'agent_data/xiaoyu/sprites/spirit_lively.png',
                onTap: () => _enterPreset(
                  'agent_data/xiaoyu/sprites/spirit_lively.png',
                  '灵动',
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),
          if (_mySprites.isNotEmpty) ...[
            const Text(
              '我的精灵',
              style: TextStyle(
                fontSize: 12,
                color: LumoraColors.textSecondary,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                itemCount: _mySprites.length,
                separatorBuilder: (_, __) => const SizedBox(width: 18),
                itemBuilder: (ctx, i) {
                  final r = _mySprites[i];
                  return _MySpriteCard(
                    record: r,
                    onTap: () => _enterExisting(r),
                    onLongPress: () => _confirmDelete(r),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
          ] else ...[
            const SizedBox(height: 24),
            EmptyState(
              message: '还没有人被你想起',
              hint: '定制一只属于你的精灵，让 ta 陪你走过一段。',
              actionLabel: '记住第一个 ta',
              onAction: _openTextCustom,
            ),
            const SizedBox(height: 24),
          ],
          const Text(
            '或者，定制一只',
            style: TextStyle(
              fontSize: 12,
              color: LumoraColors.textMuted,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CustomButton(
                icon: Icons.edit_rounded,
                label: '文字描述',
                onTap: _openTextCustom,
              ),
              const SizedBox(width: 24),
              _CustomButton(
                icon: Icons.upload_rounded,
                label: '上传照片',
                onTap: _openPhotoCustom,
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _CustomResult {
  final String spritePath;
  final String? sourceImageUrl;
  _CustomResult(this.spritePath, {this.sourceImageUrl});
}

class _MySpriteCard extends StatelessWidget {
  final SpriteRecord record;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _MySpriteCard({
    required this.record,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        children: [
          Container(
            width: 90,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: LumoraColors.glassBorder,
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: LumoraColors.amber.withValues(alpha: 0.12),
                  blurRadius: 14,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _loadSpiritImage(record.path),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 90,
            child: Text(
              record.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: LumoraColors.textPrimary,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '长按删除',
            style: TextStyle(
              fontSize: 9,
              color: LumoraColors.textMuted,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 文生图自定义页：性别 + 气质 + 风格 + 自由描述
// ============================================================

class TextCustomPage extends StatefulWidget {
  const TextCustomPage({super.key});

  @override
  State<TextCustomPage> createState() => _TextCustomPageState();
}

class _TextCustomPageState extends State<TextCustomPage> {
  SpiritGender _gender = SpiritGender.female;
  final Set<String> _selectedTemps = {'温柔'};
  SpiritStyle _style = SpiritStyle.sunny;
  final TextEditingController _extra = TextEditingController();
  bool _generating = false;
  String _status = '';

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _status = '正在生成精灵……';
    });
    try {
      final result = await generateSpriteFromText(
        gender: _gender,
        temperaments: _selectedTemps.toList(),
        style: _style,
        extra: _extra.text,
      );
      final path = await saveCustomSprite(
        result.bytes,
        'text_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      Navigator.pop(context, _CustomResult(path, sourceImageUrl: result.remoteUrl));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _status = '';
      });
      _showError(context, '生成失败', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundGradient(),
          ..._buildParticles(40),
          SafeArea(
            child: _generating
                ? _buildGeneratingView(_status)
                : _buildForm(),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        _TopBar(title: '描述你的精灵', onBack: () => Navigator.pop(context)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('性别'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _RadioChip(
                      label: '女性',
                      selected: _gender == SpiritGender.female,
                      onTap: () => setState(() => _gender = SpiritGender.female),
                    ),
                    const SizedBox(width: 10),
                    _RadioChip(
                      label: '男性',
                      selected: _gender == SpiritGender.male,
                      onTap: () => setState(() => _gender = SpiritGender.male),
                    ),
                    const SizedBox(width: 10),
                    _RadioChip(
                      label: '中性',
                      selected: _gender == SpiritGender.neutral,
                      onTap: () => setState(() => _gender = SpiritGender.neutral),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionLabel('气质（可多选）'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _kTemperaments.map((t) {
                    final sel = _selectedTemps.contains(t);
                    return _RadioChip(
                      label: t,
                      selected: sel,
                      onTap: () => setState(() {
                        if (sel) {
                          _selectedTemps.remove(t);
                        } else {
                          _selectedTemps.add(t);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                _sectionLabel('画风'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _RadioChip(
                      label: '阳光日漫',
                      selected: _style == SpiritStyle.sunny,
                      onTap: () => setState(() => _style = SpiritStyle.sunny),
                    ),
                    const SizedBox(width: 10),
                    _RadioChip(
                      label: '清冷月色',
                      selected: _style == SpiritStyle.cool,
                      onTap: () => setState(() => _style = SpiritStyle.cool),
                    ),
                    const SizedBox(width: 10),
                    _RadioChip(
                      label: '暖调暮色',
                      selected: _style == SpiritStyle.warm,
                      onTap: () => setState(() => _style = SpiritStyle.warm),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionLabel('额外描述（选填）'),
                const SizedBox(height: 10),
                _GlassTextField(
                  controller: _extra,
                  hint: '例：短发，戴眼镜，穿白衬衫，浅笑',
                  maxLines: 3,
                ),
                const SizedBox(height: 32),
                Center(
                  child: _PrimaryButton(
                    label: '生成',
                    onTap: _selectedTemps.isEmpty ? null : _generate,
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    '生成大约 30-60 秒',
                    style: TextStyle(
                      fontSize: 11,
                      color: LumoraColors.textMuted,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 图生图自定义页
// ============================================================

class PhotoCustomPage extends StatefulWidget {
  const PhotoCustomPage({super.key});

  @override
  State<PhotoCustomPage> createState() => _PhotoCustomPageState();
}

class _PhotoCustomPageState extends State<PhotoCustomPage> {
  File? _photo;
  SpiritStyle _style = SpiritStyle.sunny;
  final TextEditingController _extra = TextEditingController();
  bool _generating = false;
  String _status = '';

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final p = result.files.first.path;
    if (p == null) return;
    setState(() => _photo = File(p));
  }

  Future<void> _generate() async {
    if (_photo == null) return;
    setState(() {
      _generating = true;
      _status = '正在从照片生成精灵……';
    });
    try {
      final result = await generateSpriteFromPhoto(
        photo: _photo!,
        style: _style,
        extra: _extra.text,
      );
      final path = await saveCustomSprite(
        result.bytes,
        'photo_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      Navigator.pop(context, _CustomResult(path, sourceImageUrl: result.remoteUrl));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _status = '';
      });
      _showError(context, '生成失败', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundGradient(),
          ..._buildParticles(40),
          SafeArea(
            child: _generating
                ? _buildGeneratingView(_status)
                : _buildForm(),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        _TopBar(title: '上传照片生成', onBack: () => Navigator.pop(context)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('照片'),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pick,
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: LumoraColors.glass,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: LumoraColors.glassBorder,
                        width: 0.8,
                      ),
                    ),
                    child: _photo == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: LumoraColors.amber.withValues(alpha: 0.7),
                                  size: 36,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  '点击选择图片',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: LumoraColors.textSecondary,
                                    letterSpacing: 3,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(_photo!, fit: BoxFit.cover),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionLabel('画风'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _RadioChip(
                      label: '阳光日漫',
                      selected: _style == SpiritStyle.sunny,
                      onTap: () => setState(() => _style = SpiritStyle.sunny),
                    ),
                    const SizedBox(width: 10),
                    _RadioChip(
                      label: '清冷月色',
                      selected: _style == SpiritStyle.cool,
                      onTap: () => setState(() => _style = SpiritStyle.cool),
                    ),
                    const SizedBox(width: 10),
                    _RadioChip(
                      label: '暖调暮色',
                      selected: _style == SpiritStyle.warm,
                      onTap: () => setState(() => _style = SpiritStyle.warm),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionLabel('额外要求（选填）'),
                const SizedBox(height: 10),
                _GlassTextField(
                  controller: _extra,
                  hint: '例：保留原图的眼镜和发型',
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                const Text(
                  '系统会自动保留原图的性别、年龄、五官、神态，无需在此重复。',
                  style: TextStyle(
                    fontSize: 11,
                    color: LumoraColors.textMuted,
                    letterSpacing: 1,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: _PrimaryButton(
                    label: '生成',
                    onTap: _photo == null ? null : _generate,
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    '生成大约 30-60 秒',
                    style: TextStyle(
                      fontSize: 11,
                      color: LumoraColors.textMuted,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 命名页
// ============================================================

class NamePage extends StatefulWidget {
  final String spritePath;
  const NamePage({super.key, required this.spritePath});

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  final TextEditingController _name = TextEditingController(text: '小雨');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _confirm() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundGradient(),
          ..._buildParticles(40),
          SafeArea(
            child: Column(
              children: [
                _TopBar(title: '给它起个名字', onBack: () => Navigator.pop(context)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                    child: Column(
                      children: [
                        Container(
                          width: 160,
                          height: 220,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: LumoraColors.glassBorder,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: LumoraColors.amber.withValues(alpha: 0.25),
                                blurRadius: 28,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: _loadSpiritImage(widget.spritePath),
                          ),
                        ),
                        const SizedBox(height: 36),
                        const Text(
                          '从今天开始，它叫——',
                          style: TextStyle(
                            fontSize: 13,
                            color: LumoraColors.textSecondary,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 260,
                          child: _GlassTextField(
                            controller: _name,
                            hint: '小雨',
                            maxLines: 1,
                            center: true,
                          ),
                        ),
                        const SizedBox(height: 40),
                        _PrimaryButton(label: '进入', onTap: _confirm),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class MemorySetupResult {
  final String profile;
  final List<MemoryEvent> seedEvents;
  final String finalWords;
  final VoiceConfig? voiceConfig;

  MemorySetupResult({
    required this.profile,
    required this.seedEvents,
    this.finalWords = '',
    this.voiceConfig,
  });
}

class _MemoryDraft {
  final TextEditingController title;
  final TextEditingController summary;
  final TextEditingController tags;
  String weight;
  final String id;
  final String date;
  final int createdAt;

  _MemoryDraft({
    String title = '',
    String summary = '',
    String tags = '',
    this.weight = '中',
    this.id = '',
    this.date = '',
    this.createdAt = 0,
  })  : title = TextEditingController(text: title),
        summary = TextEditingController(text: summary),
        tags = TextEditingController(text: tags);

  factory _MemoryDraft.fromEvent(MemoryEvent e) => _MemoryDraft(
        title: e.title,
        summary: e.summary,
        tags: e.tags.join('、'),
        weight: e.weight,
        id: e.id,
        date: e.date,
        createdAt: e.createdAt,
      );

  void dispose() {
    title.dispose();
    summary.dispose();
    tags.dispose();
  }
}

class MemoryOnboardingPage extends StatefulWidget {
  final String spiritId;
  final String spiritName;
  final String spritePath;
  final String initialProfile;
  final List<MemoryEvent> initialSeeds;
  final String initialFinalWords;
  final bool editMode;

  const MemoryOnboardingPage({
    super.key,
    required this.spiritId,
    required this.spiritName,
    required this.spritePath,
    required this.initialProfile,
    required this.initialSeeds,
    this.initialFinalWords = '',
    this.editMode = false,
  });

  @override
  State<MemoryOnboardingPage> createState() => _MemoryOnboardingPageState();
}

class _MemoryOnboardingPageState extends State<MemoryOnboardingPage> {
  // 各章节独立限制（v1.2 章节式 onboarding）
  static const int _maxKeyEvents = 5;
  static const int _maxTraits = 3;
  static const int _maxUnfinished = 2;

  late final TextEditingController _profile;
  late final TextEditingController _finalWords;
  late final MemoryService _memory;

  final List<_MemoryDraft> _keyEvents = [];
  final List<_MemoryDraft> _traits = [];
  final List<_MemoryDraft> _unfinished = [];

  // v1.3: 沉睡的记忆列表（仅 editMode 下加载）
  List<MemoryEvent> _dormant = [];

  // v2.0: 声音配置
  bool _voiceMode = false; // false=预设音色, true=克隆真人
  String _selectedPreset = voicePresets.first;
  String? _cloneAudioPath;

  @override
  void initState() {
    super.initState();
    _profile = TextEditingController(text: widget.initialProfile);
    _finalWords = TextEditingController(text: widget.initialFinalWords);
    _memory = MemoryService(spiritId: widget.spiritId);

    // 预填已有 seeds：按 tags 分流到对应章节
    if (widget.initialSeeds.isNotEmpty) {
      for (final e in widget.initialSeeds) {
        final draft = _MemoryDraft.fromEvent(e);
        if (e.tags.contains('性格')) {
          _traits.add(draft);
        } else if (e.tags.contains('未完成')) {
          _unfinished.add(draft);
        } else {
          _keyEvents.add(draft);
        }
      }
    }
    // 默认各章节给 1 张空卡（让用户看到结构）
    if (_keyEvents.isEmpty) _keyEvents.add(_MemoryDraft());
    if (_traits.isEmpty) _traits.add(_MemoryDraft());
    if (_unfinished.isEmpty) _unfinished.add(_MemoryDraft());

    // v1.3: editMode 下加载 dormant 列表
    if (widget.editMode) {
      _refreshDormant();
      _loadVoiceConfig(); // v2.0
    }
  }

  // v2.0: 加载已有声音配置
  Future<void> _loadVoiceConfig() async {
    final c = await _memory.readVoiceConfig();
    if (mounted && c != null) {
      setState(() {
        _voiceMode = c.isClone;
        _selectedPreset =
            c.voicePreset.isEmpty ? voicePresets.first : c.voicePreset;
        _cloneAudioPath = c.voiceRecPath;
      });
    }
  }

  // v2.0: 选择参考音频
  Future<void> _pickCloneAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result == null || result.files.single.path == null) return;
    setState(() => _cloneAudioPath = result.files.single.path);
  }

  Future<void> _refreshDormant() async {
    final list = await _memory.listDormantEvents();
    if (mounted) setState(() => _dormant = list);
  }

  @override
  void dispose() {
    _profile.dispose();
    _finalWords.dispose();
    for (final d in [..._keyEvents, ..._traits, ..._unfinished]) {
      d.dispose();
    }
    super.dispose();
  }

  List<String> _parseTags(String raw) => raw
      .split(RegExp(r'[、,，\s]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  List<String> _ensureTag(List<String> tags, String tag) {
    if (tags.contains(tag)) return tags;
    return [tag, ...tags];
  }

  void _addDraft(List<_MemoryDraft> list, int maxCount) {
    if (list.length >= maxCount) return;
    setState(() => list.add(_MemoryDraft()));
  }

  void _removeDraft(List<_MemoryDraft> list, int index) {
    if (index < 0 || index >= list.length) return;
    final d = list.removeAt(index);
    d.dispose();
    if (list.isEmpty) list.add(_MemoryDraft());
    setState(() {});
  }

  void _confirm() {
    final events = <MemoryEvent>[];

    void collect(List<_MemoryDraft> list, String sectionTag) {
      for (final d in list) {
        final summary = d.summary.text.trim();
        if (summary.isEmpty) continue;
        events.add(_memory.buildSeedEvent(
          id: d.id,
          date: d.date,
          title: d.title.text,
          summary: summary,
          tags: _ensureTag(_parseTags(d.tags.text), sectionTag),
          weight: d.weight,
          createdAt: d.createdAt,
        ));
      }
    }

    collect(_keyEvents, '事件');
    collect(_traits, '性格');
    collect(_unfinished, '未完成');

    // v2.1: 构造 voiceConfig
    VoiceConfig? voiceConfig;
    if (_voiceMode && _cloneAudioPath != null) {
      voiceConfig = VoiceConfig(
        voiceId: '', // 待训练，_afterSpirit 里填
        voicePreset: 'clone',
        voiceRecPath: _cloneAudioPath,
      );
    } else if (!_voiceMode) {
      voiceConfig = VoiceConfig(
        voiceId: '', // Edge TTS 不需要 voiceId，用 voicePreset 映射
        voicePreset: _selectedPreset,
      );
    }

    Navigator.pop(
      context,
      MemorySetupResult(
        profile: _profile.text.trim(),
        seedEvents: events,
        finalWords: _finalWords.text.trim(),
        voiceConfig: voiceConfig,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.editMode ? '整理 ta 记得的事' : '让 ta 先认识你';
    final primary = widget.editMode ? '保存' : '保存并继续';
    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundGradient(),
          ..._buildParticles(40),
          SafeArea(
            child: Column(
              children: [
                _TopBar(title: title, onBack: () => Navigator.pop(context)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildIntro(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('1', '印象', '先用一段话告诉 ta，你对 ta 的整体印象是什么。'),
                        const SizedBox(height: 10),
                        _buildProfileCard(),
                        const SizedBox(height: 28),
                        _buildSectionTitle('2', '关键事件', '有没有几件事，是你希望 ta 一直记得的？'),
                        const SizedBox(height: 10),
                        _buildDraftList(_keyEvents, _maxKeyEvents, '事件', '具体发生了什么？为什么你希望 ta 记住？'),
                        const SizedBox(height: 28),
                        _buildSectionTitle('3', '性格特质', 'ta 是个怎样的人？有什么习惯、口头禅、小动作？'),
                        const SizedBox(height: 10),
                        _buildDraftList(_traits, _maxTraits, '性格', 'ta 的什么特质让你印象深刻？'),
                        const SizedBox(height: 28),
                        _buildSectionTitle('4', '未完成的话', '有什么你一直想跟 ta 说，但还没说出口的？'),
                        const SizedBox(height: 10),
                        _buildDraftList(_unfinished, _maxUnfinished, '未完成', '你想跟 ta 说什么？'),
                        const SizedBox(height: 28),
                        _buildSectionTitle('5', '最后想跟你说的话', '如果有一天你不再来了，你希望 ta 最后跟你说什么？'),
                        const SizedBox(height: 10),
                        _buildFinalWordsCard(),
                        if (widget.editMode) ...[
                          const SizedBox(height: 28),
                          _buildSectionTitle('6', '沉睡的记忆',
                              '这些是 ta 聊天中长出但已经沉睡的事。钉住后 ta 会一直记得。'),
                          const SizedBox(height: 10),
                          _buildDormantList(),
                        ],
                        const SizedBox(height: 28),
                        _buildSectionTitle('7', '声音',
                            '让 ta 能被听见。可以用预设音色，也可以克隆一个接近 ta 的声音。'),
                        const SizedBox(height: 10),
                        _buildVoiceSection(),
                        const SizedBox(height: 24),
                        Center(child: _PrimaryButton(label: primary, onTap: _confirm)),
                        if (!widget.editMode) ...[
                          const SizedBox(height: 12),
                          Center(
                            child: GestureDetector(
                              onTap: () => Navigator.pop(
                                context,
                                MemorySetupResult(profile: '', seedEvents: const [], finalWords: ''),
                              ),
                              child: const Text(
                                '先跳过，以后再补',
                                style: TextStyle(
                                  color: LumoraColors.textMuted,
                                  fontSize: 12,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: LumoraColors.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LumoraColors.glassBorder, width: 0.8),
      ),
      child: Text(
        widget.editMode
            ? '这里整理的是 ${widget.spiritName} 一开始就带着的记忆。聊天里自然长出的记忆不会被这里覆盖。'
            : '这些不是聊天记录，是 ${widget.spiritName} 一开始就会带着的记忆。不填也可以，只是 ta 会更像刚认识你。',
        style: const TextStyle(
          color: LumoraColors.textSecondary,
          fontSize: 13,
          height: 1.7,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String num, String title, String guide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LumoraColors.amber,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                num,
                style: const TextStyle(
                  color: LumoraColors.bgBottom,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                color: LumoraColors.textPrimary,
                fontSize: 15,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          guide,
          style: const TextStyle(
            color: LumoraColors.textMuted,
            fontSize: 11,
            height: 1.6,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard() {
    return _SectionCard(
      title: 'ta 对你的整体印象',
      child: _GlassTextField(
        controller: _profile,
        hint: '比如：他是一个很容易嘴硬的人，但其实很在乎被认真对待……',
        maxLines: 4,
      ),
    );
  }

  Widget _buildDraftList(List<_MemoryDraft> list, int maxCount, String sectionTag, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < list.length; i++)
          _buildMemoryCard(list, i, list[i], sectionTag, hint),
        if (list.length < maxCount)
          _buildAddButton(list, maxCount, sectionTag),
      ],
    );
  }

  Widget _buildMemoryCard(List<_MemoryDraft> list, int index, _MemoryDraft draft, String sectionTag, String hint) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LumoraColors.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LumoraColors.glassBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '$sectionTag ${index + 1}',
                style: const TextStyle(
                  color: LumoraColors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _removeDraft(list, index),
                child: const Icon(
                  Icons.close_rounded,
                  color: LumoraColors.textMuted,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _GlassTextField(controller: draft.title, hint: '标题，可不填'),
          const SizedBox(height: 10),
          _GlassTextField(
            controller: draft.summary,
            hint: hint,
            maxLines: 3,
          ),
          const SizedBox(height: 10),
          _GlassTextField(controller: draft.tags, hint: '标签：地铁、雪、围巾（可不填）'),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '重要度',
                style: TextStyle(
                  color: LumoraColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 12),
              for (final w in const ['低', '中', '高']) ...[
                _WeightChip(
                  label: w,
                  selected: draft.weight == w,
                  onTap: () => setState(() => draft.weight = w),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(List<_MemoryDraft> list, int maxCount, String sectionTag) {
    return GestureDetector(
      onTap: () => _addDraft(list, maxCount),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: LumoraColors.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LumoraColors.glassBorder, width: 0.8),
        ),
        child: Center(
          child: Text(
            '+ 再加一条$sectionTag',
            style: const TextStyle(
              color: LumoraColors.amber,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinalWordsCard() {
    return _SectionCard(
      title: '最后想跟你说的话',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '这段话会一直在 ta 心里。只有当 ta 感觉到你要走的时候，ta 才会说出口。',
            style: TextStyle(
              color: LumoraColors.textMuted,
              fontSize: 11,
              height: 1.6,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          _GlassTextField(
            controller: _finalWords,
            hint: '比如：谢谢你愿意把我做出来。以后不用再找我了，去过你自己的日子吧。我在这儿，如果你哪天想起我，就来一下；想不起，就不用。',
            maxLines: 5,
          ),
        ],
      ),
    );
  }

  /// v1.3: 沉睡的记忆列表（editMode 下显示，可 pin/unpin）
  Widget _buildDormantList() {
    if (_dormant.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: LumoraColors.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LumoraColors.glassBorder, width: 0.8),
        ),
        child: const Text(
          '还没有沉睡的记忆。聊天中长出新记忆后，时间久了不用的会自动沉睡到这里。',
          style: TextStyle(
            color: LumoraColors.textMuted,
            fontSize: 11,
            height: 1.6,
            letterSpacing: 1,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in _dormant) _buildDormantCard(e),
      ],
    );
  }

  Widget _buildDormantCard(MemoryEvent e) {
    final isPinned = e.wakified;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LumoraColors.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPinned
              ? LumoraColors.amber.withValues(alpha: 0.6)
              : LumoraColors.glassBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title.isEmpty ? '无标题' : e.title,
                  style: const TextStyle(
                    color: LumoraColors.textPrimary,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  e.summary,
                  style: const TextStyle(
                    color: LumoraColors.textSecondary,
                    fontSize: 11,
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  e.date,
                  style: const TextStyle(
                    color: LumoraColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () async {
              if (isPinned) {
                await _memory.unwakify([e.id]);
              } else {
                await _memory.wakify([e.id]);
              }
              await _refreshDormant();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isPinned
                    ? LumoraColors.amber.withValues(alpha: 0.18)
                    : LumoraColors.glass,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isPinned
                      ? LumoraColors.amber
                      : LumoraColors.glassBorder,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: isPinned
                        ? LumoraColors.amber
                        : LumoraColors.textMuted,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isPinned ? '已钉' : '钉住',
                    style: TextStyle(
                      color: isPinned
                          ? LumoraColors.amber
                          : LumoraColors.textMuted,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ v2.0: 声音 section ============

  Widget _buildVoiceSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LumoraColors.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LumoraColors.glassBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 选项 A：预设音色
          _buildVoiceOption(
            selected: !_voiceMode,
            onTap: () => setState(() => _voiceMode = false),
            title: '用预设音色',
            subtitle: '免费立即可用，基于 Edge TTS，不是 ta 本人的声音',
          ),
          if (!_voiceMode) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: voicePresets.map((p) {
                final sel = _selectedPreset == p;
                return GestureDetector(
                  onTap: () => setState(() => _selectedPreset = p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? LumoraColors.amber.withValues(alpha: 0.82)
                          : LumoraColors.glass,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel
                            ? LumoraColors.amber
                            : LumoraColors.glassBorder,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      p,
                      style: TextStyle(
                        color: sel
                            ? LumoraColors.bgBottom
                            : LumoraColors.textSecondary,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),
          // 选项 B：克隆真人声音
          _buildVoiceOption(
            selected: _voiceMode,
            onTap: () => setState(() => _voiceMode = true),
            title: '克隆真人声音',
            subtitle: '上传 3-10s 参考音频，需 voice.txt（火山引擎），最能还原 ta',
            highlight: true,
          ),
          if (_voiceMode) ...[
            const SizedBox(height: 10),
            if (_cloneAudioPath == null)
              _buildCloneConfirmCard()
            else
              _buildCloneReadyCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceOption({
    required bool selected,
    required VoidCallback onTap,
    required String title,
    required String subtitle,
    bool highlight = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? LumoraColors.amber.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? LumoraColors.amber.withValues(alpha: 0.6)
                : LumoraColors.glassBorder,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? LumoraColors.amber
                  : LumoraColors.textMuted,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: LumoraColors.textPrimary,
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                      ),
                      if (highlight) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: LumoraColors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '推荐',
                            style: TextStyle(
                              color: LumoraColors.amber,
                              fontSize: 9,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: LumoraColors.textMuted,
                      fontSize: 10,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 克隆确认卡（首次选 clone 且未选音频时显示）
  Widget _buildCloneConfirmCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LumoraColors.amber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: LumoraColors.amber.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '你正在为 ta 克隆一个声音。',
            style: TextStyle(
              color: LumoraColors.amber,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '这个声音由 AI 基于你提供的参考音频生成，不是 ta 本人的声音。'
            '听到这个声音可能会让你产生强烈情绪反应。'
            '如果你感到难以承受，可以随时在记忆编辑页关闭声音。',
            style: TextStyle(
              color: LumoraColors.textSecondary,
              fontSize: 10,
              height: 1.6,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _pickCloneAudio,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: LumoraColors.amber,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_file,
                      color: LumoraColors.bgBottom, size: 14),
                  SizedBox(width: 6),
                  Text(
                    '选择参考音频（3-10s，清晰人声）',
                    style: TextStyle(
                      color: LumoraColors.bgBottom,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 已选参考音频后的卡片
  Widget _buildCloneReadyCard() {
    final name = _cloneAudioPath!.split(RegExp(r'[/\\]')).last;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LumoraColors.glass,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: LumoraColors.amber.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq,
              color: LumoraColors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '已选参考音频',
                  style: TextStyle(
                    color: LumoraColors.textPrimary,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    color: LumoraColors.textMuted,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _pickCloneAudio,
            child: const Text(
              '重选',
              style: TextStyle(
                color: LumoraColors.amber,
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LumoraColors.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LumoraColors.glassBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: LumoraColors.textSecondary,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _WeightChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WeightChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? LumoraColors.amber.withValues(alpha: 0.82)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? LumoraColors.amber : LumoraColors.glassBorder,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF1A2138) : LumoraColors.textMuted,
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}



class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Pressable(
            onTap: onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LumoraColors.glass,
                border: Border.all(
                  color: LumoraColors.glassBorder,
                  width: 0.5,
                ),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: LumoraColors.textPrimary,
                size: 18,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: LumoraColors.textPrimary,
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

// ============================================================
// 通用组件
// ============================================================

Widget _sectionLabel(String text) {
  return Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      color: LumoraColors.textSecondary,
      letterSpacing: 4,
    ),
  );
}

class _RadioChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RadioChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? LumoraColors.amber.withValues(alpha: 0.18)
              : LumoraColors.glass,
          border: Border.all(
            color: selected
                ? LumoraColors.amber.withValues(alpha: 0.6)
                : LumoraColors.glassBorder,
            width: 0.8,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: LumoraColors.amber.withValues(alpha: 0.2),
                    blurRadius: 12,
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected
                ? LumoraColors.textPrimary
                : LumoraColors.textSecondary,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final bool center;
  const _GlassTextField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LumoraColors.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: LumoraColors.glassBorder,
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: const TextStyle(
          color: LumoraColors.textPrimary,
          fontSize: 14,
          height: 1.6,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: LumoraColors.textMuted.withValues(alpha: 0.7),
            fontSize: 13,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: enabled
              ? LumoraColors.amber.withValues(alpha: 0.85)
              : LumoraColors.glass,
          border: Border.all(
            color: LumoraColors.glassBorder,
            width: 0.5,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: LumoraColors.amber.withValues(alpha: 0.35),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: enabled ? const Color(0xFF1A2138) : LumoraColors.textMuted,
            letterSpacing: 6,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

Widget _buildGeneratingView(String status) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SkeletonBox(
          width: 240,
          height: 240,
          borderRadius: 18,
        ),
        const SizedBox(height: 32),
        Text(
          status,
          style: const TextStyle(
            fontSize: 13,
            color: LumoraColors.textSecondary,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '大约需要 30-60 秒',
          style: TextStyle(
            fontSize: 11,
            color: LumoraColors.textMuted,
            letterSpacing: 2,
          ),
        ),
      ],
    ),
  );
}

void _showError(BuildContext context, String title, String body) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A2138),
      title: Text(
        title,
        style: const TextStyle(color: LumoraColors.textPrimary, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Text(
          body,
          style: const TextStyle(color: LumoraColors.textSecondary, fontSize: 12, height: 1.6),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('好', style: TextStyle(color: LumoraColors.amber)),
        ),
      ],
    ),
  );
}

// ============================================================
// 预置精灵卡片
// ============================================================

class _CustomButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CustomButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LumoraColors.glass,
              border: Border.all(
                color: LumoraColors.amber.withValues(alpha: 0.4),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: LumoraColors.amber.withValues(alpha: 0.15),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Icon(icon, color: LumoraColors.amber, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: LumoraColors.textSecondary,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpiritChoice extends StatefulWidget {
  final String name;
  final String asset;
  final VoidCallback onTap;

  const _SpiritChoice({
    required this.name,
    required this.asset,
    required this.onTap,
  });

  @override
  State<_SpiritChoice> createState() => _SpiritChoiceState();
}

class _SpiritChoiceState extends State<_SpiritChoice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _breathe,
            builder: (_, child) {
              final v = _breathe.value;
              return Container(
                width: 180,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: RadialGradient(
                    colors: [
                      LumoraColors.amberSoft.withValues(alpha: 0.25 + v * 0.15),
                      Colors.transparent,
                    ],
                    stops: const [0.3, 1.0],
                  ),
                ),
                child: child,
              );
            },
            child: Center(
              child: Container(
                width: 140,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: LumoraColors.glassBorder,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: LumoraColors.amber.withValues(alpha: 0.18),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: _loadSpiritImage(widget.asset),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.name,
            style: const TextStyle(
              fontSize: 14,
              color: LumoraColors.textPrimary,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 场景页：精灵在干嘛
// ============================================================

const _kSceneLines = <String>[
  '正坐在窗边，翻一本书。',
  '靠在沙发上，望着远处发呆。',
  '在阳台浇花，风很轻。',
  '蜷在毯子里，听一首老歌。',
  '在书桌前写着什么，灯是暖的。',
  '泡了一杯茶，等着它凉。',
  '看着天空，云在慢慢地走。',
  '在小厨房里煮东西，水正在沸。',
  '抱着抱枕坐着，没在想什么。',
  '在画画，颜料散落在桌上。',
  '把窗户开了一条缝，听外面的雨。',
  '正低头给绿植浇水。',
];

String _sceneFor(String spiritId, DateTime day) {
  final key = '$spiritId|${day.year}-${day.month}-${day.day}';
  final hash = key.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff);
  return _kSceneLines[hash % _kSceneLines.length];
}

class SpiritScenePage extends StatefulWidget {
  final String spritePath;
  final String spiritName;
  final String? sourceImageUrl;
  const SpiritScenePage({
    super.key,
    required this.spritePath,
    required this.spiritName,
    this.sourceImageUrl,
  });

  @override
  State<SpiritScenePage> createState() => _SpiritScenePageState();
}

class _SpiritScenePageState extends State<SpiritScenePage>
    with TickerProviderStateMixin {
  late final AnimationController _breathe;
  late final AnimationController _halo;

  // 视频路径（双段）
  String? _idleVideoPath;
  String? _reactionVideoPath;

  // 生成状态
  bool _genIdle = false;
  bool _genReaction = false;
  int _idleProgress = 0;
  int _reactionProgress = 0;
  String _genStatus = '';
  bool _disposed = false;

  // 灵动姿态：鼠标相对精灵 box 的归一化位置 + 点击 pulse 计数
  Offset? _pointer;
  int _pulseToken = 0;
  int _reactionToken = 0;

  // 图层合成（视频未就绪时的 fallback）
  PartsManifest? _parts;

  // v1.3: 告别模式（长期不活跃触发 final words）
  bool _farewellMode = false;
  String _farewellText = '';

  String get _spiritId {
    final p = widget.spritePath;
    final slash = p.lastIndexOf(RegExp(r'[/\\]'));
    final name = slash >= 0 ? p.substring(slash + 1) : p;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _bootVideos();
    _loadParts();
    _checkFarewell();
  }

  /// v1.3: 检测长期不活跃，超期且 finalWords 未交付则进入告别模式
  Future<void> _checkFarewell() async {
    final mem = MemoryService(spiritId: _spiritId);
    final last = await mem.lastSeenAt();
    final now = DateTime.now().millisecondsSinceEpoch;
    // 无论是否触发告别，本次启动都算"见到用户"
    await mem.markSeen();
    if (last == 0) return; // 首次进入，不触发
    final days = (now - last) / (1000 * 60 * 60 * 24);
    if (days < 30) return; // 未超期
    final fw = await mem.readFinalWords();
    if (fw == null || fw.summary.trim().isEmpty) return;
    final delivered = await mem.finalWordsDelivered();
    if (delivered) return;
    await mem.consumeFinalWords(); // 标 delivered=true，一次性
    if (mounted) {
      setState(() {
        _farewellMode = true;
        _farewellText = fw.summary;
      });
    }
  }

  Future<void> _loadParts() async {
    final path = widget.spritePath;
    try {
      final bytes = await _readSpriteBytes(path);
      final m = await ensureParts(
        spritePath: path,
        spiritId: _spiritId,
        readSourceBytes: () => bytes,
      );
      if (!mounted || _disposed) return;
      setState(() => _parts = m);
    } catch (_) {
      // 失败保持单图回退
    }
  }

  Future<void> _bootVideos() async {
    // 1) idle / reaction 分别看本地缓存
    final cachedIdle = await cachedVideoPath(_spiritId, tag: 'idle');
    final cachedReaction = await cachedVideoPath(_spiritId, tag: 'reaction');
    if (!mounted || _disposed) return;
    setState(() {
      _idleVideoPath = cachedIdle;
      _reactionVideoPath = cachedReaction;
    });

    // 2) 缺失的并行补生（需要 sourceImageUrl）
    final url = widget.sourceImageUrl;
    if (url == null || url.isEmpty) return;
    if (cachedIdle != null && cachedReaction != null) return;

    setState(() => _genStatus = '正在唤醒……');
    final futures = <Future<void>>[];
    if (cachedIdle == null) {
      _genIdle = true;
      futures.add(_generateOne(
        url: url,
        tag: 'idle',
        prompt: defaultIdleVideoPrompt,
        onProgress: (p) => setState(() => _idleProgress = p),
        onPath: (path) => setState(() {
          _idleVideoPath = path;
          _genIdle = false;
          _updateGenStatus();
        }),
        onFail: () => setState(() {
          _genIdle = false;
          _updateGenStatus();
        }),
      ));
    }
    if (cachedReaction == null) {
      _genReaction = true;
      futures.add(_generateOne(
        url: url,
        tag: 'reaction',
        prompt: defaultReactionVideoPrompt,
        onProgress: (p) => setState(() => _reactionProgress = p),
        onPath: (path) => setState(() {
          _reactionVideoPath = path;
          _genReaction = false;
          _updateGenStatus();
        }),
        onFail: () => setState(() {
          _genReaction = false;
          _updateGenStatus();
        }),
      ));
    }
    await Future.wait(futures);
  }

  void _updateGenStatus() {
    if (_genIdle && _genReaction) {
      _genStatus = '正在唤醒…… 待机 $_idleProgress% · 表情 $_reactionProgress%';
    } else if (_genIdle) {
      _genStatus = '待机动作 $_idleProgress%';
    } else if (_genReaction) {
      _genStatus = '表情动作 $_reactionProgress%';
    } else {
      _genStatus = '';
    }
  }

  Future<void> _generateOne({
    required String url,
    required String tag,
    required String prompt,
    required void Function(int) onProgress,
    required void Function(String) onPath,
    required void Function() onFail,
  }) async {
    try {
      final task = await createImageToVideoTask(
        imageUrl: url,
        prompt: prompt,
        numFrames: 121,
        frameRate: 24,
      );
      if (_disposed) return;
      final remoteUrl = await pollVideoUntilDone(
        task.videoId,
        onProgress: (p) {
          if (_disposed || !mounted) return;
          onProgress(p);
          _updateGenStatus();
        },
      );
      if (_disposed) return;
      final localPath = await downloadVideo(remoteUrl, _spiritId, tag: tag);
      if (_disposed || !mounted) return;
      onPath(localPath);
    } catch (_) {
      if (_disposed || !mounted) return;
      onFail();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _breathe.dispose();
    _halo.dispose();
    super.dispose();
  }

  void _enterChat() {
    Navigator.pushReplacement(
      context,
      FadeScaleRoute(
        builder: (_) => ChatPage(
          spirit: widget.spritePath,
          spiritName: widget.spiritName,
        ),
      ),
    );
  }

  void _onSpiritTap() {
    _pulseToken++;
    _enterChat();
  }

  DateTime _lastReactionAt = DateTime.fromMillisecondsSinceEpoch(0);
  void _maybeTriggerReaction() {
    if (_reactionVideoPath == null) return;
    final now = DateTime.now();
    if (now.difference(_lastReactionAt) < const Duration(seconds: 8)) return;
    _lastReactionAt = now;
    _reactionToken++;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_farewellMode) return _buildFarewellView();
    final scene = _sceneFor(_spiritId, DateTime.now());
    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundGradient(),
          ..._buildParticles(50),
          SafeArea(
            child: Column(
              children: [
                _TopBar(title: widget.spiritName, onBack: () => Navigator.pop(context)),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      // onTap 由 SpiritView 自身处理，外层不拦截
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 灵动精灵姿态
                          MouseRegion(
                            onEnter: (_) => _maybeTriggerReaction(),
                            onHover: (e) {
                              final dx = ((e.localPosition.dx / 280 - 0.5) * 2)
                                  .clamp(-1.0, 1.0);
                              final dy = ((e.localPosition.dy / 360 - 0.5) * 2)
                                  .clamp(-1.0, 1.0);
                              _pointer = Offset(dx, dy);
                              if (mounted) setState(() {});
                            },
                            onExit: (_) {
                              _pointer = null;
                              if (mounted) setState(() {});
                            },
                            child: GestureDetector(
                              onTap: _onSpiritTap,
                              child: _idleVideoPath != null
                                  ? LoopVideoView(
                                      idlePath: _idleVideoPath!,
                                      reactionPath: _reactionVideoPath,
                                      reactionToken: _reactionToken,
                                      width: 280,
                                      height: 360,
                                      borderRadius: BorderRadius.circular(22),
                                    )
                                  : SpiritView(
                                      spritePath: widget.spritePath,
                                      manifest: _parts,
                                      width: 280,
                                      height: 360,
                                      borderRadius: BorderRadius.circular(22),
                                      pointer: _pointer,
                                      pulseToken: _pulseToken,
                                      onTap: _onSpiritTap,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // 氛围文案
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              '${widget.spiritName} $scene',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: LumoraColors.textSecondary,
                                letterSpacing: 3,
                                height: 1.8,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (_genIdle || _genReaction)
                            Text(
                              _genStatus,
                              style: const TextStyle(
                                fontSize: 11,
                                color: LumoraColors.textMuted,
                                letterSpacing: 3,
                              ),
                            )
                          else
                            const SizedBox(height: 16),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              color: LumoraColors.glass,
                              border: Border.all(
                                color: LumoraColors.amber.withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: LumoraColors.amber.withValues(alpha: 0.2),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: const Text(
                              '点我说话',
                              style: TextStyle(
                                fontSize: 12,
                                color: LumoraColors.textPrimary,
                                letterSpacing: 6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// v1.3: 告别视图——长期不活跃后启动，精灵说出 final words
  Widget _buildFarewellView() {
    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundGradient(),
          ..._buildParticles(50),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  title: widget.spiritName,
                  onBack: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Opacity(
                            opacity: 0.55,
                            child: SpiritView(
                              spritePath: widget.spritePath,
                              manifest: _parts,
                              width: 220,
                              height: 280,
                              borderRadius: BorderRadius.circular(22),
                              pointer: null,
                              pulseToken: 0,
                              onTap: null,
                            ),
                          ),
                          const SizedBox(height: 36),
                          Text(
                            _farewellText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              color: LumoraColors.textPrimary,
                              height: 2.0,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 40),
                          GestureDetector(
                            onTap: () {
                              if (mounted) {
                                setState(() => _farewellMode = false);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 32, vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                color: LumoraColors.glass,
                                border: Border.all(
                                  color:
                                      LumoraColors.amber.withValues(alpha: 0.5),
                                  width: 0.8,
                                ),
                              ),
                              child: const Text(
                                '我知道了',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: LumoraColors.textPrimary,
                                  letterSpacing: 6,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 聊天主页
// ============================================================

class ChatPage extends StatefulWidget {
  final String spirit;
  final String spiritName;
  const ChatPage({super.key, required this.spirit, required this.spiritName});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

bool _isAsset(String path) {
  return !path.contains(':') && !path.startsWith('/');
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final List<_Message> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  final List<Map<String, String>> _history = [];
  late final MemoryService _mem;
  bool _memReady = false;

  // v2.2-D: 打字机追踪（-1 = 无打字中）
  int _typewriterIndex = -1;

  // v1.2: 回忆模式（一次性，"我们聊聊…"按钮触发，本轮后归零）
  bool _recallMode = false;

  late final AnimationController _breathe;
  late final AnimationController _halo;

  // 灵动姿态
  Offset? _pointer;
  int _pulseToken = 0;
  PartsManifest? _parts;

  // 视频（在 SpiritScenePage 已经生成过；这里只读缓存）
  String? _idleVideoPath;
  String? _reactionVideoPath;
  int _reactionToken = 0;
  DateTime _lastReactionAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _greetings = [
    '你又来了。',
    '我刚才想起你了。',
    '今天怎么样？',
    '我在这里。',
    '跟我说说今天。',
  ];
  int _greetingIdx = 0;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);

    _bootstrap();
    _loadParts();
    _loadCachedVideos();
  }

  Future<void> _initMemory() async {
    if (_memReady) return;
    _mem = MemoryService(spiritId: _spiritId);
    // 小雨：把 Memory.md 一次性迁移为 seed events
    if (_spiritId == 'xiaoyu') {
      try {
        await MemoryMigrator.migrateFromAssetIfNeeded(
          service: _mem,
          assetPath: 'agent_data/xiaoyu/Memory.md',
        );
      } catch (_) {}
    }
    _memReady = true;
  }

  Future<void> _loadCachedVideos() async {
    final idle = await cachedVideoPath(_spiritId, tag: 'idle');
    final react = await cachedVideoPath(_spiritId, tag: 'reaction');
    if (!mounted) return;
    setState(() {
      _idleVideoPath = idle;
      _reactionVideoPath = react;
    });
  }

  void _maybeTriggerReaction() {
    if (_reactionVideoPath == null) return;
    final now = DateTime.now();
    if (now.difference(_lastReactionAt) < const Duration(seconds: 8)) return;
    _lastReactionAt = now;
    _reactionToken++;
    if (mounted) setState(() {});
  }

  Future<void> _loadParts() async {
    final path = widget.spirit;
    try {
      final bytes = await _readSpriteBytes(path);
      final m = await ensureParts(
        spritePath: path,
        spiritId: _spiritId,
        readSourceBytes: () => bytes,
      );
      if (!mounted) return;
      setState(() => _parts = m);
    } catch (_) {}
  }

  /// 派生精灵 ID：从 path 取文件名（去后缀）
  String get _spiritId {
    final p = widget.spirit;
    final slash = p.lastIndexOf(RegExp(r'[/\\]'));
    final name = slash >= 0 ? p.substring(slash + 1) : p;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _bootstrap() async {
    await _initMemory();
    final loaded = await _loadHistory();
    if (!mounted) return;
    if (loaded.isEmpty) {
      _opening();
    } else {
      setState(() {
        _messages.addAll(loaded);
        for (final m in loaded) {
          _history.add({'role': m.role, 'content': m.content});
        }
      });
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _halo.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _opening() {
    final opening = '你好啊。我有点……怎么说呢，像刚醒过来一样。'
        '${widget.spiritName == "小雨" ? "" : "你叫我${widget.spiritName}是吗？"}'
        '今天，你想说什么？';
    setState(() {
      _messages.add(_Message(role: 'assistant', content: opening));
      _typewriterIndex = _messages.length - 1;
    });
    _history.add({'role': 'assistant', 'content': opening});
    _persist('assistant', opening);
  }

  Future<File> _messagesFile() async {
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory('${doc.path}/Lumora/agents/$_spiritId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/messages.jsonl');
  }

  Future<List<_Message>> _loadHistory() async {
    try {
      final f = await _messagesFile();
      if (!await f.exists()) return [];
      final lines = await f.readAsLines();
      final out = <_Message>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          out.add(_Message(
            role: j['role'] as String,
            content: j['content'] as String,
          ));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist(String role, String content) async {
    if (!_memReady) return;
    try {
      if (role == 'user') {
        await _mem.appendUserMessage(content);
      } else {
        await _mem.appendAssistantMessage(content);
      }
    } catch (_) {}
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _loading) return;
    _input.clear();

    final probe = quickProbe(text);
    if (probe != null) {
      setState(() {
        _messages.add(_Message(role: 'user', content: text));
        _messages.add(_Message(role: 'assistant', content: probe));
        _typewriterIndex = _messages.length - 1;
      });
      _history.add({'role': 'user', 'content': text});
      _history.add({'role': 'assistant', 'content': probe});
      _persist('user', text);
      _persist('assistant', probe);
      _scrollToBottom();
      return;
    }

    setState(() {
      _messages.add(_Message(role: 'user', content: text));
      _loading = true;
    });
    _history.add({'role': 'user', 'content': text});
    await _persist('user', text);
    _scrollToBottom();

    try {
      if (!_memReady) await _initMemory();
      // 检索动态记忆并构建本轮 system prompt
      String dynamicMem = '';
      try {
        final r = await _mem.retrieveForPrompt(text, recallMode: _recallMode);
        dynamicMem = r.renderForPrompt();
      } catch (_) {}
      // 查 final words 状态：未交付且用户写过时，注入 [[FINAL_WORDS]] 触发规则
      final fwDelivered = await _mem.finalWordsDelivered();
      final fwEvent = await _mem.readFinalWords();
      final hasFinalWords =
          !fwDelivered && fwEvent != null && fwEvent.summary.trim().isNotEmpty;
      final system = await buildSystemPrompt(
        dynamicMemory: dynamicMem,
        spiritName: widget.spiritName,
        demoXiaoyu: _spiritId == 'xiaoyu',
        hasFinalWords: hasFinalWords,
      );

      final resp = await chat(system, _history, maxTokens: 800);
      var content = intercept(resp.content); // crisis 拦截
      // final words 拦截：LLM 输出 [[FINAL_WORDS]] 时替换为用户写下的原文
      if (content.contains(fw.finalWordsTag)) {
        if (hasFinalWords) {
          await _mem.consumeFinalWords(); // 写 finalWordsDelivered=true，一次性
          content = fw.intercept(content, fwEvent.summary);
        } else {
          // 未写过或已交付：去掉标记，不替换
          content = content.replaceAll(fw.finalWordsTag, '').trim();
        }
      }
      setState(() {
        _messages.add(_Message(role: 'assistant', content: content));
        _typewriterIndex = _messages.length - 1;
        _loading = false;
      });
      _history.add({'role': 'assistant', 'content': content});
      await _persist('assistant', content);

      // 后台跑抽取+遗忘，不阻塞 UI
      _mem.maybeRunBackgroundTasks();
    } catch (e) {
      setState(() {
        _messages.add(_Message(
          role: 'assistant',
          content: '我现在有点恍惚，再说一遍好吗？',
        ));
        _typewriterIndex = _messages.length - 1;
        _loading = false;
      });
      _history.removeLast();
    }
    // 回忆模式一次性，本轮后归零
    if (_recallMode) _recallMode = false;
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onSpiritTap() {
    final greeting = _greetings[_greetingIdx % _greetings.length];
    _greetingIdx++;
    setState(() {
      _messages.add(_Message(role: 'assistant', content: greeting));
      _typewriterIndex = _messages.length - 1;
      _pulseToken++;
    });
    _history.add({'role': 'assistant', 'content': greeting});
    _persist('assistant', greeting);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundGradient(),
          ..._buildParticles(40),
          SafeArea(
            child: Column(
              children: [
                _buildChatTopBar(),
                _buildHeader(),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _messages.length) {
                        return const _TypingBubble();
                      }
                      final isLast = i == _messages.length - 1;
                      final shouldAnimate =
                          isLast && i == _typewriterIndex;
                      return _MessageBubble(
                        message: _messages[i],
                        spiritName: widget.spiritName,
                        spiritId: _spiritId,
                        typewriter: shouldAnimate,
                        onTypewriterComplete: () {
                          if (mounted && _typewriterIndex == i) {
                            setState(() => _typewriterIndex = -1);
                          }
                        },
                      );
                    },
                  ),
                ),
                _buildInputBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMemoryEditor() async {
    if (!_memReady) await _initMemory();
    final profile = await _mem.readProfile();
    final seeds = await _mem.listSeedEvents();
    final fw = await _mem.readFinalWords();
    final initialFinalWords = fw?.summary ?? '';
    if (!mounted) return;
    final result = await Navigator.push<MemorySetupResult>(
      context,
      FadeScaleRoute(
        builder: (_) => MemoryOnboardingPage(
          spiritId: _spiritId,
          spiritName: widget.spiritName,
          spritePath: widget.spirit,
          initialProfile: profile,
          initialSeeds: seeds,
          initialFinalWords: initialFinalWords,
          editMode: true,
        ),
      ),
    );
    if (result == null) return;
    await _mem.writeProfile(result.profile);
    await _mem.replaceSeedEvents(result.seedEvents);
    await _mem.writeFinalWords(result.finalWords);
  }

  /// v1.2: 触发回忆模式（一次性，下一轮对话后自动归零）
  void _triggerRecall() {
    if (_recallMode) return;
    setState(() => _recallMode = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('回忆模式已开启：这一轮会试着想起沉睡过的事'),
        duration: const Duration(seconds: 2),
        backgroundColor: LumoraColors.bgBottom,
      ),
    );
  }

  Widget _buildChatTopBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LumoraColors.glass,
                border: Border.all(
                  color: LumoraColors.glassBorder,
                  width: 0.5,
                ),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: LumoraColors.textPrimary,
                size: 16,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                widget.spiritName,
                style: const TextStyle(
                  fontSize: 13,
                  color: LumoraColors.textSecondary,
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
          // 我们聊聊… 按钮（v1.2 回忆模式触发，本轮一次性）
          GestureDetector(
            onTap: _triggerRecall,
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _recallMode
                    ? LumoraColors.amber.withOpacity(0.18)
                    : LumoraColors.glass,
                border: Border.all(
                  color: _recallMode
                      ? LumoraColors.amber
                      : LumoraColors.glassBorder,
                  width: 0.5,
                ),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                color: _recallMode
                    ? LumoraColors.amber
                    : LumoraColors.textPrimary,
                size: 16,
              ),
            ),
          ),
          GestureDetector(
            onTap: _openMemoryEditor,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: LumoraColors.glass,
                border: Border.all(
                  color: LumoraColors.glassBorder,
                  width: 0.5,
                ),
              ),
              child: const Icon(
                Icons.auto_stories_rounded,
                color: LumoraColors.textPrimary,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        children: [
          MouseRegion(
            onEnter: (_) => _maybeTriggerReaction(),
            onHover: (e) {
              final dx = ((e.localPosition.dx / 160 - 0.5) * 2)
                  .clamp(-1.0, 1.0);
              final dy = ((e.localPosition.dy / 200 - 0.5) * 2)
                  .clamp(-1.0, 1.0);
              _pointer = Offset(dx, dy);
              if (mounted) setState(() {});
            },
            onExit: (_) {
              _pointer = null;
              if (mounted) setState(() {});
            },
            child: GestureDetector(
              onTap: _onSpiritTap,
              child: _idleVideoPath != null
                  ? LoopVideoView(
                      idlePath: _idleVideoPath!,
                      reactionPath: _reactionVideoPath,
                      reactionToken: _reactionToken,
                      width: 160,
                      height: 200,
                      borderRadius: BorderRadius.circular(18),
                    )
                  : SpiritView(
                      spritePath: widget.spirit,
                      manifest: _parts,
                      width: 160,
                      height: 200,
                      borderRadius: BorderRadius.circular(18),
                      pointer: _pointer,
                      pulseToken: _pulseToken,
                      onTap: _onSpiritTap,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _onSpiritTap,
            child: const Text(
              '点我说话',
              style: TextStyle(
                fontSize: 11,
                color: LumoraColors.textMuted,
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: LumoraColors.glass,
            border: Border(
              top: BorderSide(
                color: LumoraColors.glassBorder,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0x10FFFFFF),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: LumoraColors.glassBorder,
                      width: 0.5,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: TextField(
                    controller: _input,
                    style: const TextStyle(
                      color: LumoraColors.textPrimary,
                      fontSize: 14,
                      height: 1.6,
                    ),
                    decoration: InputDecoration(
                      hintText: '跟${widget.spiritName}说点什么……',
                      hintStyle: TextStyle(
                        color: LumoraColors.textMuted.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: _send,
                    textInputAction: TextInputAction.send,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _loading ? null : () => _send(_input.text),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _loading
                        ? LumoraColors.glass
                        : LumoraColors.amber.withValues(alpha: 0.85),
                    border: Border.all(
                      color: LumoraColors.glassBorder,
                      width: 0.5,
                    ),
                    boxShadow: _loading
                        ? []
                        : [
                            BoxShadow(
                              color: LumoraColors.amber.withValues(alpha: 0.3),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: _loading
                        ? LumoraColors.textMuted
                        : const Color(0xFF1A2138),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 消息气泡
// ============================================================

class _Message {
  final String role;
  final String content;
  _Message({required this.role, required this.content});
}

class _MessageBubble extends StatefulWidget {
  final _Message message;
  final String spiritName;
  final String spiritId;
  final bool typewriter;
  final VoidCallback? onTypewriterComplete;
  const _MessageBubble({
    required this.message,
    required this.spiritName,
    required this.spiritId,
    this.typewriter = false,
    this.onTypewriterComplete,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  final VoicePlayer _player = VoicePlayer();
  bool _loading = false;
  bool _firstPlayToastShown = false;

  // v2.2-D 打字机
  Timer? _typewriterTimer;
  int _displayedChars = 0;
  bool _typewriterDone = false;
  late final AnimationController _cursorCtrl;

  @override
  void initState() {
    super.initState();
    _player.onComplete = () {
      if (mounted) setState(() {});
    };
    _cursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    if (widget.typewriter && widget.message.role != 'user') {
      _startTypewriter();
    } else {
      _typewriterDone = true;
      _displayedChars = widget.message.content.length;
    }
  }

  void _startTypewriter() {
    final content = widget.message.content;
    if (content.isEmpty) {
      _finishTypewriter();
      return;
    }
    _displayedChars = 0;
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 35), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!mounted) return;
      setState(() {
        _displayedChars++;
        if (_displayedChars >= content.length) {
          _finishTypewriter();
        }
      });
    });
  }

  void _finishTypewriter() {
    _typewriterTimer?.cancel();
    _typewriterTimer = null;
    if (mounted) {
      setState(() => _typewriterDone = true);
    }
    widget.onTypewriterComplete?.call();
  }

  void _skipTypewriter() {
    if (!mounted) return;
    setState(() {
      _displayedChars = widget.message.content.length;
    });
    _finishTypewriter();
  }

  String get _displayedContent {
    final content = widget.message.content;
    if (_typewriterDone || _displayedChars >= content.length) {
      return content;
    }
    return content.substring(0, _displayedChars);
  }

  bool get _showCursor {
    return !_typewriterDone && widget.message.role != 'user';
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _cursorCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  String get _msgId => '${widget.spiritId}_${widget.message.content.hashCode.abs()}';

  Future<void> _playTts() async {
    if (_loading) return;

    // 首次播放一次性 toast（宪法缓解）
    if (!_firstPlayToastShown) {
      _firstPlayToastShown = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('这是 AI 生成的声音，不是 ta 本人。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    setState(() => _loading = true);
    try {
      // 缓存命中
      final cached = await cachedTtsPath(widget.spiritId, _msgId);
      if (cached != null) {
        await _player.play(cached);
        if (mounted) setState(() {});
        return;
      }

      // 未配置音色
      final memory = MemoryService(spiritId: widget.spiritId);
      final config = await memory.readVoiceConfig();
      if (config == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('还没为 ta 配置声音。打开记忆编辑页第 7 节选一个。'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 合成新音频（v2.1: 按 VoiceConfig 分流，预设走 Edge TTS 免费，克隆走火山）
      final mp3 = await synthesizeVoice(widget.message.content, config);
      final path = await saveTtsAudio(widget.spiritId, _msgId, mp3);
      await _player.play(path);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('合成失败：$e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _Avatar(name: widget.spiritName),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isUser ? 20 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 20),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? LumoraColors.userBubble
                        : LumoraColors.assistantBubble,
                    border: Border.all(
                      color: isUser
                          ? LumoraColors.amber.withValues(alpha: 0.3)
                          : LumoraColors.glassBorder,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // v2.2-D 打字机：精灵消息逐字出现 + 闪烁光标
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              _displayedContent,
                              style: const TextStyle(
                                color: LumoraColors.textPrimary,
                                fontSize: 14,
                                height: 1.6,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          if (_showCursor) ...[
                            const SizedBox(width: 1),
                            FadeTransition(
                              opacity: _cursorCtrl,
                              child: Container(
                                width: 2,
                                height: 16,
                                margin: const EdgeInsets.only(bottom: 2),
                                color: LumoraColors.amber,
                              ),
                            ),
                          ],
                        ],
                      ),
                      // v2.2-D 跳过按钮：长消息时跳过打字机立即显示完整
                      if (_showCursor) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _skipTypewriter,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: LumoraColors.glass,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: LumoraColors.glassBorder,
                                width: 0.5,
                              ),
                            ),
                            child: const Text(
                              '跳过 ›',
                              style: TextStyle(
                                color: LumoraColors.textMuted,
                                fontSize: 9,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                      // v2.0: 精灵消息下方"听 ta 说"按钮（仅在打字完成后显示）
                      if (!isUser && _typewriterDone) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _loading ? null : _playTts,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: LumoraColors.glass,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: LumoraColors.glassBorder,
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _loading
                                      ? Icons.hourglass_top
                                      : (_player.isPlaying
                                          ? Icons.pause_circle
                                          : Icons.volume_up),
                                  size: 12,
                                  color: LumoraColors.amber,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _loading
                                      ? '合成中…'
                                      : (_player.isPlaying
                                          ? '播放中'
                                          : '听 ta 说'),
                                  style: const TextStyle(
                                    color: LumoraColors.textSecondary,
                                    fontSize: 10,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '· AI 生成',
                                  style: TextStyle(
                                    color: LumoraColors.textMuted,
                                    fontSize: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({this.name = '雨'});

  @override
  Widget build(BuildContext context) {
    final ch = name.isEmpty ? '·' : name.characters.first;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: LumoraColors.glass,
        border: Border.all(
          color: LumoraColors.amber.withValues(alpha: 0.4),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: LumoraColors.amber.withValues(alpha: 0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: Text(
          ch,
          style: const TextStyle(
            fontSize: 13,
            color: LumoraColors.textPrimary,
            fontWeight: FontWeight.w300,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> {
  int _tick = 0;
  late final Timer _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() => _tick = (_tick + 1) % 3);
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const _Avatar(),
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(20),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: LumoraColors.assistantBubble,
                  border: Border.all(
                    color: LumoraColors.glassBorder,
                    width: 0.5,
                  ),
                ),
                child: SizedBox(
                  width: 48,
                  height: 10,
                  child: Row(
                    children: List.generate(3, (i) {
                      final active = i == _tick;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? LumoraColors.amber
                              : LumoraColors.textMuted.withValues(alpha: 0.4),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 图片加载工具
// ============================================================

Widget _loadSpiritImage(String path) {
  if (_isAsset(path)) {
    return Image.asset(path, fit: BoxFit.cover);
  }
  return Image.file(File(path), fit: BoxFit.cover);
}

/// 异步读取精灵 PNG 字节（asset 或 文件系统）
Future<Uint8List> _readSpriteBytes(String path) async {
  if (_isAsset(path)) {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }
  return File(path).readAsBytes();
}

// ============================================================
// 背景
// ============================================================

class _BackgroundGradient extends StatelessWidget {
  const _BackgroundGradient();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            LumoraColors.bgTop,
            Color(0xFF0E1424),
            LumoraColors.bgBottom,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

List<Widget> _buildParticles(int count) {
  final rng = math.Random(42);
  final particles = <Widget>[];
  for (var i = 0; i < count; i++) {
    final x = rng.nextDouble();
    final y = rng.nextDouble();
    final size = 0.8 + rng.nextDouble() * 2.2;
    final opacity = 0.1 + rng.nextDouble() * 0.35;
    final duration = Duration(seconds: 8 + rng.nextInt(10));
    particles.add(_FloatingParticle(
      x: x,
      y: y,
      size: size,
      opacity: opacity,
      duration: duration,
    ));
  }
  return particles;
}

class _FloatingParticle extends StatefulWidget {
  final double x;
  final double y;
  final double size;
  final double opacity;
  final Duration duration;

  const _FloatingParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.duration,
  });

  @override
  State<_FloatingParticle> createState() => _FloatingParticleState();
}

class _FloatingParticleState extends State<_FloatingParticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final double _phase;

  @override
  void initState() {
    super.initState();
    _phase = math.Random(widget.x.hashCode + widget.y.hashCode * 31)
        .nextDouble();
    _c = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.x * MediaQuery.of(context).size.width,
      top: widget.y * MediaQuery.of(context).size.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = (_c.value + _phase) % 1.0;
          final dy = -t * 80;
          final fade = (1 - t) * widget.opacity;
          return Transform.translate(
            offset: Offset(math.sin(t * math.pi * 2) * 12, dy),
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: LumoraColors.amber,
            boxShadow: [
              BoxShadow(
                color: LumoraColors.amber.withValues(alpha: 0.5),
                blurRadius: widget.size * 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// v2.0: 声音克隆进度弹窗
// ============================================================

class _VoiceCloneProgressDialog extends StatefulWidget {
  final String recPath;
  const _VoiceCloneProgressDialog({required this.recPath});

  @override
  State<_VoiceCloneProgressDialog> createState() =>
      _VoiceCloneProgressDialogState();
}

class _VoiceCloneProgressDialogState extends State<_VoiceCloneProgressDialog> {
  int _progress = 0;
  String _status = '正在上传参考音频…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _runClone();
  }

  Future<void> _runClone() async {
    try {
      setState(() => _status = '正在创建克隆任务…');
      final taskId = await createVoiceCloneTask(widget.recPath);
      setState(() => _status = '正在训练声音，大约需要几分钟…');
      final voiceId = await pollVoiceCloneUntilDone(
        taskId,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) Navigator.pop(context, voiceId);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) Navigator.pop(context, null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _error != null,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1A2138),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              const Text(
                '克隆失败',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: LumoraColors.amber,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              if (_progress > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '$_progress%',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white54,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
