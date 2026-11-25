import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../data/ai_mapping.dart';
import '../data/clothing_naming.dart';
import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../services/direct_ai_client.dart';
import '../services/gateway_profile.dart';
import '../services/image_store.dart';
import '../services/local_white_bg.dart';
import '../services/wardrobe_backend.dart';
import '../services/white_background_service.dart';
import '../theme/app_theme.dart';

/// 添加衣服：两段式 —— 第一段选图并交给 AI 识别，第二段人工确认/修改后入库。
///
/// [initialImageBytes] / [prefill]：后台入库任务失败后走「自定义保存」时，
/// 直接带着原图与识别草稿进第二段（不重新选图）。
class AddClothingSheet extends StatefulWidget {
  const AddClothingSheet({
    super.key,
    this.initialImageBytes,
    this.initialImagePath,
    this.prefill,
  });

  final Uint8List? initialImageBytes;
  final String? initialImagePath;
  final Clothing? prefill;

  @override
  State<AddClothingSheet> createState() => _AddClothingSheetState();
}

class _AddClothingSheetState extends State<AddClothingSheet> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _patternCtrl = TextEditingController();
  final TextEditingController _brandCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _tempMinCtrl = TextEditingController();
  final TextEditingController _tempMaxCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _extraAttrCtrl = TextEditingController();

  /// 0 = 选图阶段；1 = AI 结果确认表单
  int _stage = 0;
  String? _imagePath;
  String? _base64Image;
  Uint8List? _imageBytes;
  bool _recognizing = false;
  bool _aiOffline = false;
  bool _aiFailed = false;
  bool _whiteBgGenerating = false;
  String? _whiteBgPath;
  Uint8List? _whiteBgBytes;
  String? _whiteBgError;
  String? _whiteBgNote;
  String _whiteBgMode = 'local';

  @override
  void initState() {
    super.initState();
    _loadWhiteBgMode();
    final bytes = widget.initialImageBytes;
    if (bytes != null) {
      // 自定义保存：跳过选图段，直接进确认段
      _imageBytes = bytes;
      _imagePath = widget.initialImagePath;
      _base64Image = base64Encode(bytes);
      _stage = 1;
      final prefill = widget.prefill;
      if (prefill != null) {
        _prefillFromResult(prefill);
      } else {
        _resetForm();
        _aiFailed = true;
      }
    }
  }

  Future<void> _loadWhiteBgMode() async {
    try {
      final cfg = await WardrobeBackend(
              context.read<WardrobeProvider>().storage)
          .config();
      if (mounted) setState(() => _whiteBgMode = cfg.whiteBgMode);
    } catch (_) {
      // 服务不可达就按本地处理，不影响添加衣物
    }
  }

  /// 入库进行中标记：防止「确认入库」连点插入重复单品
  bool _saving = false;

  // 确认表单字段
  String _category = ClothingCategory.tops;
  String _subCategory = 't_shirt';
  String? _material;
  int _thickness = 2;
  List<String> _styles = [];
  List<String> _seasons = [];
  List<String> _occasions = [];

  @override
  void dispose() {
    _colorCtrl.dispose();
    _patternCtrl.dispose();
    _brandCtrl.dispose();
    _priceCtrl.dispose();
    _tempMinCtrl.dispose();
    _tempMaxCtrl.dispose();
    _nameCtrl.dispose();
    _extraAttrCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _stage == 0
              ? _buildPickStage()
              : _buildConfirmStage(scrollController),
        );
      },
    );
  }

  // ========== 第一段：选图 ==========

  Widget _buildPickStage() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Consumer<WardrobeProvider>(
        builder: (context, provider, _) {
          final busy = _recognizing || provider.isLoading;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGrabHandle(),
              const SizedBox(height: 18),
              const Text('STEP 1 / 2',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.2,
                      color: AppColors.inkSubtle)),
              const SizedBox(height: 6),
              const Text('先来一张照片',
                  style: TextStyle(
                      fontSize: 26,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: AppColors.ink)),
              const SizedBox(height: 8),
              const Text('AI 会认出品类和颜色，你再确认一下就能入库。',
                  style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
              const SizedBox(height: 16),
              Expanded(
                child: _imageBytes == null
                    ? _buildPickPlaceholder()
                    : _buildRecognizingView(busy),
              ),
              if (!kIsWeb) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('从相册选择'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPickPlaceholder() {
    return GestureDetector(
      onTap: () => _pickImage(
        kIsWeb ? ImageSource.gallery : ImageSource.camera,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline, width: 1.2),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                    color: AppColors.surface, shape: BoxShape.circle),
                child: const Icon(Icons.add_a_photo_outlined,
                    size: 28, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 14),
              const Text(
                '拍照 / 从相册选一张',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink),
              ),
              const SizedBox(height: 6),
              const Text(
                '建议浅色背景、单件平铺，识别更准',
                style: TextStyle(fontSize: 11, color: AppColors.inkSubtle),
              ),
              if (kIsWeb)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Web 端将从相册选择',
                    style: TextStyle(
                      color: AppColors.inkSubtle,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecognizingView(bool busy) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            _imageBytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
        if (busy)
          Positioned.fill(
            child: Container(
              color: AppColors.canvas.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 12),
                    Text('AI 正在识别…', style: TextStyle(color: AppColors.ink)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGrabHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.hairline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ========== 第二段：AI 结果确认表单 ==========

  Widget _buildConfirmStage(ScrollController scrollController) {
    final String title;
    final String subtitle;
    if (_aiFailed) {
      title = 'AI 识别失败，请手动填写';
      subtitle = '识别服务暂时不可用，字段已留空，补充信息后入库';
    } else if (_aiOffline) {
      title = '离线默认值，请人工核对';
      subtitle = '未连上 AI 识别服务，以下为默认预填值，请逐项核对修改';
    } else {
      title = 'AI 识别结果，请确认';
      subtitle = '以下字段均已预填，可直接修改后入库';
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _buildGrabHandle(),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (_imageBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              _imageBytes!,
              height: 170,
              width: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        if (_whiteBgBytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(_whiteBgBytes!, height: 170, width: double.infinity, fit: BoxFit.contain),
            ),
          ),
        // Web 端没有本地图片仓库，生成出来也存不下，直接不显示入口
        if (ImageStore.instance.available && _whiteBgMode != 'off') ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _whiteBgGenerating ? null : _generateWhiteBackground,
              icon: _whiteBgGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_fix_high, size: 17),
              label: Text(_whiteBgGenerating
                  ? '正在生成白底图…'
                  : _whiteBgMode == 'server'
                      ? '生成白底商品图（服务器加速）'
                      : '在手机本地生成白底图'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              _whiteBgMode == 'server'
                  ? '这张照片会经衣橱管家服务转发给 AI 模型，服务器不保存图片。'
                  : '在本机处理，照片不会上传；适合浅色背景的照片。',
              style: TextStyle(fontSize: 10.5, color: AppColors.inkSubtle),
            ),
          ),
          if (_whiteBgError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_whiteBgError!,
                  style:
                      const TextStyle(color: Colors.deepOrange, fontSize: 12)),
            ),
          if (_whiteBgNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_whiteBgNote!,
                  style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
            ),
        ],
        TextButton.icon(
          onPressed: _restartPick,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重新选图'),
        ),
        _buildCategoryField(),
        _buildSubCategoryField(),
        _buildLabeledTextField(
          label: '名称（选填）',
          controller: _nameCtrl,
          hintText: '留空自动生成，如「白色T恤」',
        ),
        _buildLabeledTextField(
          label: '颜色',
          controller: _colorCtrl,
          hintText: '可直接输入自定义颜色，如 灰豆绿',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final c in ColorPresets.quick)
                GestureDetector(
                  onTap: () => setState(() => _colorCtrl.text = c),
                  child: Chip(
                    label: Text(c, style: const TextStyle(fontSize: 11)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
            ],
          ),
        ),
        _buildLabeledTextField(
          label: '其他属性（选填）',
          controller: _extraAttrCtrl,
          hintText: '如 版型:宽松，购买渠道:实体店',
        ),
        _buildLabeledTextField(
          label: '图案',
          controller: _patternCtrl,
          hintText: '如 纯色 / 条纹 / 格子（选填）',
        ),
        _buildMaterialField(),
        _buildThicknessField(),
        _buildTempFields(),
        _buildChipGroupField(
          label: '风格',
          options: StyleTag.names,
          selected: _styles,
        ),
        _buildChipGroupField(
          label: '季节',
          options: Season.names,
          selected: _seasons,
        ),
        _buildChipGroupField(
          label: '场合',
          options: Occasion.names,
          selected: _occasions,
        ),
        _buildLabeledTextField(
          label: '品牌',
          controller: _brandCtrl,
          hintText: '选填，如 Uniqlo',
        ),
        _buildLabeledTextField(
          label: '购入价',
          controller: _priceCtrl,
          hintText: '选填，填了就能算「单次穿着成本」',
          keyboardType: TextInputType.number,
        ),
        _buildConfirmButton(),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.inkMuted,
        ),
      ),
    );
  }

  Widget _buildCategoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('类别'),
        DropdownButtonFormField<String>(
          value: _category,
          items: ClothingCategory.names.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text('${ClothingCategory.icons[e.key]} ${e.value}'),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _category = value;
              _subCategory =
                  ClothingSubCategory.subCategories[value]!.first;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSubCategoryField() {
    final subs = ClothingSubCategory.subCategories[_category] ?? const [];
    final value = subs.contains(_subCategory) ? _subCategory : subs.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('子类'),
        DropdownButtonFormField<String>(
          value: value,
          items: subs
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(ClothingSubCategory.names[s] ?? s),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _subCategory = value);
          },
        ),
      ],
    );
  }

  Widget _buildLabeledTextField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(hintText: hintText),
        ),
      ],
    );
  }

  Widget _buildMaterialField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('材质'),
        DropdownButtonFormField<String?>(
          value: _material,
          decoration: const InputDecoration(hintText: '未填'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('未填')),
            ...MaterialType.all.map(
              (m) => DropdownMenuItem<String?>(
                value: m,
                child: Text(MaterialType.names[m] ?? m),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _material = value),
        ),
      ],
    );
  }

  Widget _buildThicknessField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('厚度'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final level in ThicknessLevel.names.keys)
              ChoiceChip(
                label: Text(ThicknessLevel.name(level)),
                selected: _thickness == level,
                onSelected: (_) => setState(() => _thickness = level),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTempFields() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildLabeledTextField(
            label: '适穿温度下限',
            controller: _tempMinCtrl,
            hintText: '如 10',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildLabeledTextField(
            label: '适穿温度上限',
            controller: _tempMaxCtrl,
            hintText: '如 25',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChipGroupField({
    required String label,
    required Map<String, String> options,
    required List<String> selected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in options.entries)
              FilterChip(
                label: Text(entry.value),
                selected: selected.contains(entry.key),
                onSelected: (_) => _toggleInList(selected, entry.key),
              ),
          ],
        ),
      ],
    );
  }

  void _toggleInList(List<String> list, String value) {
    setState(() {
      if (list.contains(value)) {
        list.remove(value);
      } else {
        list.add(value);
      }
    });
  }

  Widget _buildConfirmButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _saving ? null : _confirm,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.check),
          label: const Text('确认入库'),
        ),
      ),
    );
  }

  // ========== 选图与识别 ==========

  Future<void> _pickImage(ImageSource source) async {
    if (_recognizing) return;
    final XFile? image = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 70,
    );
    if (image == null || !mounted) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;
    final base64 = base64Encode(bytes);

    setState(() {
      _imagePath = image.path;
      _imageBytes = bytes;
      _base64Image = base64;
      _recognizing = true;
      _aiOffline = false;
      _aiFailed = false;
    });

    // 自动走 AI 识别（Web / 原生统一用 base64 通道）
    Clothing? result;
    try {
      result = await context
          .read<WardrobeProvider>()
          .recognizeClothingFromBase64(base64);
    } catch (_) {
      result = null;
    }
    if (!mounted) return;

    if (result != null) {
      _prefillFromResult(result);
    } else {
      _resetForm();
      _aiFailed = true;
    }
    setState(() {
      _recognizing = false;
      _stage = 1;
    });
  }

  /// 用 AI 识别结果预填确认表单（无效枚举值回落到合法默认）。
  /// #1：颜色/图案英文归一成中文；名称预填走 toChineseClothingName
  /// （颜色+品类，品牌词剥离进品牌栏），保证列表标题 100% 中文。
  void _prefillFromResult(Clothing result) {
    var category = AiMapping.category(result.category);
    if (!ClothingCategory.names.containsKey(category)) {
      category = ClothingCategory.tops;
    }
    final subs = ClothingSubCategory.subCategories[category]!;
    var subCategory = AiMapping.subCategory(result.subCategory, category);
    if (!subs.contains(subCategory)) {
      subCategory = subs.first;
    }
    _category = category;
    _subCategory = subCategory;
    // #15：AI 自报颜色直存（词典优先、原文保留、首字母大写）
    _colorCtrl.text = normalizeAiColor(result.color);
    _patternCtrl.text = result.pattern == null || result.pattern!.trim().isEmpty
        ? ''
        : (toChinesePattern(result.pattern!.trim()) ?? result.pattern!.trim());
    _brandCtrl.text = result.brand ?? '';
    _material = result.material;
    final t = result.thickness;
    _thickness = t < 0 ? 0 : (t > 4 ? 4 : t);
    _tempMinCtrl.text = result.tempMin?.toString() ?? '';
    _tempMaxCtrl.text = result.tempMax?.toString() ?? '';
    _styles = result.styles
        .where(StyleTag.names.containsKey)
        .toList(growable: true);
    _seasons = result.seasons
        .where(Season.names.containsKey)
        .toList(growable: true);
    _occasions = result.occasions
        .where(Occasion.names.containsKey)
        .toList(growable: true);
    _aiOffline = _isOfflineDefault(result);

    // 名称预填：已有中文名（intake 草稿）优先，否则按「颜色+品类」生成
    final existingName = result.customName?.trim() ?? '';
    if (existingName.isNotEmpty) {
      _nameCtrl.text = existingName;
    } else {
      final rawLabel = [
        result.brand ?? '',
        result.subCategory,
        result.category,
      ].where((s) => s.trim().isNotEmpty).join(' ');
      final parsed =
          parseChineseClothingName(rawLabel, colorHint: _colorCtrl.text);
      if (parsed.name.isNotEmpty && parsed.hasCategory) {
        _nameCtrl.text = parsed.name;
      }
    }
  }

  /// 与 AIService 离线兜底数据完全一致时，按「离线默认值」提示人工核对
  bool _isOfflineDefault(Clothing c) {
    return c.category == ClothingCategory.tops &&
        c.subCategory == 't_shirt' &&
        c.color == '白色' &&
        c.pattern == '纯色' &&
        c.material == MaterialType.cotton &&
        c.thickness == 1 &&
        c.tempMin == 15 &&
        c.tempMax == 28 &&
        c.brand == null;
  }

  /// 把「版型:宽松，购买渠道:实体店」解析成自定义属性表；空则返回 null。
  Map<String, String>? _parseExtraAttributes(String raw) {
    final map = <String, String>{};
    for (final line in raw.split(RegExp(r'[,，;；\n]'))) {
      final text = line.trim();
      if (text.isEmpty) continue;
      final i = text.indexOf(RegExp(r'[:：]'));
      if (i > 0) {
        final k = text.substring(0, i).trim();
        final v = text.substring(i + 1).trim();
        if (k.isNotEmpty && v.isNotEmpty) map[k] = v;
      } else if (!map.containsKey('自定义')) {
        map['自定义'] = text;
      }
    }
    return map.isEmpty ? null : map;
  }

  void _resetForm() {
    _category = ClothingCategory.tops;
    _subCategory =
        ClothingSubCategory.subCategories[ClothingCategory.tops]!.first;
    _material = null;
    _thickness = 2;
    _colorCtrl.clear();
    _patternCtrl.clear();
    _brandCtrl.clear();
    _priceCtrl.clear();
    _tempMinCtrl.clear();
    _tempMaxCtrl.clear();
    _nameCtrl.clear();
    _extraAttrCtrl.clear();
    _styles = [];
    _seasons = [];
    _occasions = [];
  }

  void _restartPick() {
    setState(() {
      _stage = 0;
      _imagePath = null;
      _base64Image = null;
      _imageBytes = null;
      _whiteBgPath = null;
      _whiteBgBytes = null;
      _whiteBgError = null;
      _whiteBgNote = null;
      _recognizing = false;
      _aiOffline = false;
      _aiFailed = false;
      _resetForm();
    });
  }

  Future<void> _generateWhiteBackground() async {
    final source = _imageBytes;
    if (source == null || _whiteBgGenerating) return;
    setState(() {
      _whiteBgGenerating = true;
      _whiteBgError = null;
      _whiteBgNote = null;
    });
    try {
      Uint8List bytes;
      String? note;
      if (_whiteBgMode == 'server') {
        // 同步取 storage，避免跨 await 使用 context
        final storage = context.read<WardrobeProvider>().storage;
        try {
          // v1.9：白底 server 模式直连优先（white_bg 用途）：
          // 有凭证 → 直发厂商图像编辑端点；无凭证/不可用 → 后台代理（现状）。
          // 直连失败不回退代理，避免同一张图传两遍，直接落到本地兜底。
          final ep = await DirectAiClient.resolveEndpoint(
            kind: 'white_bg',
            proxyBaseUrl: WardrobeBackend.proxyBaseUrl,
          );
          if (ep.direct) {
            final directEndpoint = (ep.endpoint ?? '').trim();
            final result = await WhiteBackgroundService().generate(
              source: source,
              profile: GatewayProfile(
                kind: GatewayKind.edit,
                baseUrl: ep.baseUrl,
                model: ep.model ?? '',
                editEndpoint:
                    directEndpoint.isEmpty ? '/images/edits' : directEndpoint,
                supportsImageEdit: true,
              ),
              apiKey: ep.apiKey,
            );
            bytes = result.bytes;
          } else {
            bytes = await WardrobeBackend(storage).whiteBackground(source);
          }
        } catch (e) {
          note = '服务器生成失败，已改用手机本地处理';
          bytes = await const LocalWhiteBackground().build(source);
        }
      } else {
        bytes = await const LocalWhiteBackground().build(source);
      }
      if (img.decodeImage(bytes) == null) {
        throw StateError('生成结果不是有效图片，请换一张照片再试');
      }
      final path = await ImageStore.instance.saveBytes(
        bytes,
        prefix: 'white_bg',
        ext: WhiteBackgroundResult(bytes: bytes, endpoint: '').extension,
      );
      if (path == null) throw StateError('白底图保存失败，请检查存储空间');
      if (!mounted) return;
      setState(() {
        _whiteBgBytes = bytes;
        _whiteBgPath = path;
        _whiteBgNote = note;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(note ?? '白底图已生成，入库时会优先使用它')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _whiteBgError =
            '生成失败：${e.toString().replaceFirst('StateError: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _whiteBgGenerating = false);
    }
  }

  // ========== 入库 ==========

  Future<void> _confirm() async {
    if (_saving) return;
    final color = _colorCtrl.text.trim();
    if (color.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写颜色后再入库')),
      );
      return;
    }
    setState(() => _saving = true);
    final pattern = _patternCtrl.text.trim();
    final brand = _brandCtrl.text.trim();
    final tempMin = int.tryParse(_tempMinCtrl.text.trim());
    final tempMax = int.tryParse(_tempMaxCtrl.text.trim());
    final subs = ClothingSubCategory.subCategories[_category] ?? const [];
    final subCategory = subs.contains(_subCategory) ? _subCategory : subs.first;

    final clothing = Clothing(
      id: 'c_${const Uuid().v4()}',
      imageUrl: _whiteBgPath ?? (_base64Image != null
          ? 'data:image/jpeg;base64,$_base64Image'
          : (_imagePath ?? '')),
      originalImagePath: _imagePath,
      category: _category,
      subCategory: subCategory,
      color: color,
      pattern: pattern.isEmpty ? null : pattern,
      styles: List<String>.of(_styles),
      seasons: List<String>.of(_seasons),
      brand: brand.isEmpty ? null : brand,
      price: double.tryParse(_priceCtrl.text.trim()),
      material: _material,
      thickness: _thickness,
      tempMin: tempMin,
      tempMax: tempMax,
      occasions: List<String>.of(_occasions),
      createdAt: DateTime.now(),
      customName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      extraAttributes: _parseExtraAttributes(_extraAttrCtrl.text),
    );

    try {
      await context.read<WardrobeProvider>().addClothing(clothing);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('入库失败：$e')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已确认入库 +10 积分')),
    );
  }
}

class QuickAddButton extends StatelessWidget {
  const QuickAddButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => const AddClothingSheet(),
        );
      },
      icon: const Icon(Icons.add_a_photo),
      label: const Text('添加衣服'),
    );
  }
}
