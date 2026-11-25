# #11 真 3D 数字人 · 选型方案（供用户拍板，不定案）

> 状态：方案对比文档，未实现任何代码。按交接书要求「先出选型方案给用户确认」。
> 生成：2026-11-24 深夜会话。调研来源见文末链接。

## 0. 结论先行

真 3D = **人体重建（服务/模型）+ 客户端 3D 渲染 + 衣服贴图试穿** 三件独立工程。
建议分两阶段，避免一次咬太多：

- **阶段 1（可较快交付）**：云 API 单图/双图 → 3D 人体网格（GLB）→ App 内可旋转查看素体数字人。**只展示、不换装**，界面明确标注「3D 形象 · 换装开发中」。
- **阶段 2（大工程）**：衣服贴图/换装（UV 映射 + 材质替换，或模型侧多图融合）。工作量与不确定性都高，建议单独立项再评估。

## 1. 重建路线对比（二选一）

| 维度 | 方案 A：云端 image-to-3D API | 方案 B：自托管 TripoSR |
|---|---|---|
| 候选 | [Meshy-6](https://skillsmp.com/pt/creators/svenka-shannon/dispatch/skills-image-to-3d)（~$0.10/次，~60s，带纹理）、[fal.ai Hunyuan3D v3](https://skillsmp.com/pt/creators/svenka-shannon/dispatch/skills-image-to-3d)（~$0.05/次，~30s，PBR 纹理，擅长人脸/人物）、[Tripo API](https://triposr.org/blog/convert-photo-to-3d)（按任务轮询） | [TripoSR 开源自托管](https://triposr.org/blog/convert-photo-to-3d)（免费） |
| 成本 | 按次计费，10 万用户量级需预算管控（后台按设备限频已有） | GPU 服务器成本 + 运维 |
| 质量 | 人物还原较好，Hunyuan3D 对脸/人最优 | 无纹理（❌ 不带贴图），细节一般 |
| 纹理 | ✅（阶段 1 也需要衣服/皮肤基础纹理） | ❌ 需二次贴图 |
| 隐私 | ⚠️ 用户全身照+面部照会上传第三方 API（需用户知情同意，与现有「照片仅在用户主动操作后上传」原则一致但要明示第三方边界） | ✅ 全程自有 |
| 网格可用性 | 输出 GLB/OBJ；拓扑未必适合绑骨骼，高级动画可能要 retopo（[来源](https://triposr.org/blog/convert-photo-to-3d)） | 同左 |
| 接入工作量 | 后台加一类模型用途（如 `avatar3d`，复用现有 MODEL_KIND/密钥加密/连通测试框架）+ 服务端代理或直连转发 | 部署推理服务 + 同样接入 |

**倾向：方案 A（云 API）**。理由：本项目已是「管理员后台统一配置模型 + 密钥」架构，云 API 与该架构完全同构（加一类用途即可）；自托管 GPU 超出当前运维能力。

⚠️ 学术补充路线（了解即可，不建议现在做）：SMPL 参数化人体（SMPLify/PIFuuHD 类）输出**天然可绑骨骼的标准人体网格**，身材参数准确，但自建复杂、脸部还原弱，不满足「还原本人长相」主线。

## 2. 客户端渲染选型

| 候选 | 说明 | 结论 |
|---|---|---|
| [flutter_3d_controller](https://packages.ecosyste.ms/registries/pub.dev/keywords/gltf) 2.3.0 | GLB/GLTF 交互渲染、相机/灯光控制，维护活跃 | ✅ 首选 |
| [model_viewer / model_viewer_plus / pro](https://pub.dev/api/packages/model_viewer_pro/feed.atom) | 基于 Google model-viewer WebView 组件 | 备选（WebView 依赖较重） |

均为新依赖（pubspec 变更），按项目约束需用户点头后引入。

## 3. 与现有架构的接法（阶段 1 蓝图）

1. 后台：`MODEL_KINDS` 加 `avatar3d`（"3D 数字人生成"），管理员配云 API（与豆包/DeepSeek 并列的厂商卡片）；审计加 `avatar3d.generate`。
2. 服务端：`/api/app/avatar3d`（上传全身照+面部照 → 转发重建 API → 轮询/等待 → 返回 GLB 字节，内存转发不落盘，仿现有 `/api/app/avatar`）。
3. App：`flutter_3d_controller` 渲染 GLB；与 v1.8 三视角全身图**并存**（决策 3：不删原功能），数字人页加「3D 形象」页签。
4. 隐私：上传前 App 内明示「照片将发送至管理员配置的 3D 生成服务」；可随时删除（本地 GLB + 服务端不留存）。

## 4. 需要用户确认的 4 个问题

1. 云 API 按次付费可以吗？（预算：1 次生成 ≈ ¥0.3–0.8）
2. 全身照+面部照上传第三方（如 fal.ai/腾讯云）接受吗？还是必须自有服务器？
3. 阶段 1「只可旋转查看、暂不能换装」先交付，可以吗？
4. 选定厂商：Meshy / fal.ai Hunyuan3D / Tripo（或国产云，如腾讯云 3D 生成）？——若拿不准，后台做成可配置多厂商，先接一家实测。

---

# #12 / #13 调研摘要（P3）

## #12 同类开源项目缺口分析

- [wardrobe-Go](https://github.com/FlazeFy/wardrobe-Go)（Go Gin）：自动搭配建议（按历史/可用性/天气/偏好）、周计划、洗衣历史、**数据导出 PDF/Excel**。
- [Libre-Closet](https://github.com/Lazztech/Libre-Closet)（自托管 PWA）：衣橱目录/搭配/离线手机访问/**日历卡上带天气预报预览**（v0.6.0）。
- 对照本项目 v1.8 已有：日历、行李清单、洗护、愿望清单、统计、天气（Open-Meteo）、分享卡。
- **结论：无重大功能缺口**。可借鉴两点：①衣橱/记录**导出 PDF/Excel**（现备份仅 JSON+图片 zip，普通用户不可读）→ 建议列入 v1.9.x；②Libre-Closet 的「日历日卡内嵌天气小字」细节。

## #13 醒图 AI 造型室 · 可借鉴点（不抄 UI，学结构）

来源：[醒图 AI 造型室实测](http://mp.weixin.qq.com/s?__biz=MzkzNzY1ODk5Ng==&mid=2247489817&idx=1&sn=49dc53843390fe5daa4c8e94f93ad496)、[醒图六周年/智能出片三步曲](https://www.fromgeek.com/news/717025.html)。

1. **个人美学档案先行**：先面部分析（脸型/五官量感/肤色季型）生成档案，所有建议挂在档案上——同风格不同人给不同配色。↔ 对应本项目的 profile（性别/身材）+ #8 审美规则：可加「肤色季型」一项，配色规则按季型分组。
2. **场景化整套方案**：「重庆三天两夜」一次给每天穿什么+色系+带什么。↔ 本项目 packing_screen 已是行程制，可升级为「按天整套推荐」视图。
3. **生成过程分阶段可见**：上传/处理等待/结果预览是三种不同的界面状态，等待期不白屏。↔ 对应 #2 后台队列的进度 UI（intake 任务列表正按此设计）。
4. **推荐必带人话理由**。↔ #8 已落地方向（每套推荐 2-3 条中文理由）。
