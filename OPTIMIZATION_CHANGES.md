# wardrobe v1.8 优化改动清单（2026-11-24 20:53–21:38）

四轮迭代：3 子代理并行深审（后台 / 前端排版 / Flutter）→ Lead 集成 → 只读对抗复核 → 二轮精修。
验证：pytest 32 passed（基线 27 + 新增 5 回归）、py_compile 全过、node --check 过、
98 个 dart 文件结构扫描 0 失败、真实 uvicorn 冒烟（healthz / 静态页 / 422 中文信封）通过。

## 一、后台 wardrobe-admin（Python）

- api_app.py：chat 代理非 JSON 对象 body → 400（原 500）；设备注册按 IP 限频 10 次/时
  （原无凭据无频控可刷库）；proxy_edit / white-bg 补 ai_service_enabled 总开关；
  设备接入 TOCTOU → 409；messages 元素类型守卫
- api_auth.py：send_code 限流改 BEGIN IMMEDIATE 事务（并发绕过）；注册 TOCTOU → 409；
  bootstrap token 常量时间比较；SMTP 发信失败删刚插的验证码行（不再白占 60s 重发窗口）
- core.py：XFF 取末段（原首段可伪造污染审计）；codes 表过期行清理；
  ACTION_LABELS 补 user.reset；邮件 TTL<60s 文案修正
- api_admin.py：新建即停用模型不挂 is_default；summary 新增「今日 AI 调用」统计；
  list_users 收紧 require(3)（与权限矩阵对齐）
- server.py：全局异常落日志（logger.exception）；422 统一 {ok,message} 中文信封
- tests/test_api.py：新增 5 个回归测试（test_28–32），共 32 项全绿
- README.md：备份 DB 路径、测试数（32）、部署命令（zip 而非 tar）、
  密钥直写 /etc/wardrobe-admin.env（防 deploy.sh 模板覆盖）

## 二、管理页前端 static/（排版 + JS）

- 排版：三张表窄屏撑破 → table-wrap 横滚（键盘可达）；弹窗 safe center（高溢出可滚顶）；
  100vh/92vh → dvh 回退；次要文字对比度 3.64→4.77:1、链接色 4.0→4.67:1（AA）；
  长密钥/URL overflow-wrap:anywhere；窄屏筛选行/user-chip 溢出；触控目标 ≥44px；
  焦点环；toast 超屏；加载态；用户表空态
- JS：dev_code 回显补 esc()（唯一 XSS 缺口）；会话中 401 自动清凭证退登录
  （auth 接口除外）；12 个写操作 lock() 防连点；日志查询乱序守卫 + 关键词保持 +
  IME-safe 回车；codeTimer 泄漏；弹窗 Esc/遮罩关闭；登录表单回车提交
- 权限矩阵：设备/日志 tab 放权给管理员（级别 2，与后端 require(2) 一致）；
  设备「移除」按钮收归超管可见（require(3)）；概览「最近操作」同步放权

## 三、Flutter App wardrobe-manager

- storage_service.dart：9 个写方法 + 8 个读方法补 !_ready 守卫（Hive 未就绪不再
  LateInitializationError 红屏 / 假数据），共 46 处守卫
- wardrobe_backend.dart：版本兜底 '1.7.0'→'1.8.0'（设备上报曾永远 1.7.0）；
  Dio 单例复用；config() 在 401/403（设备被停用）时不再退回旧缓存显示「已连接」
- ai_service / vision / text / try_on 共 8 处 v1.8 过时文案
  （「去 AI 网关设置」等已删除入口的引导）→「管理员还没开通…」；
  _describeDio 透传后台 {ok,message} 中文信封
- backup_service_io.dart：新增功能——行李清单纳入备份（导出/恢复/完整字段映射，
  老备份兼容、幂等恢复）；export/restore 补 isReady 判定（消灭空 zip 假成功）
