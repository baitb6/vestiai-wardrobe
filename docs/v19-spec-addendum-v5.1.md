# v1.9 交接规格书 · v5.1 增补与勘误（2026-11-25 凌晨）

> 基于 v5 原规格书（81cb7d89cb2f925e_v5.md）。本文件只记录：①评审修正的落实 ②各需求实际实现状态 ③联调契约 ④遗留。与 v5 冲突处以本文件为准。
> 施工基线：`/root/workspace/admin-v18-src`（本工作区 v1.8 优化版直接演进），版本已升 **1.9.0+3024**。

## 0. 基线勘误（v5 §1.2/1.3 的修正）

- v5 所述「82 项客户端测试全绿 / analyze 0-0 / versionCode 5023/6023/8023/9023」对应**另一工作区**的 v1.8 快照（build 3023）。本工作区快照为 build 3021 起步、无 Flutter SDK，Dart 侧以「结构级静态验证（括号/引号状态机全库 0 失败）+ 密钥纪律 grep + 既有测试语义逐条核对」替代编译验证。
- **合并指引**：若要把两份合流，以 82 测试全绿那份为编译基线，把本工作区的改动清单（见 §2）按文件移植后重跑 `flutter analyze && flutter test`。pubspec 版本统一取 `1.9.0+3024`（高于两份基线）。
- v5 §1.2 所列上一轮已修内容与本工作区 `OPTIMIZATION_CHANGES.md` 一致，无回退。

## 1. 六条评审修正的落实

| # | 修正 | 状态 |
|---|---|---|
| 1 | 双基线歧义 | 本文件 §0 处置：以本工作区为施工基线，合流指引如上 |
| 2 | #3 根因「待复现」 | ✅ 已按此执行：全库仅 3 个 isolate 点且当前快照均纯数据可发送；唯一加固 = cutout_service 闭包拆 this 捕获；真机复现指引已交付（logcat 过滤法），不盲改 |
| 3 | README「永不下发」承诺 | ✅ README.md:17 与后台模型页文案已改为准确描述；审计 credential.issue 不落明文 Key（test_33 断言全日志无 Key 原文） |
| 4 | 「今日 AI 调用」口径 | ✅ 字段名保留（兼容），语义注明「仅代理流量」；新增 `credentials_today`（今日凭证下发数）卡片 |
| 5 | 设备停用被直连绕过 | ✅ 撤销语义 = 停用设备（代理+凭证一并 403）或关 `direct_ai_enabled`（停发新凭证）；已发凭证 TTL 内离线有效（默认 24h，可 1-168h 调，端点侧 clamp 兜底）。强吊销需换厂商 Key（文档已如实写明） |
| 6 | 队列复用 | ✅ intake 队列复刻 auto_split 的 _pump + 代际令牌骨架（见 §2 #2） |

## 2. 14 条需求实现状态（截至本文件生成时）

