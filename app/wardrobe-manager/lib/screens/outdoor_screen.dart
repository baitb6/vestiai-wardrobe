import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../services/recommendation_engine.dart';
import '../theme/app_theme.dart';

/// 户外模式：按场景（徒步 / 长跑）结合实时天气给出穿搭 + 装备 + 材质建议。
class OutdoorScreen extends StatefulWidget {
  const OutdoorScreen({super.key});

  @override
  State<OutdoorScreen> createState() => _OutdoorScreenState();
}

class _OutdoorScreenState extends State<OutdoorScreen> {
  /// 当前选中的场景（OutdoorScenario.hiking / longRun）
  String _scenario = OutdoorScenario.hiking;

  /// 「换一套」时被排除的衣物 id，让下一次推荐换一批单品
  final Set<String> _excludedIds = {};

  /// 装备勾选状态（仅本地 UI 态，key 为 PackingItem.id）
  final Set<String> _checkedGears = {};

  /// 保存进行中标记：防止「保存为搭配」连点插入重复 Outfit
  bool _saving = false;

  void _selectScenario(String id) {
    if (id == _scenario) return;
    setState(() {
      _scenario = id;
      _excludedIds.clear();
    });
  }

  /// 计算当前方案：默认走 provider.recommendOutdoor；
  /// 「换一套」后带排除集用同一引擎重算。
  OutdoorPlan _computePlan(WardrobeProvider provider) {
    if (_excludedIds.isEmpty) {
      return provider.recommendOutdoor(_scenario)!;
    }
    final pool = provider.clothes
        .where((c) => !_excludedIds.contains(c.id))
        .toList();
    if (pool.isEmpty) {
      return provider.recommendOutdoor(_scenario)!;
    }
    return provider.engine.recommendOutdoor(
      clothes: pool,
      temperature: provider.currentTemperature,
      scenario: _scenario,
      precipProb: provider.weather?.precipProb ?? 0,
      windSpeed: provider.weather?.windSpeed ?? 0,
    );
  }

  /// 换一套：把当前这套排除后再算；剩余衣物凑不齐一套时回退从头轮换。
  void _reshuffle(WardrobeProvider provider, OutdoorPlan plan) {
    final currentIds = plan.outfit.clothingIds;
    final pool = provider.clothes
        .where((c) =>
            !_excludedIds.contains(c.id) && !currentIds.contains(c.id))
        .toList();
    final hasTop = pool.any((c) => c.category == ClothingCategory.tops);
    final hasBottom =
        pool.any((c) => c.category == ClothingCategory.bottoms);
    setState(() {
      if (hasTop && hasBottom) {
        _excludedIds.addAll(currentIds);
      } else {
        _excludedIds.clear();
      }
    });
  }

