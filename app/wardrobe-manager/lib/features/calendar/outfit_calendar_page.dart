import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/clothing_naming.dart';
import '../../models/models.dart';
import '../../providers/wardrobe_provider.dart';
import '../../services/platform_image.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';

/// 穿搭日历：把 OOTD 记录铺到月历上，看得到「穿了什么、多久没换花样」。
class OutfitCalendarPage extends StatefulWidget {
  const OutfitCalendarPage({super.key});

  @override
  State<OutfitCalendarPage> createState() => _OutfitCalendarPageState();
}

class _OutfitCalendarPageState extends State<OutfitCalendarPage> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final byDay = <int, List<OutfitRecord>>{};
    for (final r in p.records) {
      if (r.date.year == _month.year && r.date.month == _month.month) {
        byDay.putIfAbsent(r.date.day, () => []).add(r);
      }
    }
    for (final list in byDay.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final dayRecords = byDay[_selected.day] ?? const <OutfitRecord>[];
    final monthCount = byDay.length;
    final totalRecords = byDay.values.fold<int>(0, (a, b) => a + b.length);
    final streak = _streak(p.records);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: '穿搭日历',
              eyebrow: 'CALENDAR',
              subtitle: '${_month.year} 年 ${_month.month} 月 · 记录了 $monthCount 天',
              actions: [
                RoundIconButton(
                  icon: Icons.today_outlined,
                  onTap: () {
                    final now = DateTime.now();
                    setState(() {
                      _month = DateTime(now.year, now.month);
                      _selected = DateTime(now.year, now.month, now.day);
                    });
                  },
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  _statStrip(monthCount, totalRecords, streak, p.records.length),
                  const SizedBox(height: 16),
                  _calendarCard(byDay),
                  const SizedBox(height: 20),
                  _dayHeader(dayRecords.length),
                  const SizedBox(height: 10),
                  if (dayRecords.isEmpty)
                    EmptyState(
                      title: '这天还没记录',
                      desc: '在首页对满意的搭配点「就穿这套」，\n它会自动出现在这一格里。',
                      icon: Icons.event_note_outlined,
                    )
                  else
                    ...dayRecords.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RecordTile(record: r),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 连续记录天数（从今天往前数）
  int _streak(List<OutfitRecord> all) {
    if (all.isEmpty) return 0;
    final days = all
        .map((r) => DateTime(r.date.year, r.date.month, r.date.day))
        .toSet();
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    var n = 0;
    // 今天没记就从昨天开始数，避免早上打开显示 0
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (days.contains(cursor)) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  Widget _statStrip(int days, int records, int streak, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
                value: '$days', unit: '天', label: '本月有记录'),
          ),
          _divider(),
          Expanded(
            child: StatTile(
                value: '$records',
                unit: '条',
                label: '本月 OOTD',
                align: CrossAxisAlignment.center),
          ),
          _divider(),
          Expanded(
            child: StatTile(
                value: '$streak',
                unit: '天',
                label: '连续记录',
                color: AppColors.primary,
                align: CrossAxisAlignment.center),
          ),
          _divider(),
          Expanded(
            child: StatTile(
                value: '$total',
                unit: '条',
                label: '累计',
                align: CrossAxisAlignment.end),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 30,
        color: AppColors.hairline,
      );

  Widget _calendarCard(Map<int, List<OutfitRecord>> byDay) {
    // 周一为一周起点
    final first = DateTime(_month.year, _month.month, 1);
    final offset = (first.weekday + 6) % 7; // Mon=0
    final daysInMonth =
        DateTime(_month.year, _month.month + 1, 0).day;
    final cells = offset + daysInMonth;
    final rows = (cells / 7).ceil();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _monthNav(Icons.chevron_left, () {
                setState(() {
                  _month = DateTime(_month.year, _month.month - 1);
                  if (_selected.year != _month.year ||
                      _selected.month != _month.month) {
                    _selected = DateTime(_month.year, _month.month, 1);
                  }
                });
              }),
              Expanded(
                child: Center(
                  child: Text(
                    '${_month.year} / ${_month.month.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5),
                  ),
                ),
              ),
              _monthNav(Icons.chevron_right, () {
                setState(() {
                  _month = DateTime(_month.year, _month.month + 1);
                  if (_selected.year != _month.year ||
                      _selected.month != _month.month) {
                    _selected = DateTime(_month.year, _month.month, 1);
                  }
                });
              }),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: ['一', '二', '三', '四', '五', '六', '日']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.inkSubtle),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < rows; row++)
            Row(
              children: List.generate(7, (col) {
                final index = row * 7 + col;
                final day = index - offset + 1;
                if (day < 1 || day > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 46));
                }
                return Expanded(
                  child: _dayCell(day, byDay[day] ?? const []),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(int day, List<OutfitRecord> records) {
    final date = DateTime(_month.year, _month.month, day);
    final isSelected = _selected.year == date.year &&
        _selected.month == date.month &&
        _selected.day == date.day;
    final isToday = _isSameDay(date, DateTime.now());
    final has = records.isNotEmpty;

    return GestureDetector(
      onTap: () => setState(() => _selected = date),
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.ink
              : has
                  ? AppColors.primarySoft
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isToday && !isSelected
              ? Border.all(color: AppColors.primary, width: 1.2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected || has ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : has
                        ? AppColors.primary
                        : AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 3),
            if (has)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  records.length.clamp(0, 3),
                  (_) => Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.lime : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _monthNav(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: AppColors.ink),
        ),
      );

  Widget _dayHeader(int count) {
    final label =
        '${_selected.month} 月 ${_selected.day} 日 ${_weekdayName(_selected.weekday)}';
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -.3)),
        const SizedBox(width: 8),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.lime,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$count 套',
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900)),
          ),
      ],
    );
  }

  String _weekdayName(int w) =>
      ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][(w - 1) % 7];

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ---------- 当天记录 ----------

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final OutfitRecord record;

  @override
  Widget build(BuildContext context) {
    final p = context.read<WardrobeProvider>();
    final items = record.clothingIds
        .map((id) {
          final list = p.allClothes.where((c) => c.id == id);
          return list.isEmpty ? null : list.first;
        })
        .whereType<Clothing>()
        .toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: items.take(4).map((c) {
                    final img = fileImageWidget(c.displayImagePath,
                        fit: BoxFit.cover);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        width: 26,
                        height: 26,
                        color: AppColors.surfaceAlt,
                        alignment: Alignment.center,
                        child: img ??
                            Text(ClothingCategory.icons[c.category] ?? '👕',
                                style: const TextStyle(fontSize: 12)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // #16 命名同 #7：颜色+衣服名（如「白色T恤×黑色阔腿裤」），
                      // 单品已被删光时回退「N 件 · 场合」
                      items.isNotEmpty
                          ? outfitAutoName(items,
                              max: 3,
                              fallback:
                                  '${items.length} 件 · ${record.occasion == null ? '未标场合' : (Occasion.names[record.occasion] ?? record.occasion!)}')
                          : '${record.clothingIds.length} 件 · '
                              '${record.occasion == null ? '未标场合' : (Occasion.names[record.occasion] ?? record.occasion!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    if (record.notes != null && record.notes!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        record.notes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: AppColors.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (record.temperature != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${record.temperature}°',
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