| 需求 | 状态 | 实现位置 |
|---|---|---|
| #1 中文命名 | ✅ | clothing_naming.dart 新增 144 键颜色/118 键品类/92 品牌词典 + parseChineseClothingName（n-gram 归一匹配，品牌剥离，宁缺毋滥）；入库两链（auto_split 确认/add_clothing_sheet 预填）接入；naming_test 62 断言（新增 54），算法 python 移植对拍 51/51 |
| #2 应用内后台队列 | ✅ | lib/features/intake/（intake_provider 415 行 + 任务列表页 280 行）：EXIF→识别→中文名→抠图→白底→入库全自动串行（_pump+代际令牌+180s 超时）；失败=轻提示+重试+自定义保存（AddClothingSheet 预填直达确认段）；wardrobe_screen FAB 常驻进度徽标；内存队列重启清空（Hive 持久化留下轮） |
| #3 isolate | ✅ 防御性加固完成 | cutout_service.dart:52-54；真凶待真机复现（当前快照 3 处均纯数据） |
| #4/#9 协议 | ✅ 服务端 Gemini 适配 | api_app.py `_openai_to_gemini/_gemini_to_openai/_gemini_url/_is_gemini`，chat 代理分支；含 6 个 mock 测试。真实厂商实测仍待可用 Key（v5 已注明） |
| #5+#10 两步白底 | ✅ | lib/services/white_bg_pipeline.dart：WhiteBgSteps{segment,beautify} 各自可关；segment=LocalEdgeCutout 透明底、beautify=server 代理/直连注入口/本地合成三路由；每步独立 try/catch 永不抛异常；降级矩阵见子代理报告（均不阻断入库） |
| #7 数字人两 bug | ✅ | digital_avatar_page.dart：cover 裁剪分支修正（:527-535）+ 试穿改用裁切正面形象 `_deriveTryOnPerson`（:75-113），绝不回退上传原图 |
| #11 真 3D | ✅ 选型方案已出 | docs/v19-research-3d-and-benchmarks.md（两阶段 + 4 个待用户拍板问题） |
| #12/#13 调研 | ✅ | 同上文档：无重大功能缺口（可借鉴 PDF 导出）；醒图四借鉴点（美学档案/场景化方案/分阶段状态/带理由推荐） |
| #6 性别搭配 | ✅ | recommendation_engine.dart OutfitRules.filterByGender（保守+回退保护）+ provider 传 gender + outfit_screen 轻提示跳设置 |
| #8 审美规则 | ✅ | OutfitRules：主色 ≤3/冲突表/温度硬排除/场合硬排除/版型平衡/新鲜度 + buildReasons 中文理由（2-3 条）；outfit_screen 渲染理由行；test/recommendation_rules_test.dart 12 test/33 断言 |
| 决策 1 直连（#14） | ✅ | 服务端 `POST /api/app/credential`（api_app.py:183-219）+ App 直连（direct_ai_client.dart 226 行 + wardrobe_backend.directCredential + vision/try_on/add_clothing_sheet 白底接入）；无凭证/过期自动回代理 |
| 决策 4 降级 | ✅ | intake 失败态 = 轻提示 + 重试 + 自定义保存出口（AddClothingSheet 预填原图+草稿直达确认段）；白底每段独立 try/catch；StateError 前缀 "Bad state: " 已从用户可见错误中剥离 |
| 版本 | ✅ | pubspec 1.9.0+3024；服务端 healthz/api_version/static ?v= 全部 1.9.0 |

服务端测试：**38 passed**（既有 32 未动 + 新增 6）；`py_compile` 全过；`node --check` 过；uvicorn 冒烟（healthz 1.9.0、设备注册 ai.direct:true、credential 接口通）。

## 3. 直连联调契约（B 代理与 A 代理对齐结果）

- `POST /api/app/credential`（Bearer 设备凭据，受设备限频）→ `{ok, expires_at, ttl_hours, models:{vision|text|edit|avatar|white_bg:{base_url, model, api_key, endpoint}}, message}`
- endpoint 带前导斜杠（`/chat/completions`、`/images/edits`、`/models/{model}:generateContent`）；空则 App 端按用途默认拼接
- `GET /api/app/config` 的 `ai.direct` 布尔指示是否值得申请凭证（契约小增量，向后兼容）
- App 侧过期判定提前 60 秒；401/403/ok=false 清缓存凭证；直连失败本轮不回退代理（防双倍图片上传），下轮自然重评
- Gemini 图像编辑类模型**不走服务端** images/edits 链路（协议不同），配置给 App 直连使用

## 4. 遗留与下一步

1. **真机/编译验证**：Dart 全部改动（约 20 文件）未经编译——合流后必跑 `flutter analyze && flutter test`（含新增 naming/recommendation_rules 测试）
2. 真实厂商端到端（含 Gemini）仍待可用测试 Key
3. #3 若真机复现：`adb logcat | grep -iE 'unsendable|Isolate'`，按错误前缀（识别失败：/抠图）三选一定位
4. 3D 选型 4 个问题等用户拍板（云 API 费用/隐私边界/阶段 1 不换装/厂商）
5. v1.9 未做服务端部署与打包（沿用用户「不打包」要求；交付为源码 zip）
