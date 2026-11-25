# 衣橱管家 · 管理后台（ai.slongb.xyz）

统一管理 App 的 AI 模型、访问权限和操作审计。

**App 端不再有任何模型配置入口**：用户看不到接口地址、模型 ID、API Key，
打开 App 自动接入；模型由管理员在这里配置一次，全端生效。

---

## 1. 它管什么

| 能力 | 说明 |
|---|---|
| 注册 / 登录 | 账号 + 密码 + 邮箱验证码；验证码有有效期、重发间隔、每小时上限 |
| 权限分级 | `只读` → `管理员` → `超级管理员`，首个注册用户自动是超级管理员 |
| AI 模型 | 四类用途（视觉识别 / 文本分析 / 图像编辑 / 白底商品图）各自独立配置、启停、设默认 |
| 密钥安全 | API Key 用 AES-GCM 加密后存 SQLite，管理接口只回显掩码；**代理模式不下发明文 Key**，开启「允许 App 直连」后按设备下发短时直连凭证（含解密 Key、有效期可配），停用设备即可撤销 |
| 连通测试 | 每个模型可一键测试，结果与耗时记在模型卡片上 |
| App 设备 | 每台手机自动接入，可单独停用/移除；能看到调用次数与最近活跃 |
| App 直连（实验） | v1.9：设备可申请短时直连凭证，图片类 AI 由 App 直连厂商、不经服务器；停用设备即撤销 |
| 操作日志 | 全部动作中文化，可按动作或关键词筛选 |
| 白底图 | 三种模式：手机本地 / 后台代跑 / 关闭。后台代跑只在内存转发，不落盘 |

服务器**只存**：账号、模型基础配置（含加密密钥）、系统设置、操作日志、设备凭据哈希。
**不存**：衣物照片、搭配、打卡记录等任何业务数据。

---

## 2. 部署（Ubuntu 22.04 / 24.04）

```bash
# 0) DNS：把 ai.slongb.xyz 的 A 记录指向服务器 IP，等生效
# 1) 解压到 /opt/wardrobe-admin（发布包是 zip）
sudo mkdir -p /opt/wardrobe-admin
sudo unzip -o wardrobe-admin-server-*.zip -d /tmp/wm-unpack
sudo cp -r /tmp/wm-unpack/wardrobe-admin/. /opt/wardrobe-admin/
cd /opt/wardrobe-admin

# 2) 生成密钥（务必保存好，换掉会导致已存密钥无法解密）
#    直接写进 /etc/wardrobe-admin.env：deploy.sh 发现它已存在就不会用模板覆盖
python3 -c "import secrets;print('WM_SECRET='+secrets.token_urlsafe(48))" | sudo tee /etc/wardrobe-admin.env
echo "WM_DEV_CODE=0" | sudo tee -a /etc/wardrobe-admin.env

# 3) 一键脚本：装依赖、建 systemd、配 Nginx
sudo bash deploy/deploy.sh

# 4) HTTPS
sudo certbot --nginx -d ai.slongb.xyz
```

打开 `https://ai.slongb.xyz`，**第一个注册的账号自动成为超级管理员**。

### 环境变量（`.env` → `/etc/wardrobe-admin.env`）

```ini
WM_SECRET=...                 # 必填，加密模型密钥用
WM_DB=/var/lib/wardrobe-admin/wardrobe.db
WM_PORT=8787
WM_DEV_CODE=0                 # 生产必须为 0
WM_SMTP_HOST=smtp.exmail.qq.com
WM_SMTP_PORT=465
WM_SMTP_USER=noreply@slongb.xyz
WM_SMTP_PASS=...
WM_SMTP_FROM=衣橱管家 <noreply@slongb.xyz>
WM_ALLOW_ORIGINS=https://ai.slongb.xyz
WM_BOOTSTRAP_TOKEN=           # 可选：首个管理员注册需带此令牌
```

> 不配 SMTP 时验证码会直接显示在页面上，只适合内测。上线前务必配置。
> 不配 `WM_DEV_CODE=0` 时同样会回显验证码。

---

## 3. 给模型填什么

只需要三样，其余留空即用默认值：

| 字段 | 例子 |
|---|---|
| 接口地址 Base URL | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| 模型 ID | `qwen-vl-max` |
| API Key | `sk-...`（加密保存，保存后只显示 `sk-ab****cd12`） |

常见组合（后台弹窗里有「快捷填充」）：

