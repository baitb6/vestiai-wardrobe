import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/clothing_naming.dart';
import '../features/share/share_card_page.dart';
import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/kit.dart';

/// 心情选项（值保存进 OutfitRecord.mood）
class _MoodOption {
  const _MoodOption(this.value, this.emoji, this.label);

  final String value;
  final String emoji;
  final String label;
}

const List<_MoodOption> _moodOptions = [
  _MoodOption('happy', '😄', '开心'),
  _MoodOption('calm', '😊', '不错'),
  _MoodOption('neutral', '😐', '一般'),
  _MoodOption('tired', '😫', '疲惫'),
];

String? _moodLabel(String? mood) {
  if (mood == null) return null;
  for (final option in _moodOptions) {
    if (option.value == mood) return '${option.emoji} ${option.label}';
  }
  return mood;
}

/// 穿搭日历：按月浏览每天的穿搭记录，一键记录今天穿了什么。
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  /// 当前展示的月份（只使用 year / month，day 固定为 1）
  DateTime _displayMonth = _monthOf(DateTime.now());

  static DateTime _monthOf(DateTime date) => DateTime(date.year, date.month, 1);

  void _switchMonth(int delta) {
    setState(() {
      _displayMonth = DateTime(
        _displayMonth.year,
        _displayMonth.month + delta,
        1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(84),
        child: SafeArea(
          bottom: false,
          child: ScreenHeader(
            title: '穿搭日历',
            eyebrow: 'OOTD LOG',
            subtitle: '${_displayMonth.month} 月',
          ),
        ),
      ),
      body: Consumer<WardrobeProvider>(
        builder: (context, provider, _) {
          final clothingMap = <String, Clothing>{
            for (final c in provider.clothes) c.id: c,
          };
          final monthRecords = provider.getRecordsForMonth(
            _displayMonth.year,
            _displayMonth.month,
          );
          return SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCalendarCard(monthRecords, clothingMap),
                  const SizedBox(height: 14),
                  _buildStatsCard(monthRecords, clothingMap),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('记今天穿了什么',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ============ 日历卡片 ============

  Widget _buildCalendarCard(
    Map<int, List<OutfitRecord>> monthRecords,
    Map<String, Clothing> clothingMap,
  ) {
    const weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
    final monthStart = _displayMonth;
    final leadingBlanks = monthStart.weekday - 1; // 周一开头对齐
    final daysInMonth = DateTime(monthStart.year, monthStart.month + 1, 0).day;
    var cellCount = leadingBlanks + daysInMonth;
    cellCount = ((cellCount + 6) ~/ 7) * 7; // 补齐整行空格

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.chevron_left,
                  color: AppColors.inkMuted,
                ),
                onPressed: () => _switchMonth(-1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${monthStart.year}年${monthStart.month}月',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.chevron_right,
                  color: AppColors.inkMuted,
                ),
                onPressed: () => _switchMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSubtle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.92,
            ),
            itemCount: cellCount,
            itemBuilder: (context, index) {
              if (index < leadingBlanks) return const SizedBox.shrink();
              final day = index - leadingBlanks + 1;
              final cellDate = DateTime(monthStart.year, monthStart.month, day);
              final dayRecords =
                  monthRecords[day] ?? const <OutfitRecord>[];
              return _buildDayCell(cellDate, dayRecords, clothingMap);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    DateTime date,
    List<OutfitRecord> dayRecords,
    Map<String, Clothing> clothingMap,
  ) {
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final dotCount = dayRecords.length.clamp(0, 3).toInt();
    final temperature = _firstTemperature(dayRecords);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showDaySheet(date, dayRecords, clothingMap),
      child: Column(
        children: [
          const SizedBox(height: 2),
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: isToday
                ? const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primarySoft,
                  )
                : null,
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                color: isToday ? AppColors.primary : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 4,
            child: dotCount > 0
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < dotCount; i++)
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  )
                : null,
          ),
          SizedBox(
            height: 11,
            child: temperature != null
                ? Center(
                    child: Text(
                      '$temperature°',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.inkSubtle,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  int? _firstTemperature(List<OutfitRecord> records) {
    for (final record in records) {
      if (record.temperature != null) return record.temperature;
    }
    return null;
  }

  // ============ 月度统计卡片 ============

  Widget _buildStatsCard(
    Map<int, List<OutfitRecord>> monthRecords,
    Map<String, Clothing> clothingMap,
  ) {
    var totalRecords = 0;
    final frequency = <String, int>{};
    for (final list in monthRecords.values) {
      totalRecords += list.length;
      for (final record in list) {
        for (final id in record.clothingIds) {
          frequency[id] = (frequency[id] ?? 0) + 1;
        }
      }
    }
    final recordedDays = monthRecords.length;
    final topEntries = frequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    const medals = ['🥇', '🥈', '🥉'];

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('本月统计'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Center(child: _buildStatBlock('$recordedDays', '记录天数')),
              ),
              Container(width: 1, height: 34, color: AppColors.hairline),
              Expanded(
                child: Center(child: _buildStatBlock('$totalRecords', '记录条数')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (topEntries.isEmpty)
            const Text(
              '本月还没有穿着频次数据',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSubtle),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < topEntries.length && i < 3; i++)
                  TagPill(
                    iconEmoji: medals[i],
                    label:
                        '${clothingMap[topEntries[i].key] == null ? topEntries[i].key : clothingDisplayName(clothingMap[topEntries[i].key]!)}'
                        ' ×${topEntries[i].value}',
                    foreground:
                        i == 0 ? AppColors.primary : AppColors.inkMuted,
                    background:
                        i == 0 ? AppColors.primarySoft : AppColors.surfaceAlt,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatBlock(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
        ),
      ],
    );
  }

  // ============ 某天记录详情 ============

  void _showDaySheet(
    DateTime day,
    List<OutfitRecord> records,
    Map<String, Clothing> clothingMap,
  ) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${day.month}月${day.day}日'
                          ' · 周${weekdays[day.weekday - 1]}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 20,
                          color: AppColors.inkMuted,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: records.isEmpty
                        ? _buildNoRecordHint()
                        : Column(
                            children: [
                              for (var i = 0; i < records.length; i++) ...[
                                if (i > 0) const SizedBox(height: 10),
                                _buildRecordDetail(
                                  records[i],
                                  clothingMap,
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoRecordHint() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.event_busy, size: 40, color: AppColors.inkSubtle),
            SizedBox(height: 12),
            Text(
              '这天没有穿搭记录',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordDetail(
    OutfitRecord record,
    Map<String, Clothing> clothingMap,
  ) {
    final clothingPills = <Widget>[
      for (final id in record.clothingIds)
        TagPill(
          label: clothingMap[id] == null ? id : clothingDisplayName(clothingMap[id]!),
          icon: Icons.checkroom,
          foreground: AppColors.ink,
        ),
    ];

    final metaPills = <Widget>[
      if (record.weather != null || record.temperature != null)
        TagPill(
          icon: Icons.wb_cloudy_outlined,
          label: [
            if (record.weather != null) record.weather!,
            if (record.temperature != null) '${record.temperature}°C',
          ].join(' · '),
        ),
      if (record.occasion != null)
        TagPill(
          icon: Icons.local_activity_outlined,
          label: Occasion.names[record.occasion] ?? record.occasion!,
        ),
      if (_moodLabel(record.mood) != null)
        TagPill(
          label: _moodLabel(record.mood)!,
          foreground: AppColors.accent,
          background: AppColors.accentSoft,
        ),
    ];

    return SoftCard(
      color: AppColors.surfaceAlt,
      borderColor: AppColors.hairline,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 6, children: clothingPills),
              ),
              if (clothingPills.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    final pieces = record.clothingIds
                        .map((id) => clothingMap[id])
                        .whereType<Clothing>()
                        .toList();
                    if (pieces.isEmpty) return;
                    showShareCard(
                      context,
                      pieces: pieces,
                      title: outfitAutoName(pieces, fallback: '这一天穿这样'),
                      subtitle: [
                        if (record.weather != null) record.weather!,
                        if (record.temperature != null)
                          '${record.temperature}°C',
                      ].join(' · '),
                      occasion: record.occasion == null
                          ? null
                          : Occasion.names[record.occasion!],
                      date: record.date,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 8),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.ios_share,
                        size: 15, color: AppColors.inkMuted),
                  ),
                ),
            ],
          ),
          if (metaPills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: metaPills),
          ],
          if (record.notes != null && record.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              record.notes!,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.inkMuted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============ 记录今天穿了什么 ============

  Future<void> _showAddSheet(BuildContext context) async {
    final provider = context.read<WardrobeProvider>();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AddRecordSheet(provider: provider),
    );
    if (saved == true && mounted) {
      final now = DateTime.now();
      setState(() {
        _displayMonth = DateTime(now.year, now.month, 1);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已记录今天的穿搭 ✅')),
      );
    }
  }
}

/// 「记今天穿了什么」底部弹层
class _AddRecordSheet extends StatefulWidget {
  const _AddRecordSheet({required this.provider});

  final WardrobeProvider provider;

  @override
  State<_AddRecordSheet> createState() => _AddRecordSheetState();
}

class _AddRecordSheetState extends State<_AddRecordSheet> {
  final TextEditingController _notesController = TextEditingController();
  final Set<String> _selectedClothingIds = <String>{};
  String? _occasion;
  String? _mood;

  /// 保存进行中标记：防止「保存」连点插入重复记录
  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final notes = _notesController.text.trim();
      final record = OutfitRecord(
        id: 'record_${DateTime.now().microsecondsSinceEpoch}',
        clothingIds: _selectedClothingIds.toList(),
        date: DateTime.now(),
        occasion: _occasion,
        mood: _mood,
        notes: notes.isEmpty ? null : notes,
        createdAt: DateTime.now(),
      );
      await widget.provider.addOutfitRecord(record);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clothes = widget.provider.clothes;
    final byCategory = <String, List<Clothing>>{};
    for (final clothing in clothes) {
      byCategory.putIfAbsent(clothing.category, () => []).add(clothing);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: SectionTitle('记今天穿了什么'),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SheetLabel('穿了什么'),
                      if (clothes.isEmpty)
                        _buildEmptyWardrobeHint()
                      else
                        for (final category in ClothingCategory.names.keys)
                          if (byCategory.containsKey(category))
                            _buildCategoryGroup(
                              category,
                              byCategory[category]!,
                            ),
                      const SizedBox(height: 14),
                      const _SheetLabel('场合（可不选）'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in Occasion.names.entries)
                            _PickChip(
                              label: entry.value,
                              selected: _occasion == entry.key,
                              onTap: () {
                                setState(() {
                                  _occasion =
                                      _occasion == entry.key ? null : entry.key;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const _SheetLabel('心情'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in _moodOptions)
                            _PickChip(
                              label: '${option.emoji} ${option.label}',
                              selected: _mood == option.value,
                              onTap: () {
                                setState(() {
                                  _mood = _mood == option.value
                                      ? null
                                      : option.value;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const _SheetLabel('备注'),
                      TextField(
                        controller: _notesController,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.ink,
                        ),
                        decoration: const InputDecoration(
                          hintText: '今天穿搭的感受…（可不填）',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed:
                              _selectedClothingIds.isEmpty || _saving
                                  ? null
                                  : _save,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyWardrobeHint() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.checkroom, size: 40, color: AppColors.inkSubtle),
            SizedBox(height: 10),
            Text(
              '衣橱里还没有衣物',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.inkMuted,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '先到「衣橱」页添加衣物，再来记录今天穿了什么',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.inkSubtle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGroup(String category, List<Clothing> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${ClothingCategory.names[category] ?? category}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.inkMuted,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final clothing in items)
                _PickChip(
                  label: clothing.displayName,
                  selected: _selectedClothingIds.contains(clothing.id),
                  onTap: () {
                    setState(() {
                      if (_selectedClothingIds.contains(clothing.id)) {
                        _selectedClothingIds.remove(clothing.id);
                      } else {
                        _selectedClothingIds.add(clothing.id);
                      }
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 弹层内的小节标题
class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

/// 多选 / 单选胶囊
class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.primary : AppColors.inkMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
