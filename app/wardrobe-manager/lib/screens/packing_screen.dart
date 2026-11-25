import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../theme/app_theme.dart';

String _fmtDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}'
    '.${d.day.toString().padLeft(2, '0')}';

/// 清单分组顺序：衣物类在前，非衣物类在后
const List<String> _kCategoryOrder = [
  ClothingCategory.tops,
  ClothingCategory.bottoms,
  ClothingCategory.dress,
  ClothingCategory.outerwear,
  ClothingCategory.shoes,
  ClothingCategory.accessories,
  'gear',
  'essentials',
  'toiletries',
  'documents',
  'other',
];

const Map<String, String> _kExtraCategoryNames = {
  'gear': '装备',
  'essentials': '必需品',
  'toiletries': '洗漱',
  'documents': '证件',
  'other': '其他',
};

String _categoryName(String c) =>
    ClothingCategory.names[c] ?? _kExtraCategoryNames[c] ?? '其他';

Color _materialBg(String material) {
  final warmth = MaterialType.warmthOf(material);
  if (warmth >= 7) return AppColors.tagWarm;
  if (warmth <= 2) return AppColors.tagCool;
  return AppColors.tagNeutral;
}

Color _materialFg(String material) {
  final warmth = MaterialType.warmthOf(material);
  if (warmth >= 7) return AppColors.warn;
  if (warmth <= 2) return AppColors.accent;
  return AppColors.inkMuted;
}

/// 行李清单：行程列表 + 新建行程表单 + 清单详情
class PackingScreen extends StatefulWidget {
  const PackingScreen({super.key});