| 用途 | 阿里云百炼 | OpenAI | 智谱 |
|---|---|---|---|
| 视觉识别（拆衣） | `qwen-vl-max` | `gpt-4o` | `glm-4v-plus` |
| 文本分析 | `qwen-max` | `gpt-4o-mini` | `glm-4-plus` |
| 图像编辑（试穿） | `wanx2.1-imageedit` | `gpt-image-1` | `cogview-3-flash` |
| 白底商品图 | 同上 | `gpt-image-1` | 同上 |

保存后点「测试」确认连通，再设默认。模型卡片会显示最近一次成功耗时或失败原因。

Gemini 官方 API：Base URL 填 `https://generativelanguage.googleapis.com/v1beta`，
provider 填 `gemini`（或端点含 `generateContent`）。走服务器代理时后端会自动把
OpenAI 格式转成 `contents/parts`（图片转 base64 `inlineData`）、用 `x-goog-api-key`
头，并把响应转回 `choices` 格式，App 端零改动。

---

## 4. App 侧怎么接

App 里**没有任何配置项**。首次启动时：

1. `POST /api/app/device` 换取设备凭据（用户无感）
2. `GET /api/app/config` 拿到「哪些能力可用」
3. 之后所有 AI 请求走代理，模型和密钥都在服务器

| 接口 | 用途 |
|---|---|
| `POST /api/app/device` | 设备接入，返回凭据 + 服务状态 |
| `GET /api/app/config` | 能力开关（需设备凭据），v1.9 起含 `ai.direct` 直连开关 |
| `POST /api/app/credential` | v1.9：申请直连凭证（需设备凭据），返回五类默认模型直连参数与短时有效期 |
| `POST /api/app/ai/v1/chat/completions` | 文本 / 视觉统一代理（OpenAI 协议；Gemini 原生模型自动协议转换） |
| `POST /api/app/ai/v1/images/edits` | 图像编辑（试穿） |
| `POST /api/app/white-bg` | 白底图（仅 `white_bg_mode=server`） |

后台不可达或能力未开通时，App 只降级对应 AI 功能，记账主流程不受影响。

### App 直连（v1.9 · 实验）

- 管理员在「系统设置」开启「允许 App 直连」后，App 凭设备凭据调用
  `POST /api/app/credential` 换取一次直连凭证：五类用途的
  `{base_url, model, api_key, endpoint}`（含解密明文 Key）+ `expires_at`，
  写入手机安全存储；之后**图片类** AI 请求由 App 直连厂商，图片不再经服务器转发；
- 老版本 App 与文本/视觉代理链路完全不受影响；
- 撤销语义：停用设备（该设备连代理也一并拒绝）、关闭「允许 App 直连」
  （停发新凭证），或等凭证到期（默认 24 小时，可配 1-168）自动失效；
  服务器不维护吊销名单，已下发凭证在 TTL 内离线有效；
- 明文 Key 只出现在该接口的响应里，绝不写审计日志；审计只记设备、用途列表与 TTL。

### 白底图三种模式

- **手机本地**（默认）：本机抠图 + 白底合成，照片不出手机，适合浅色背景；
- **后台代跑**：单张图经服务器转发给模型，速度快，服务器只在内存处理、不落盘；
- **关闭**：App 里不显示白底图入口。

---

## 5. 权限矩阵

| 操作 | 只读 | 管理员 | 超级管理员 |
|---|---|---|---|
| 看概览 / 模型列表 | ✓ | ✓ | ✓ |
| 新增 / 修改 / 启停模型、测试连通 | | ✓ | ✓ |
| 删除模型 | | | ✓ |
| 设备管理 | | ✓ | ✓ |
| 用户与角色 | | | ✓ |
| 系统设置 | | | ✓ |
| 操作日志 | | 看 | 看 |

---

## 6. 运维

```bash
systemctl status wardrobe-admin
journalctl -u wardrobe-admin -f
# 备份：拷贝 /var/lib/wardrobe-admin/wardrobe.db（含加密密钥，需同时保存 WM_SECRET）
sqlite3 /var/lib/wardrobe-admin/wardrobe.db ".backup '/root/wm-$(date +%F).db'"
```

**换 WM_SECRET 会让已保存的模型密钥无法解密**，需重新填一次 Key。

---

## 7. 测试

```bash
python3 -m pytest tests -q      # 38 项：注册/验证码/权限/密钥加密/代理/设备/白底模式/限频/422 信封/直连凭证/Gemini 协议转换
```