  Future<void> _saveOutfit(
      WardrobeProvider provider, OutdoorPlan plan) async {
    if (_saving) return;
    setState(() => _saving = true);
    final outfit = Outfit(
      id: 'outfit_${const Uuid().v4()}',
      name: '${OutdoorScenario.names[_scenario] ?? '户外'}穿搭',
      clothingIds: plan.outfit.clothingIds,
      occasion: Occasion.sport,
      description: plan.outfit.reasoning,
      createdAt: DateTime.now(),
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      await provider.addOutfit(outfit);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('「${outfit.name}」已保存到我的搭配')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('户外模式')),
      body: Consumer<WardrobeProvider>(
        builder: (context, provider, _) {
          final hasClothes = provider.clothes.isNotEmpty;
          final plan = hasClothes ? _computePlan(provider) : null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _scenarioSelector(),
              const SizedBox(height: 14),
              _weatherCard(provider),
              const SizedBox(height: 14),
              if (!hasClothes) ...[
                _emptyWardrobeCard(),
                const SizedBox(height: 14),
                _materialCard(),
              ] else ...[
                _outfitCard(plan!),
                const SizedBox(height: 14),
                _gearCard(plan),
                const SizedBox(height: 14),
                _materialCard(),
                const SizedBox(height: 18),
                _actionButtons(provider, plan),
              ],
            ],
          );
        },
      ),
    );
  }

  // ============ 场景选择 ============

  Widget _scenarioSelector() {
    return Row(
      children: [
        _scenarioCard(OutdoorScenario.hiking),
        const SizedBox(width: 12),
        _scenarioCard(OutdoorScenario.longRun),
      ],
    );
  }

  Widget _scenarioCard(String id) {
    final selected = _scenario == id;
    return Expanded(
      child: SoftCard(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        borderColor: selected ? AppColors.primary : AppColors.hairline,
        onTap: () => _selectScenario(id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              OutdoorScenario.icons[id] ?? '🥾',
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              OutdoorScenario.names[id] ?? id,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              OutdoorScenario.descriptions[id] ?? '',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============ 天气条 ============

  Widget _weatherCard(WardrobeProvider provider) {
    final weather = provider.weather;
    if (weather == null) {
      return SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('当前天气'),
            const SizedBox(height: 10),
            Text(
              provider.weatherLoading ? '正在获取天气…' : '暂无天气数据',
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: provider.weatherLoading
                      ? null
                      : () => provider.refreshWeather(),
                  icon: provider.weatherLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                ),
                if (provider.weatherError != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      provider.weatherError!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.bad,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(weather.emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weather.city,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${weather.temperature.round()}°C · '
                      '${weather.conditionText}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TagPill(iconEmoji: '💧', label: '降水 ${weather.precipProb}%'),
              TagPill(
                iconEmoji: '💨',
                label: '风速 ${weather.windSpeed.round()} km/h',
              ),
              TagPill(iconEmoji: '🌡️', label: weather.brief),
            ],
          ),
          if (weather.tips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '⚠️ ${weather.tips.first}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.inkSubtle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============ 穿搭推荐 ============

  Widget _outfitCard(OutdoorPlan plan) {
    final outfit = plan.outfit;
    final hasPieces = outfit.pieces.isNotEmpty;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            '穿搭推荐',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TagPill(label: '${plan.temperature.round()}°C'),
                const SizedBox(width: 6),
                TagPill(
                  label: OutdoorScenario.names[plan.scenario] ?? plan.scenario,
                  background: AppColors.tagSport,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (!hasPieces)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                outfit.reasoning,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.inkMuted,
                ),
              ),
            )
          else ...[
            if (outfit.top != null)
              _pieceRow(ClothingCategory.tops, outfit.top!),
            if (outfit.bottom != null)
              _pieceRow(ClothingCategory.bottoms, outfit.bottom!),
            if (outfit.outer != null)
              _pieceRow(ClothingCategory.outerwear, outfit.outer!),
            if (outfit.shoes != null)
              _pieceRow(ClothingCategory.shoes, outfit.shoes!),
            if (outfit.accessory != null)
              _pieceRow(ClothingCategory.accessories, outfit.accessory!),
            const SizedBox(height: 6),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              '💡 ${outfit.reasoning}',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.inkMuted,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pieceRow(String category, Clothing piece) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.checkroom, size: 18, color: AppColors.inkSubtle),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ClothingCategory.names[category] ?? '单品',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  piece.displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                TagPill(
                  iconEmoji: '🧵',
                  label: MaterialType.name(piece.material),
                  background: AppColors.tagSport,
                  foreground: AppColors.inkMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============ 装备清单 ============

  Widget _gearCard(OutdoorPlan plan) {
    final gears = plan.gears;
    final checked =
        gears.where((g) => _checkedGears.contains(g.id)).length;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            '装备清单',
            trailing: TagPill(label: '已备 $checked / ${gears.length}'),
          ),
          const SizedBox(height: 4),
          ...gears.map(_gearRow),
        ],
      ),
    );
  }

  Widget _gearRow(PackingItem gear) {
    final checked = _checkedGears.contains(gear.id);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          if (checked) {
            _checkedGears.remove(gear.id);
          } else {
            _checkedGears.add(gear.id);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _checkbox(checked),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gear.name,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: checked ? AppColors.inkMuted : AppColors.ink,
                    ),
                  ),
                  if (gear.note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      gear.note!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkSubtle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkbox(bool checked) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked ? AppColors.primary : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: checked ? AppColors.primary : AppColors.hairline,
          width: 1.4,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 15, color: AppColors.ink)
          : null,
    );
  }

  // ============ 材质建议 ============

  Widget _materialCard() {
    final tips = _scenario == OutdoorScenario.hiking
        ? const [
            '三层穿衣法：贴身速干排汗层，避免纯棉贴身',
            '中间层抓绒 / 轻薄羽绒保暖，方便随温差穿脱',
            '外层防风防雨壳（冲锋衣），应对山间风雨',
          ]
        : const [
            '速干轻量优先，减少闷热与负重',
            '大腿内侧、乳头处贴防磨贴，防止长距离磨伤',
            '夜跑务必穿戴反光装备，安全第一',
            '纯棉吸汗后变重易磨身，尽量避免',
          ];
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            '材质建议',
            trailing: TagPill(
              iconEmoji: OutdoorScenario.icons[_scenario],
              label: OutdoorScenario.names[_scenario] ?? '户外',
            ),
          ),
          const SizedBox(height: 12),
          ...tips.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.inkMuted,
                        height: 1.5,
                      ),
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

  // ============ 空衣橱兜底 ============

  Widget _emptyWardrobeCard() {
    return SoftCard(
      child: Column(
        children: [
          const Text('🧺', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          const Text(
            '衣橱还是空的',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '先去衣橱录入衣物，再来获取户外穿搭推荐',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }

  // ============ 底部操作 ============

  Widget _actionButtons(WardrobeProvider provider, OutdoorPlan plan) {
    final hasPieces = plan.outfit.pieces.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                hasPieces ? () => _reshuffle(provider, plan) : null,
            icon: const Icon(Icons.casino_outlined, size: 18),
            label: const Text('换一套'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: hasPieces && !_saving
                ? () => _saveOutfit(provider, plan)
                : null,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('保存为搭配'),
          ),
        ),
      ],
    );
  }
}