- wardrobe_provider.dart：add/update/deleteClothing + addClothingBatch 四处
  isReady 守卫（内存镜像不再谎报保存成功）
- auto_split_provider.dart：任务代际令牌 _runTokens——180s 超时后底层僵尸请求
  返回时作废（不覆盖新一轮结果、裁片不重复生成、删除任务即在途作废）

## 四、新功能

1. 后台概览「今日 AI 调用」统计卡片（summary 端点 + 前端 + 测试断言）
2. 行李清单纳入备份/恢复

## 五、遗留建议（未做，按优先级）

1. 设备凭据轮换需 App + 服务端同步改协议（现靠 IP 限频缓解）——最重要遗留
2. auto_split 曾标记的 print()→debugPrint 清理（约 30 处，release 进 logcat）
3. splitTasks 不入备份（源图为旧机绝对路径，属产品取舍）
4. Dart 侧请在有 SDK 的机器跑 flutter analyze + flutter test 后再出包

——位置：/root/workspace/admin-v18-src/（app/wardrobe-manager + server/wardrobe-admin）

## 六、深夜加更（2026-11-25 03:24–04:20，用户指定「修复到 5:00」轮）

### 服务端（6 处逻辑修复，线上生产已同步生效并验证）
1. proxy_chat 上游状态掩蔽：>=400 才算失败改为 >=300，且 2xx 必须能解析为 JSON（防 base_url 配错拿到 200+HTML 被包成 JSON 发给 App）
2. _run_image_edit 超时重试带 170s 总预算（_IMAGE_TOTAL_BUDGET）：重试前查剩余预算，不足 10s 直接失败——90s×2 重试会撞 nginx 180s read 超时，白付生成费还被掐成 HTML 504
3. register 首用户竞态：COUNT 判定与 INSERT 移入同一 BEGIN IMMEDIATE 写锁，多 worker 并发首注册不再产生双超管
4. _credential_endpoint Gemini 端点归一：":generateContent" / "/v1beta" 简写补成与 _gemini_url 同构的完整路径，直连凭证拿到即用
5. test_model 对 Gemini 改用 x-goog-api-key 头（Bearer 一律 401，有效 Key 被误报「密钥被拒绝」）
6. white_bg off/local 模式提示分离（off 不再误导「用手机本地处理」）
附：nginx client_max_body_size 10m→14m（后端 12MB 中文校验先于 nginx HTML 413）；静态资源 ?v=1.9.1 强刷。
验证：pytest 38/38（含 2K→1K 断言同步）；线上 43/43。

### App（8 处逻辑修复）
1. intake 180s 超时误报→重试→重复入库三件套（savedClothingId 前移 + 超时兜底改判完成 + retryTask 入口守卫）
2. intake 白底流水线重复分割：复用已抠图结果（steps: WhiteBgSteps(segment: false)）
3. intake server 模式白底直连漏接：新增 _serverWhiteBgPipeline()（有 white_bg 凭证直连，无凭证走代理）
4. fetchDirectCredential 401 不刷新设备凭据死循环：401 先 token(refresh:true) 重试一次
5. naming：Title Case 词典词误判品牌（命中品类/颜色/图案词典不当品牌）
6. naming：_zhNameHasColor 补扫 _enColorNames.values（防「蓝色宝蓝连衣裙」颜色重复）
7. digital_avatar 换形象旧 ui.Image 泄漏：setState 前 _sheet?.dispose()
8. intake deleteTask 的 _runTokens 条目移除（会话级小泄漏）
附：print→debugPrint 41 处（exif_cleaner/cutout 刻意保留 4 处 print：Isolate.run 文件不引 dart:ui）；weather/style 两处 analyzer info 顺手修。
验证：102 dart 文件括号状态机扫描全平衡；新 API 调用点交叉核对一致。

