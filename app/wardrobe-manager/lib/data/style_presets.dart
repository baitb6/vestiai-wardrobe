import 'package:flutter/material.dart';

/// 灵感风格库 —— 参照 Whering / OpenWardrobe 的「风格 mood board」，
/// 每个风格是一张可点击的卡片：点一下即按该风格 + 当前天气生成整套搭配。
class StylePreset {
  final String id;
  final String name;
  final String en;
  final String desc;
  final String prompt;
  final String occasion;
  final String styleKey;
  final String emoji;
  final List<Color> gradient;
  final List<String> tags;

  const StylePreset({
    required this.id,
    required this.name,
    required this.en,
    required this.desc,
    required this.prompt,
    required this.occasion,
    required this.styleKey,
    required this.emoji,
    required this.gradient,
    required this.tags,
  });
}

const kStylePresets = <StylePreset>[
  StylePreset(
    id: 'clean',
    name: '极简通勤',
    en: 'CLEAN FIT',
    desc: '低饱和 + 干净线条，办公室也能很时髦',
    prompt: '帮我搭一套极简通勤装，低饱和配色，干净利落',
    occasion: 'work',
    styleKey: 'minimalist',
    emoji: '◻️',
    gradient: [Color(0xFFE8E2D9), Color(0xFFC9BFB1)],
    tags: ['低饱和', '利落'],
  ),
  StylePreset(
    id: 'y2k',
    name: 'Y2K 甜酷',
    en: 'Y2K POP',
    desc: '亮色、短上衣、厚底鞋，拍照最出片',
    prompt: '搭一套 Y2K 甜酷风，可以有一点亮色和配饰',
    occasion: 'party',
    styleKey: 'streetwear',
    emoji: '💿',
    gradient: [Color(0xFFFFD9E8), Color(0xFFB9A6FF)],
    tags: ['亮色', '出片'],
  ),
  StylePreset(
    id: 'citywalk',
    name: 'City Walk',
    en: 'CITY WALK',
    desc: '舒服但不邋遢，走一天也不累',
    prompt: '搭一套 city walk 的日常装，好走舒服但要有型',
    occasion: 'daily',
    styleKey: 'casual',
    emoji: '🧋',
    gradient: [Color(0xFFDCE9D5), Color(0xFFA8C3A0)],
    tags: ['舒适', '日常'],
  ),
  StylePreset(
    id: 'date',
    name: '约会夜',
    en: 'DATE NIGHT',
    desc: '一点点小心机，不用太用力',
    prompt: '搭一套约会穿搭，温柔一点，不要太夸张',
    occasion: 'dating',
    styleKey: 'dating',
    emoji: '🌙',
    gradient: [Color(0xFFFFE0CC), Color(0xFFFFB4A2)],
    tags: ['温柔', '心机'],
  ),
  StylePreset(
    id: 'sporty',
    name: '运动休闲',
    en: 'SPORTY',
    desc: '速干透气优先，健身房和街头都能穿',
    prompt: '搭一套运动休闲装，透气排汗，看起来也要利落',
    occasion: 'sport',
    styleKey: 'sporty',
    emoji: '🏃',
    gradient: [Color(0xFFD6E9FF), Color(0xFF9CC0F0)],
    tags: ['速干', '活力'],
  ),
  StylePreset(
    id: 'vintage',
    name: '复古学院',
    en: 'VINTAGE',
    desc: '格纹、大地色、针织，秋冬最有味道',
    prompt: '搭一套复古学院风，可以用格纹和大地色',
    occasion: 'daily',
    styleKey: 'vintage',
    emoji: '📻',
    gradient: [Color(0xFFF0DFC4), Color(0xFFC9A47A)],
    tags: ['大地色', '针织'],
  ),
];
