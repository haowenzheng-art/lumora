import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'main.dart' show LumoraColors;

/// Lumora 字体系统（v2.2）
///
/// 设计原则：
/// - 情感性文本（产品 logo / 信札式 UI / 告别语 / onboarding 章节标题）→ Noto Serif SC
///   思源宋体的衬线 + 中文韵味，跟"思念具象化"的庄重调性匹配
/// - 功能性文本（按钮 / 时间戳 / 提示 / 西文）→ Inter
///   现代无衬线，对比清晰，不抢情感文本的戏
/// - 技术性数字 / 路径 / ID → JetBrains Mono（可选）
///
/// 全局默认走 Inter（中文用 fallback），关键情感位用 displayStyle / letterStyle 覆盖。
class LumoraTextStyles {
  /// 产品 logo / 章节大标题：思源宋体 + 字重 300 + 宽字距
  /// 用于 Lumora logo、onboarding 章节标题、告别仪式标题
  static TextStyle displayStyle({
    double fontSize = 42,
    FontWeight fontWeight = FontWeight.w300,
    Color color = LumoraColors.textPrimary,
    double letterSpacing = 12,
    double height = 1.2,
  }) {
    return GoogleFonts.notoSerifSc(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// 信札式正文：思源宋体 + 较宽行高 + 宽字距
  /// 用于产品口号、final words、Soul 自述、告别信
  static TextStyle letterStyle({
    double fontSize = 13,
    Color color = LumoraColors.moonBlue,
    double letterSpacing = 4,
    double height = 1.8,
  }) {
    return GoogleFonts.notoSerifSc(
      fontSize: fontSize,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// 正文：Inter + 适中行高
  /// 用于消息气泡、对话内容、说明文字
  static TextStyle bodyStyle({
    double fontSize = 14,
    Color color = LumoraColors.textPrimary,
    double height = 1.6,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      color: color,
      height: height,
    );
  }

  /// 辅助说明：Inter + 字距 + 浅色
  /// 用于小标题、Section 标题、placeholder
  static TextStyle captionStyle({
    double fontSize = 12,
    Color color = LumoraColors.textSecondary,
    double letterSpacing = 2,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// 按钮：Inter + 中等字重 + 宽字距
  /// 用于主按钮、RadioChip 选中态
  static TextStyle buttonStyle({
    double fontSize = 13,
    Color color = const Color(0xFF1A2138),
    FontWeight fontWeight = FontWeight.w500,
    double letterSpacing = 6,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }
}