### 后台 UI（Linear 基准精修，线上已生效）
favicon 衣架（消 404）、双层暖阴影、150ms 微交互、卡片 hover/一次性 fade-in、概览数字 countUp+tabular-nums、表格 sticky 表头+斑马纹+内部滚动、空态 emoji 插画、safe-area 顶部/底部、prefers-reduced-motion 兜底、viewport-fit=cover。无头浏览器 0 console 错误验证，备份 *.bak-lcs 可回滚。

### 竞品调研
docs/v52-research-wardrowbe.md：GitHub wardrowbe（866★）功能对照 + v5.2 候选清单（每日穿搭推送/反馈评分回流/衣柜分析页/家庭模式/AI 能力分级开关）与我方既有优势（生图/直连/凭证安全/多模型路由）。

### 模型与性能（本session早前已上线）
白底主力 nano-banana-2.1（14.8s）+ 方舟 1K（10.4s 备胎停用）；试穿/数字人 nano-banana-2.1（8.9s）；识别链路 768px 压缩（上传砍半省 vision token）；超时自动重试。

## 七、v1.9.1 真机二轮（2026-11-25 06:56–08:00，用户 20 条反馈全修）

### 崩溃根治（#1，含金量最高）
isolate 闭包 Context 污染：Dart 同作用域多闭包共享变量槽打包（Context num_variables: 4），
mine() 局部函数捕获 task 后，Isolate.run 闭包把整个 Context（连 HiveObject→BoxImpl→
StorageBackendVm→SendPort 链）序列化进 isolate → object is unsendable，重试永败。
修复：intake/auto_split 各提取 static _cleanInIsolate(Uint8List) 独立函数（闭包 Context
只含参数 data）；cutout/local_white_bg 核查安全（唯一闭包+先拷贝字段）。

### 交互与推荐（#2-12、16、19，引擎确定性根治）
- 数字人：成功后 jumpToPage 空态抛 No element（先解码后跳页+hasClients 守卫）；模型回
  单图误按三联裁切（宽高比判定 triptych/contain 分支）；重新生成按钮禁用态
- 3D 展馆：卡片 contain+内边距防裁身；转盘半径窄屏 clamp
- 试穿/愿望清单删除入口（wish 的 onDelete 回调本是死代码）
- 穿戴顺序 _wearRank（帽→上衣→下装→外套→鞋→配饰），中心化 pieces getter
- 分享：outfitAutoName「颜色×衣服名」自动命名、水印 VestiAI、新增杂志/波普两套模板
- 推荐引擎确定性根治：seed 参数+每槽 top-3 稳定轮换（日期盐/风格盐/分钟种子），
  风格命中 +9/场合错配 -4，换一套/风格/场合/本周穿搭四路全部真正变化
- 保存这套：预填自动名弹窗可改、保存中状态、行解析改 allClothes 防换空间丢图

### 功能补齐（#13-18）
- #13 衣橱页「换白底图」：white_bg_replace.dart 后台控制器（直连/代理/local 三通道
  复用）+ 详情/长按两入口 + 卡片进度遮罩 + 失败回退可重试
- #14/16 命名：Clothing.displayName 委托 clothingDisplayName（颜色+中文品类），
  日历/统计/分享自动生效
- #15 颜色自由：normalizeAiColor（词典→中文原文→拉丁首字母大写），5 个 AI 写入点
- #17 备份导入：file_picker 9.2.3 + 备份页「导入备份」按钮（确认→restore→刷新）
- #18 权限：Manifest 仅 INTERNET 核查无误；设置页加系统 Photo Picker 免授权说明

### 构建坑（box 云编 AGP 9）
file_picker 8.x 与 AGP 9 不兼容（does not specify compileSdk）→ 升 9.2.3 +
root gradle subprojects 反射 setCompileSdk(36)（排除 app）+ app 显式 compileSdk=36。
style_sheet.dart 补 OutfitPlan import（B 代理漏）。

交付：https://file.autoi.icu/f/7vyApBw（wardrobe-v1.9.1-arm64.apk 25.9MB，
sha1 efd8042f）+ 源码 zip 同步更新。