  @override
  State<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends State<PackingScreen> {
  Future<void> _openCreateSheet() async {
    final created = await showModalBottomSheet<PackingList>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CreateTripSheet(),
    );
    if (created != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PackingDetailPage(listId: created.id),
        ),
      );
    }
  }

  void _openDetail(PackingList list) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PackingDetailPage(listId: list.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WardrobeProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('行李清单')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openCreateSheet,
            icon: const Icon(Icons.add),
            label: const Text('新建行程'),
          ),
          body: provider.packingLists.isEmpty
              ? _buildEmpty()
              : _buildList(provider),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SoftCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Icon(
                Icons.luggage,
                size: 56,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                '根据行程天数、目的地气候和场合，自动生成打包清单',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.inkMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _openCreateSheet,
                icon: const Icon(Icons.add),
                label: const Text('新建行程'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(WardrobeProvider provider) {
    final upcoming = provider.upcomingPackingLists;
    final past = provider.packingLists.where((p) => p.isPast).toList();
    final ordered = [...upcoming, ...past];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: ordered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final list = ordered[index];
        final card = _buildCard(list);
        return list.isPast
            ? Opacity(opacity: 0.55, child: card)
            : card;
      },
    );
  }

  Widget _buildCard(PackingList list) {
    final climateName = ClimateType.names[list.climate] ?? list.climate;
    return SoftCard(
      onTap: () => _openDetail(list),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  list.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TagPill(
                label: climateName,
                iconEmoji: ClimateType.icons[list.climate],
                background: AppColors.primarySoft,
                foreground: AppColors.primary,
              ),
            ],
          ),
          if (list.destination != null &&
              list.destination!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    list.destination!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${_fmtDate(list.startDate)} - ${_fmtDate(list.endDate)}'
            ' · 共 ${list.days} 天',
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: list.progress,
              minHeight: 6,
              backgroundColor: AppColors.surfaceAlt,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已打包 ${list.packedCount} / ${list.items.length}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

/// 新建行程底部表单
class _CreateTripSheet extends StatefulWidget {
  const _CreateTripSheet();

  @override
  State<_CreateTripSheet> createState() => _CreateTripSheetState();
}

class _CreateTripSheetState extends State<_CreateTripSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  String _climate = ClimateType.mild;
  final Set<String> _occasions = <String>{};
  bool _submitting = false;

  static const List<String> _climateOptions = [
    ClimateType.hot,
    ClimateType.mild,
    ClimateType.cold,
    ClimateType.variable,
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _destCtrl.dispose();
    _tempCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final earliest = DateTime(now.year - 1, now.month, now.day);
    final latest = DateTime(now.year + 3, now.month, now.day);
    var first = earliest;
    if (!isStart && _startDate != null) {
      first = _startDate!;
    }
    var initial = isStart
        ? (_startDate ?? now)
        : (_endDate ?? _startDate?.add(const Duration(days: 1)) ?? now);
    if (initial.isBefore(first)) {
      initial = first;
    }
    if (initial.isAfter(latest)) {
      initial = latest;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: latest,
      helpText: isStart ? '选择开始日期' : '选择结束日期',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        _startCtrl.text = _fmtDate(picked);
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
          _endCtrl.text = _fmtDate(_endDate!);
        }
      } else {
        _endDate = picked;
        _endCtrl.text = _fmtDate(picked);
      }
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final provider = context.read<WardrobeProvider>();
    final dest = _destCtrl.text.trim();
    final tempText = _tempCtrl.text.trim();
    final avgTemp = tempText.isEmpty ? null : double.tryParse(tempText);
    try {
      final list = await provider.generatePackingList(
        name: _nameCtrl.text.trim(),
        destination: dest.isEmpty ? null : dest,
        startDate: _startDate!,
        endDate: _endDate!,
        climate: _climate,
        occasions: _occasions.toList(),
        avgTemp: avgTemp,
      );
      if (!mounted) return;
      Navigator.pop(context, list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '新建行程',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '行程名称',
                  hintText: '如：十一日本行',
                ),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入行程名称' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _destCtrl,
                decoration: const InputDecoration(
                  labelText: '目的地',
                  hintText: '如：东京',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startCtrl,
                      readOnly: true,
                      onTap: () => _pickDate(isStart: true),
                      decoration: const InputDecoration(
                        labelText: '开始日期',
                        suffixIcon: Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      validator: (v) =>
                          _startDate == null ? '请选择开始日期' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _endCtrl,
                      readOnly: true,
                      onTap: () => _pickDate(isStart: false),
                      decoration: const InputDecoration(
                        labelText: '结束日期',
                        suffixIcon: Icon(
                          Icons.event_outlined,
                          size: 18,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      validator: (v) {
                        if (_endDate == null) return '请选择结束日期';
                        if (_startDate != null &&
                            _endDate!.isBefore(_startDate!)) {
                          return '不早于开始日期';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SheetLabel('目的地气候'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _climateOptions)
                    ChoiceChip(
                      label: Text(
                        '${ClimateType.icons[c] ?? ''} ${ClimateType.names[c] ?? c}',
                      ),
                      selected: _climate == c,
                      labelStyle: _climate == c
                          ? const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            )
                          : null,
                      onSelected: (_) => setState(() => _climate = c),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const _SheetLabel('行程场合（可多选）'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in Occasion.names.keys)
                    FilterChip(
                      label: Text(
                        Occasion.names[o] ?? o,
                      ),
                      selected: _occasions.contains(o),
                      labelStyle: _occasions.contains(o)
                          ? const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            )
                          : null,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _occasions.add(o);
                          } else {
                            _occasions.remove(o);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _tempCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '日均温度（°C，选填）',
                  hintText: '如：18',
                ),
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return null;
                  return double.tryParse(text) == null ? '请输入有效数字' : null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('生成清单'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
        letterSpacing: 0.2,
      ),
    );
  }
}

/// 行李清单详情页
class _PackingDetailPage extends StatelessWidget {
  const _PackingDetailPage({required this.listId});

  final String listId;

  void _confirmDelete(
    BuildContext context,
    WardrobeProvider provider,
    PackingList list,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除行程'),
        content: Text('确定删除「${list.name}」的行李清单吗？该操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.bad,
              foregroundColor: AppColors.ink,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
              provider.deletePackingList(list.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WardrobeProvider>(
      builder: (context, provider, _) {
        final index =
            provider.packingLists.indexWhere((p) => p.id == listId);
        if (index == -1) {
          return const Scaffold(body: SizedBox.shrink());
        }
        final list = provider.packingLists[index];
        return Scaffold(
          appBar: AppBar(
            title: Text(list.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _confirmDelete(context, provider, list),
              ),
            ],
          ),
          body: _buildBody(list),
        );
      },
    );
  }

  Widget _buildBody(PackingList list) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _buildInfoCard(list),
        const SizedBox(height: 24),
        for (final category in _kCategoryOrder)
          ..._buildCategorySection(list, category),
      ],
    );
  }

  Widget _buildInfoCard(PackingList list) {
    final climateName = ClimateType.names[list.climate] ?? list.climate;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  list.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TagPill(
                label: climateName,
                iconEmoji: ClimateType.icons[list.climate],
                background: AppColors.primarySoft,
                foreground: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 14,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  list.destination ?? '未设置目的地',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.date_range, size: 14, color: AppColors.inkMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${_fmtDate(list.startDate)} - ${_fmtDate(list.endDate)}'
                  ' · 共 ${list.days} 天',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          if (list.avgTemp != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.device_thermostat_outlined,
                  size: 14,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  '日均 ${list.avgTemp!.round()}°C',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ],
          if (list.occasions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in list.occasions)
                  TagPill(
                    label: Occasion.names[o] ?? o,
                    icon: Icons.local_activity_outlined,
                    background: AppColors.accentSoft,
                    foreground: AppColors.accent,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: list.progress,
              minHeight: 6,
              backgroundColor: AppColors.surfaceAlt,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已打包 ${list.packedCount} / ${list.items.length}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSubtle,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCategorySection(
    PackingList list,
    String category,
  ) {
    final items =
        list.items.where((item) => item.category == category).toList();
    if (items.isEmpty) return const <Widget>[];
    final packed = items.where((item) => item.packed).length;
    return <Widget>[
      SectionTitle(
        _categoryName(category),
        trailing: Text(
          '$packed/${items.length}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSubtle,
          ),
        ),
      ),
      const SizedBox(height: 12),
      SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(indent: 8, endIndent: 8),
              _ItemRow(list: list, item: items[i]),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
    ];
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.list, required this.item});

  final PackingList list;
  final PackingItem item;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<WardrobeProvider>();
    Clothing? clothing;
    if (item.clothingId != null) {
      final matches = provider.clothes
          .where((c) => c.id == item.clothingId)
          .toList();
      if (matches.isNotEmpty) clothing = matches.first;
    }
    final material = clothing?.material;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Checkbox(
            value: item.packed,
            onChanged: (_) => provider.togglePacked(list.id, item.id),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: item.packed
                              ? AppColors.inkSubtle
                              : AppColors.ink,
                        ),
                      ),
                    ),
                    Text(
                      'x${item.quantity}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkSubtle,
                      ),
                    ),
                  ],
                ),
                if (item.note != null && item.note!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.note!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkSubtle,
                    ),
                  ),
                ],
                if (material != null) ...[
                  const SizedBox(height: 6),
                  TagPill(
                    label: MaterialType.name(material),
                    background: _materialBg(material),
                    foreground: _materialFg(material),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
