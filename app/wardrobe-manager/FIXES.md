# wardrobe-manager v1.5 稳定性修复清单

版本：1.5.0+15（修复版）
范围：5 个并行子代理修复 41 个文件，全部最小 diff，不重构、不改 UI 结构、不加依赖。
验证：91 个 Dart 文件括号平衡 ✓；跨模块接口兼容 ✓；新增符号定义/调用配对 ✓。

## 一、崩溃风险修复

- **Hive 旧数据兼容**（9 个 .g.dart 适配器）：旧版本 App 写入的记录字段少于新 schema 时，
  非空字段读取会 TypeError 导致全表崩溃；现在全部改为空安全 + 构造器同款默认值。
- `wardrobe_provider.dart` `currentSpace`：`_spaces` 为空（Hive 未就绪）时抛 StateError → 返回 `WardrobeSpace.builtin()` 兜底。
- `wardrobe_provider.dart`：`togglePacked` / `purchaseWish` 的 `firstWhere` 无 orElse → indexWhere + 空安全返回。
- `wardrobe_provider.dart`：5 处 `await _storage.saveProfile(_profile!)` 在 profile 未加载时强解包崩溃 → 判空后再保存。
- `auto_split_provider.dart`：6 处任务 `firstWhere` 无 orElse（任务被删除后调用即崩）→ indexWhere + 早返回；
  应用重启后卡 `running` 的任务自动重置为 `failed`（可重试）。
- `auto_split_page.dart` `try_on_page.dart`：确认页/首帧的空断言与任务缺失崩溃 → 判空守卫
  （`tp.profile!` 首帧必崩已修）。
- `share_card_page.dart`：pieces 为空时网格除零 → `columns.clamp(1, 3)`。

## 二、页面退出后的生命周期

- `try_on_provider.dart` / `auto_split_provider.dart`：页面退出（dispose）后后台任务仍在跑，
  `notifyListeners()` 打在已销毁对象上崩溃 → `_disposed` 标志 + `_notify()` 守卫；任务照常跑完落库不丢。
- `wishlist_page.dart` / `clothing_card.dart`：弹窗内 `TextEditingController` 从未 dispose（泄漏）→ 关闭即释放。
- `style_analysis_page.dart`：`await` 后 `setState` 无 `mounted` 守卫 → 已补。

## 三、连点重复提交（6 个页面）

home「就穿这套」/ outfit「保存这套」「今天穿这套」/ outdoor「保存为搭配」/ record「记今天穿搭」/
add_clothing「确认入库」：连点会插入重复打卡或重复单品 → `_saving` 防抖标记 + 按钮置灰 + try/finally 复位。

## 四、网络与 AI 网关健壮性

- `weather_service`：Dio 错误与脏 JSON（字段缺失时 null 强转）直接炸到页面 → 统一分类成中文提示
  （超时 / 5xx / 网络不可达 / 数据格式异常）。
- `ai_service` `testConnection`：裸调无 catch，英文堆栈直达用户 → 中文分类异常。
- `try_on_service`：结果图下载无超时（CDN 卡死则任务永远「生成中」）→ 连接 20s / 接收 60s。
- 三个网关（拆分 / 风格 / 试穿）的响应体容错：`looseDecode` 让 text/plain 或前后带废话的 JSON 也能解析，
  失败保留原始响应供「查看原始响应」。
- `ai_service`：`WardrobeAnalysisResult` 补 `isFallback` 字段，整柜识别失败返回兜底数据时上层可判别。
- `cutout_service`：损坏图片在 image 库解码/裁剪时抛异常 → 整体 try-catch 后返回原图（兑现「失败退回原图」承诺）。

## 五、备份与图片管家

- `backup_service_io` 导出：单图读取失败不中断整个导出；磁盘满时删除半成品 zip。
- 恢复：`data.json` 损坏给中文提示；逐条容错（坏记录跳过并计数，不再炸掉整个恢复）。
- `image_store_io`：目录初始化一次瞬时失败会永久锁死图片仓库 → 移除闩锁，允许重试。
- `image_maintenance_io`：压缩失败残留 `.tmp` 立即清理；扫描单文件 stat 失败跳过不中断。

## 六、其他

- 穿搭日历：切月后选中日期留在旧月导致明细串月 → 切月时重置选中日期；跨年/闰月边界核验无误。
- outfit 缩略图：引用衣物被删后显示毫不相干的第一件 → 按存活 id 解析，全部失效回占位图标。
- profile 城市名过长溢出 → Flexible + ellipsis。
- wishlist 冷静期提示窄屏溢出 → Expanded + ellipsis。
- `android/gradle.properties`：JVM 内存 4096m → 1024m（适配 2G 内存构建机）。

## 改动文件（41）

providers/wardrobe_provider.dart
models/packing_list.dart
models/{clothing,outfit,outfit_record,packing_list,split_task,try_on_task,user_profile,wardrobe_space,wish_item}.g.dart
services/{ai_service,weather_service,vision_gateway_service,text_gateway_service,try_on_service,cutout_service,backup_service_io,image_store_io,image_maintenance_io,duplicate_detector,exif_cleaner,gateway_store,share_service_io,file_bytes_io}.dart
features/auto_split/{auto_split_provider,auto_split_page}.dart
features/try_on/{try_on_provider,try_on_page}.dart
features/wishlist/wishlist_page.dart
features/calendar/outfit_calendar_page.dart
features/style_analysis/style_analysis_page.dart
features/share/share_card_page.dart
screens/{home,outfit,outdoor,record,profile}_screen.dart
widgets/{clothing_card,style_sheet,add_clothing_sheet}.dart
android/gradle.properties

## 已核对无需修复

- 4 个测试文件（wardrobe/auto_split/iteration1/iteration2）逐符号对账零缺陷，未改动。
- pubspec 依赖约束与 lock 全部相容，版本号一致。
- 备份恢复「图片缺失只计数」、试穿失败降级搭配预览、多衣橱删除退回主衣橱等 README 承诺逐处核对成立。

## 备注

本修复版未在目标机构上跑 `flutter analyze`（构建机当时不可达）；已做静态词法/交叉引用验证。
后续构建前建议先跑一次 `flutter analyze` 与 `flutter test` 复核。
