/* 衣橱管家管理后台 · 前端（无框架）
   设计原则：管理员只填四件事——接口地址、模型 ID、API Key、给它起个名。其余全部有默认值。 */
const S = {
  token: localStorage.getItem('wm_token') || '', user: null, tab: 'home',
  config: {}, models: [], kinds: [], ready: {}, devices: [], users: [], roles: [],
  logs: [], actions: [], settings: {}, summary: {}, modes: [], logFilter: '', logKw: ''
};
const $ = (s) => document.querySelector(s);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function api(path, opts = {}) {
  const headers = Object.assign({}, opts.headers || {});
  if (S.token) headers['Authorization'] = 'Bearer ' + S.token;
  if (opts.body && typeof opts.body !== 'string' && !(opts.body instanceof FormData)) {
    headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(opts.body);
  }
  let r;
  try { r = await fetch(path, Object.assign({}, opts, { headers })); }
  catch (_) { throw new Error('连不上服务器，请检查网络或服务是否运行'); }
  // 会话中途 token 过期：清凭证退回登录页（登录/注册等 auth 接口自身的 401 不算）
  if (r.status === 401 && S.token && !path.startsWith('/api/auth/')) {
    S.token = ''; S.user = null;
    localStorage.removeItem('wm_token');
    renderAuth();
  }
  let data = {};
  try { data = await r.json(); } catch (_) { data = {}; }
  if (!r.ok || data.ok === false) {
    const err = new Error(data.message || `请求失败（HTTP ${r.status}）`);
    err.status = r.status;
    throw err;
  }
  return data;
}

function toast(msg, err = false) {
  const el = document.createElement('div');
  el.className = 'toast' + (err ? ' err' : '');
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 3600);
}
const ts = (t) => t ? new Date(t * 1000).toLocaleString('zh-CN', { hour12: false }) : '—';
function ago(t) {
  if (!t) return '从未';
  const d = Math.floor(Date.now() / 1000 - t);
  if (d < 60) return '刚刚';
  if (d < 3600) return Math.floor(d / 60) + ' 分钟前';
  if (d < 86400) return Math.floor(d / 3600) + ' 小时前';
  return Math.floor(d / 86400) + ' 天前';
}
const badge = (ok, on, off) =>
  `<span class="badge ${ok ? 'on' : 'off'}">${ok ? on : off}</span>`;

/* ---------------- 登录 / 注册 ---------------- */
let authMode = 'login';
let codeLeft = 0, codeTimer = 0;

async function refreshConfig() {
  try { S.config = await api('/api/public/config'); } catch (_) { S.config = {}; }
}

function renderAuth() {
  const c = S.config, emailOn = c.email_verification !== false;
  const ttl = Math.round((c.code_ttl_seconds || 600) / 60);
  const needCode = (authMode === 'register' && emailOn) ||
                   (authMode === 'login' && c.login_code_required) || authMode === 'reset';
  $('#app').innerHTML = `
  <div class="auth-wrap"><div class="auth">
    <div class="brand"><div class="logo">衣</div><div>
      <h1>${esc(c.site_name || '衣橱管家 · 管理后台')}</h1>
      <p>统一管理 App 的 AI 模型与访问权限</p></div></div>
    <div class="tabs">
      <button class="${authMode === 'login' ? 'on' : ''}" onclick="setAuth('login')">登录</button>
      <button class="${authMode === 'register' ? 'on' : ''}" onclick="setAuth('register')">注册</button>
      ${authMode === 'reset' ? '<button class="on">找回密码</button>' : ''}
    </div>
    ${authMode === 'reset' ? `
      <div class="field"><label>注册邮箱</label><input id="f_email" type="email" placeholder="填写注册时用的邮箱"></div>
    ` : `
      <div class="field"><label>${authMode === 'register' ? '账号' : '账号 / 邮箱'}</label>
        <input id="f_user" autocomplete="username" placeholder="${authMode === 'register' ? '2-32 位，可用中文' : '输入账号或邮箱'}"></div>
      ${authMode === 'register' ? '<div class="field"><label>邮箱</label><input id="f_email" type="email" placeholder="用于接收验证码、找回密码"></div>' : ''}
    `}
    <div class="field"><label>密码</label>
      <input id="f_pwd" type="password" placeholder="至少 8 位，含字母和数字" autocomplete="${authMode === 'login' ? 'current-password' : 'new-password'}"></div>
    ${needCode ? `
      <div class="field"><label>邮箱验证码</label>
        <div class="row"><input id="f_code" placeholder="6 位数字" maxlength="6" inputmode="numeric">
        <button class="btn ghost small" id="btn_code" onclick="sendCode()">获取验证码</button></div>
        <div class="note">${ttl} 分钟内有效，60 秒内只能发一次</div></div>` : ''}
    <button class="btn full" onclick="submitAuth()">
      ${authMode === 'login' ? '登录' : authMode === 'register' ? '注册并进入' : '重置密码'}</button>
    <div class="note" id="email_state">
      ${emailOn
        ? '当前：邮箱验证已开启，注册需填验证码。'
        : '<span class="badge warn">邮箱验证已关闭</span> 注册不需要验证码，邮箱也不会验证。'}
      ${c.login_code_required ? '<br>登录同样需要验证码。' : ''}
    </div>
    <div class="auth-links">
      ${authMode === 'login'
        ? '<a onclick="setAuth(\'reset\')">忘记密码？</a>'
        : '<a onclick="setAuth(\'login\')">返回登录</a>'}
    </div>
    <div id="auth_msg"></div>
  </div></div>`;
}
function setAuth(m) {
  authMode = m;
  clearInterval(codeTimer); codeLeft = 0;
  renderAuth();
}

async function sendCode() {
  const target = (authMode === 'register' || authMode === 'reset')
    ? ($('#f_email')?.value || '').trim()
    : ($('#f_user')?.value || '').trim();
  if (!target) return toast(authMode === 'reset' ? '请先填邮箱' : '请先填账号或邮箱', true);
  const btn = $('#btn_code');
  btn.disabled = true;
  try {
    const r = await api('/api/auth/code', {
      method: 'POST',
      body: { target, purpose: authMode === 'reset' ? 'reset' : authMode }
    });
    const secs = r.resend_in || 60;
    $('#auth_msg').innerHTML =
      `<div class="alert ok">${esc(r.message)}，${Math.round(r.expires_in / 60)} 分钟内有效。` +
      `</div>${r.dev_code
        ? `<div class="dev-code">未配置邮件服务，本次验证码：<b>${esc(r.dev_code)}</b></div>` : ''}`;
    codeLeft = secs;
    btn.textContent = codeLeft + 's 后重发';
    clearInterval(codeTimer);
    codeTimer = setInterval(() => {
      codeLeft--;
      btn.textContent = codeLeft > 0 ? codeLeft + 's 后重发' : '获取验证码';
      if (codeLeft <= 0) { clearInterval(codeTimer); btn.disabled = false; }
    }, 1000);
  } catch (e) {
    btn.disabled = false;
    btn.textContent = '获取验证码';
    $('#auth_msg').innerHTML = `<div class="alert err">${esc(e.message)}</div>`;
  }
}

async function submitAuth() {
  const pwd = $('#f_pwd').value;
  const body = {
    password: pwd,
    code: $('#f_code') ? $('#f_code').value.trim() : ''
  };
  if (authMode === 'reset') {
    body.email = $('#f_email').value.trim();
    try {
      const r = await api('/api/auth/reset', { method: 'POST', body });
      toast(r.message);
      setAuth('login');
    } catch (e) { $('#auth_msg').innerHTML = `<div class="alert err">${esc(e.message)}</div>`; }
    return;
  }
  body.username = $('#f_user').value.trim();
  if (authMode === 'register') body.email = $('#f_email').value.trim();
  if (!body.username) return toast('请填写账号', true);
  if (!body.password) return toast('请填写密码', true);
  try {
    const r = await api('/api/auth/' + authMode, { method: 'POST', body });
    clearInterval(codeTimer);  // 登录成功进入主界面，停掉验证码倒计时，避免计时器空转
    S.token = r.token;
    localStorage.setItem('wm_token', r.token);
    S.user = r.user;
    S.tab = 'home';
    await loadAll();
    render();
    toast(r.message);
  } catch (e) { $('#auth_msg').innerHTML = `<div class="alert err">${esc(e.message)}</div>`; }
}

async function logout() {
  try { await api('/api/auth/logout', { method: 'POST' }); } catch (_) { }
  S.token = ''; S.user = null;
  localStorage.removeItem('wm_token');
  await refreshConfig();
  renderAuth();
}

/* ---------------- 数据加载 ---------------- */
async function loadAll() {
  // 先拿权限快照，再按权限决定请求哪些接口
  try {
    const me = await api('/api/auth/me');
    S.user = me.user;
    S.user.permissions = me.permissions;
  } catch (e) {
    if (e.status === 401) {  // token 已过期：清掉凭证，boot 会退回登录页
      S.token = ''; S.user = null;
      localStorage.removeItem('wm_token');
    }
  }
  const can = (S.user?.permissions) || {};
  await Promise.all([
    api('/api/admin/summary').then(r => S.summary = r).catch(() => { }),
    api('/api/admin/settings').then(r => {
      S.settings = r.settings; S.modes = r.white_bg_modes || [];
    }).catch(() => { }),
    api('/api/admin/models').then(r => {
      S.models = r.models; S.kinds = r.kinds; S.ready = r.ready || {};
    }).catch(() => { }),
    can.can_manage_users
      ? api('/api/admin/users').then(r => { S.users = r.users; S.roles = r.roles; }).catch(() => { })
      : Promise.resolve(),
    can.can_edit_models
      ? api('/api/admin/devices').then(r => S.devices = r.devices).catch(() => { })
      : Promise.resolve(),
    can.can_edit_models
      ? api('/api/admin/logs?limit=120').then(r => { S.logs = r.logs; S.actions = r.actions; }).catch(() => { })
      : Promise.resolve()
  ]);
}

/* ---------------- 外壳 ---------------- */
const NAV = [
  ['home', '概览'], ['models', 'AI 模型'], ['devices', 'App 设备'],
  ['users', '用户与权限'], ['logs', '操作日志'], ['settings', '系统设置']
];
const canEdit = () => !!(S.user?.permissions || {}).can_edit_models;
const canSuper = () => !!(S.user?.permissions || {}).can_manage_users;

function render() {
  if (!S.token || !S.user) return renderAuth();
  // 权限矩阵与后端/README 对齐：设备、日志管理员(级别2)可见；用户管理仅超管
  const nav = NAV.filter(([k]) =>
    (k !== 'users' && k !== 'logs' && k !== 'devices') ||
    (k === 'users' ? canSuper() : canEdit()));
  $('#app').innerHTML = `
  <div class="shell">
    <aside class="side">
      <div class="brand"><div class="logo">衣</div><div><h1>衣橱管家</h1><p>管理后台</p></div></div>
      <nav class="nav">${nav.map(([k, label]) =>
        `<button class="${S.tab === k ? 'on' : ''}" onclick="go('${k}')">${label}</button>`).join('')}</nav>
      <div class="foot">v1.9.0<br>账号、模型配置与日志仅存在这台服务器</div>
    </aside>
    <main class="main">
      <div class="top">
        <div><h2>${(nav.find(n => n[0] === S.tab) || [, ''])[1]}</h2>
          <div class="sub">${esc(S.config.site_name || '')} · ai.slongb.xyz</div></div>
        <div class="user-chip"><span>${esc(S.user.username)}</span>
          <span class="badge ${S.user.role === 'super_admin' ? 'on' : 'off'}">${esc(S.user.role_label)}</span>
          <button class="btn gray small" onclick="logout()">退出</button></div>
      </div>
      <div id="page"></div>
    </main>
  </div>`;
  renderPage();
}
function go(tab) { S.tab = tab; render(); }

function renderPage() {
  const el = $('#page');
  if (!el) return;
  if (S.tab === 'home') { el.innerHTML = homeHTML(); countUp(); }
  else if (S.tab === 'models') el.innerHTML = modelsHTML();
  else if (S.tab === 'devices') el.innerHTML = canEdit() ? devicesHTML() : noPerm('App 设备');
  else if (S.tab === 'users') el.innerHTML = canSuper() ? usersHTML() : noPerm('用户与权限');
  else if (S.tab === 'logs') el.innerHTML = canEdit() ? logsHTML() : noPerm('操作日志');
  else el.innerHTML = settingsHTML();
}
const noPerm = (what) => `<div class="panel"><div class="empty">你的账号是「${esc(S.user.role_label)}」，没有查看${what}的权限。<br>
  需要的话，请让超级管理员把你的角色改为「管理员」。</div></div>`;

/* 概览数字 count-up：一次性微动效；数值没变就不重播；跟随系统「减少动态效果」设置 */
let counted = {};
function countUp() {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  document.querySelectorAll('.card .v').forEach(v => {
    const first = v.firstChild;
    const target = parseInt(first?.textContent, 10);
    const key = v.closest('.card')?.querySelector('.k')?.textContent;
    if (!first || first.nodeType !== 3 || !(target > 0) || !key || counted[key] === target) return;
    counted[key] = target;
    const t0 = performance.now(), dur = 600;
    (function step(t) {
      const p = Math.min((t - t0) / dur, 1);
      first.textContent = Math.round(target * (1 - (1 - p) ** 3));
      if (p < 1) requestAnimationFrame(step);
    })(t0);
  });
}

/* ---------------- 概览 ---------------- */
function homeHTML() {
  const s = S.summary || {};
  const readyList = (S.kinds || []).map(k => {
    const ok = (s.ready || {})[k.key];
    return `<span class="pill ${ok ? 'ok' : 'bad'}">${ok ? '✓' : '✕'} ${esc(k.label.split(' · ')[0])}</span>`;
  }).join('');
  return `
  <div class="cards">
    <div class="card"><div class="k">App 设备</div><div class="v">${s.devices ?? 0}</div>
      <div class="d">7 天内活跃 ${s.devices_active ?? 0}</div></div>
    <div class="card"><div class="k">AI 模型</div><div class="v">${s.models_enabled ?? 0}<small> / ${s.models ?? 0} 启用</small></div>
      <div class="d">五类用途见下</div></div>
    <div class="card"><div class="k">后台账号</div><div class="v">${s.users ?? 0}</div>
      <div class="d">${s.email_verification ? '注册需邮箱验证' : '注册免验证码'}</div></div>
    <div class="card"><div class="k">操作记录</div><div class="v">${s.logs ?? 0}</div>
      <div class="d">${canEdit() ? `最近 ${S.logs.length} 条可查` : '管理员及以上可查看'}</div></div>
  </div>
  <div class="panel">
    <h3>AI 能力就绪状态</h3>
    <div class="note">App 里五个 AI 功能能否使用，取决于这里是否有「已启用 + 已填密钥」的模型。</div>
    <div class="pills">${readyList || '<span class="muted">暂无模型</span>'}</div>
    ${(!s.ready || !s.ready.vision || !s.ready.text) ? `<div class="alert warn" style="margin-top:12px">
      还有 AI 能力未配置，App 端对应功能会显示「管理员暂未开通」。建议至少配置「视觉识别」和「文本分析」各一个。
      <button class="btn small" style="margin-left:8px" onclick="go('models')">去配置</button></div>` : ''}
  </div>
  <div class="panel">
    <h3>服务状态</h3>
    <div class="switch-row"><div><div class="t">今日 AI 调用</div>
      <div class="d">App 端今天经后台代理完成的模型请求数（代理流量，直连调用不在此列）</div></div>
      <b>${s.ai_calls_today ?? 0} 次</b></div>
    <div class="switch-row"><div><div class="t">今日下发直连凭证</div>
      <div class="d">App 今天申请直连凭证的次数；开启直连后图片类 AI 直接发往厂商、不经服务器</div></div>
      <b>${s.credentials_today ?? 0} 次</b></div>
    <div class="switch-row"><div><div class="t">App AI 服务</div>
      <div class="d">关闭后 App 所有 AI 功能停用，不影响手工记账</div></div>
      ${badge(!!s.ai_service_enabled, '开放', '已关闭')}</div>
    <div class="switch-row"><div><div class="t">白底图模式</div>
      <div class="d">${esc(s.white_bg_mode_label || '—')}</div></div>
      <span class="badge ${s.white_bg_mode === 'off' ? 'off' : 'on'}">${s.white_bg_mode === 'off' ? '关闭' : s.white_bg_mode === 'server' ? '后台代跑' : '手机本地'}</span></div>
    <div class="switch-row"><div><div class="t">邮件验证码</div>
      <div class="d">${s.smtp_configured ? '已配置 SMTP，验证码发到邮箱' : '未配置 SMTP，验证码会直接显示在页面上（仅适合内测）'}</div></div>
      <span class="badge ${s.smtp_configured ? 'on' : 'warn'}">${s.smtp_configured ? '正常' : '未配置'}</span></div>
  </div>
  <div class="panel"><div class="head"><h3>最近操作</h3>
    ${canEdit() ? '<button class="btn gray small" onclick="go(\'logs\')">查看全部</button>' : ''}</div>
    ${canEdit() ? logTable(S.logs.slice(0, 8)) : '<div class="empty">管理员及以上可查看操作日志</div>'}</div>`;
}

/* ---------------- AI 模型 ---------------- */
const TEMPLATES = [
  { id: '', name: '选择常用厂商自动填地址（可选）' },
  { id: 'ark', name: '豆包 · 火山方舟（推荐）', base: 'https://ark.cn-beijing.volces.com/api/v3',
    model: 'doubao-seed-1-6-vision-250815', text: 'doubao-seed-1-6-flash-250715',
    edit: 'doubao-seededit-3-0-i2i-250628', avatar: 'doubao-seededit-3-0-i2i-250628',
    white_bg: 'doubao-seedream-4-0-250828', edit_ep: '/images/generations' },
  { id: 'openai', name: 'OpenAI', base: 'https://api.openai.com/v1', model: 'gpt-4o', edit: 'gpt-image-1' },
  { id: 'dashscope', name: '阿里云百炼（兼容模式）', base: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-vl-max', edit: 'wanx2.1-imageedit' },
  { id: 'zhipu', name: '智谱 GLM', base: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4v-plus', edit: 'cogview-3-flash' },
  { id: 'siliconflow', name: '硅基流动', base: 'https://api.siliconflow.cn/v1', model: 'Qwen/Qwen2.5-VL-72B-Instruct', edit: '' },
  { id: 'deepseek', name: 'DeepSeek（无视觉）', base: 'https://api.deepseek.com/v1', model: 'deepseek-chat', edit: '' },
  { id: 'custom', name: '自定义 / 自建网关', base: '', model: '', edit: '' }
];

function modelsHTML() {
  const groups = (S.kinds || []).map(k => {
    const list = S.models.filter(m => m.kind === k.key);
    const ok = S.ready[k.key];
    return `<div class="kind-block">
      <div class="kind-head">
        <div><h4>${esc(k.label)} ${badge(!!ok, '就绪', '未就绪')}</h4>
          <div class="note">${esc(k.hint)}</div></div>
        ${canEdit() ? `<button class="btn small" onclick="openModel(null,'${k.key}')">+ 添加</button>` : ''}
      </div>
      ${list.length ? `<div class="model-grid">${list.map(modelCard).join('')}</div>`
        : `<div class="empty small">还没有配置${esc(k.label)}模型${canEdit() ? '，点右上角添加' : ''}</div>`}
    </div>`;
  }).join('');
  return `<div class="panel">
    <h3>模型配置</h3>
    <div class="note">API Key 加密保存在这台服务器，管理页只显示掩码，App 里也看不到、改不了。
      代理模式下明文 Key 不下发；开启「允许 App 直连」后，会按设备下发<b>短时直连凭证</b>
      （有效期见系统设置），停用设备或关闭开关即可撤销。
      你只需要填接口地址、模型 ID 和 Key，其余用默认值即可。</div>
    ${groups}
  </div>`;
}

function modelCard(m) {
  const health = m.last_error
    ? `<div class="health bad" title="${esc(m.last_error)}">最近失败：${esc(m.last_error.slice(0, 46))}</div>`
    : m.last_ok_at
      ? `<div class="health ok">最近正常 · ${m.last_ok_ms || 0} ms · ${ago(m.last_ok_at)}</div>`
      : `<div class="health muted">还没测试过连接</div>`;
  return `<div class="model-card ${m.enabled ? '' : 'off'}">
    <div class="mc-top"><b>${esc(m.name)}</b>
      ${m.is_default ? '<span class="badge on">默认</span>' : ''}
      ${m.enabled ? '' : '<span class="badge off">已停用</span>'}</div>
    <div class="mono small">${esc(m.model || '未填模型 ID')}</div>
    <div class="mono tiny">${esc(m.base_url || '')}</div>
    <div class="mc-key">密钥：${m.api_key_set ? `<span class="ok-text">${esc(m.api_key_hint)}</span>` : '<span class="bad-text">未填写</span>'}</div>
    ${health}
    <div class="ops">
      ${canEdit() ? `<button class="btn gray small" onclick="openModel(${m.id})">编辑</button>
      <button class="btn ghost small" onclick="testModel(${m.id}, this)">测试</button>
      <button class="btn ghost small" onclick="toggleModel(${m.id})">${m.enabled ? '停用' : '启用'}</button>
      ${m.enabled && !m.is_default ? `<button class="btn ghost small" onclick="setDefault(${m.id})">设默认</button>` : ''}` : ''}
      ${canSuper() ? `<button class="btn ghost small danger" onclick="delModel(${m.id})">删除</button>` : ''}
    </div>
  </div>`;
}

let modalEsc = null;  // 当前弹窗的 Esc 监听（单例，防止累积泄漏）
function openModel(id, presetKind) {
  const m = id ? S.models.find(x => x.id === id) : null;
  const kind = m?.kind || presetKind || 'vision';
  const d = m || { kind, timeout_seconds: 90, temperature: 0.3, enabled: true, is_default: false,
    supports_image_input: kind !== 'text',
    supports_image_edit: ['edit', 'white_bg', 'avatar'].includes(kind) };
  const bg = document.createElement('div');
  bg.className = 'modal-bg';
  bg.innerHTML = `<div class="modal">
    <h3>${id ? '编辑模型' : '添加模型'}</h3>
    <div class="form-grid">
      <div class="field wide"><label>快捷选择厂商（自动填，可选）</label>
        <select id="m_tpl" onchange="applyTpl(this.value)">
          ${TEMPLATES.map(t => `<option value="${t.id}">${t.name}</option>`).join('')}</select>
        <div class="note">选好厂商会自动填接口地址、模型 ID 和端点路径；也可以完全手填。</div></div>
      <div class="field"><label>用途</label>
        <select id="m_kind" onchange="if($('#m_tpl') && $('#m_tpl').value) applyTpl($('#m_tpl').value)">${S.kinds.map(k =>
          `<option value="${k.key}" ${kind === k.key ? 'selected' : ''}>${k.label}</option>`).join('')}</select></div>
      <div class="field"><label>给它起个名字</label>
        <input id="m_name" value="${esc(m?.name || '')}" placeholder="如 通义千问 · 拆衣"></div>
      <div class="field wide"><label>接口地址 Base URL</label>
        <input id="m_base" value="${esc(m?.base_url || '')}" placeholder="https://api.openai.com/v1">
        <div class="note">就是模型厂商文档里的 base_url，通常以 /v1 结尾。</div></div>
      <div class="field wide"><label>模型 ID</label>
        <input id="m_model" value="${esc(m?.model || '')}" placeholder="如 gpt-4o / qwen-vl-max">
        <div class="note">填厂商文档里的模型名，不是显示名。</div></div>
      <div class="field wide"><label>API Key</label>
        <input id="m_key" type="password" autocomplete="new-password"
          placeholder="${m?.api_key_set ? '已保存 ' + esc(m.api_key_hint) + '，留空表示不修改' : '粘贴密钥，保存后会加密'}">
        ${m?.api_key_set ? '<label class="tiny-check"><input type="checkbox" id="m_clearkey"> 清空已保存的密钥</label>' : ''}
        <div class="note">只存在服务器，App 端拿不到。建议用只开了这个模型的子账号 Key。</div></div>
    </div>
    <details class="adv"><summary>高级设置（一般不用改）</summary>
      <div class="form-grid">
        <div class="field"><label>端点路径</label>
          <input id="m_endpoint" value="${esc(m?.endpoint || '')}" placeholder="留空用默认 /chat/completions"></div>
        <div class="field"><label>超时（秒）</label>
          <input id="m_timeout" type="number" min="5" max="600" value="${d.timeout_seconds}"></div>
        <div class="field"><label>temperature</label>
          <input id="m_temp" type="number" step="0.1" min="0" max="2" value="${d.temperature}"></div>
        <div class="field"><label>备注</label><input id="m_note" value="${esc(m?.note || '')}"></div>
      </div>
    </details>
    <div class="row between" style="margin-top:14px">
      <label class="tiny-check"><input type="checkbox" id="m_enabled" ${d.enabled ? 'checked' : ''}> 启用</label>
      <label class="tiny-check"><input type="checkbox" id="m_default" ${d.is_default ? 'checked' : ''}> 设为这类用途的默认</label>
    </div>
    <div class="row end" style="margin-top:14px">
      <button class="btn gray" onclick="this.closest('.modal-bg').remove()">取消</button>
      <button class="btn" id="m_save">保存</button>
      ${id ? '<button class="btn ghost" id="m_test">保存并测试连接</button>' : ''}
    </div>
    <div id="m_msg"></div>
  </div>`;
  document.body.appendChild(bg);
  bg.addEventListener('click', (e) => { if (e.target === bg) bg.remove(); });  // 点遮罩关闭
  if (modalEsc) document.removeEventListener('keydown', modalEsc);  // 单例：清掉上一个弹窗残留的 Esc 监听
  modalEsc = (e) => {
    if (e.key !== 'Escape') return;
    bg.remove();
    document.removeEventListener('keydown', modalEsc);
    modalEsc = null;
  };
  document.addEventListener('keydown', modalEsc);
  $('#m_name')?.focus();
  const collect = () => ({
    name: $('#m_name').value.trim(), kind: $('#m_kind').value,
    base_url: $('#m_base').value.trim(), model: $('#m_model').value.trim(),
    api_key: $('#m_key').value.trim(),
    clear_key: $('#m_clearkey') ? $('#m_clearkey').checked : false,
    endpoint: $('#m_endpoint').value.trim(),
    timeout_seconds: +$('#m_timeout').value || 90,
    temperature: +$('#m_temp').value || 0,
    enabled: $('#m_enabled').checked, is_default: $('#m_default').checked,
    note: $('#m_note').value.trim(),
    supports_image_input: ['vision', 'edit', 'white_bg', 'avatar'].includes($('#m_kind').value),
    supports_image_edit: ['edit', 'white_bg', 'avatar'].includes($('#m_kind').value)
  });
  const save = async (thenTest) => {
    const body = collect();
    if (!body.name) return msg('请给这个模型起个名字');
    if (!body.base_url) return msg('请填接口地址');
    if (!body.model) return msg('请填模型 ID');
    const btn = $('#m_save'); btn.disabled = true; btn.textContent = '保存中…';
    try {
      const r = await api('/api/admin/models' + (id ? '/' + id : ''),
        { method: id ? 'PUT' : 'POST', body });
      const mid = r.model.id;
      toast(r.message);
      await loadAll();
      if (thenTest) {
        btn.textContent = '测试中…';
        try {
          const t = await api(`/api/admin/models/${mid}/test`, { method: 'POST' });
          toast(t.message);
        } catch (e) { toast('测试失败：' + e.message, true); }
      }
      bg.remove();
      renderPage();
    } catch (e) {
      btn.disabled = false; btn.textContent = '保存';
      msg(e.message);
    }
  };
  const msg = (t) => { $('#m_msg').innerHTML = `<div class="alert err">${esc(t)}</div>`; };
  $('#m_save').onclick = () => save(false);
  if ($('#m_test')) $('#m_test').onclick = () => save(true);
}

function applyTpl(tid) {
  const t = TEMPLATES.find(x => x.id === tid);
  if (!t || !t.base) return;
  $('#m_base').value = t.base;
  const kind = $('#m_kind').value;
  const mid = { vision: t.model, text: t.text || t.model, edit: t.edit,
    avatar: t.avatar || t.edit, white_bg: t.white_bg || t.edit }[kind] || t.model;
  if (mid) $('#m_model').value = mid;
  const ep = ['edit', 'avatar', 'white_bg'].includes(kind) ? t.edit_ep : '';
  if (ep) $('#m_endpoint').value = ep;
  if (!$('#m_name').value) $('#m_name').value = t.name;
}

async function testModel(id, btn) {
  if (btn) { btn.disabled = true; btn.textContent = '测试中…'; }
  try {
    const r = await api(`/api/admin/models/${id}/test`, { method: 'POST' });
    toast(r.message);
  } catch (e) { toast(e.message, true); }
  await loadAll(); renderPage();
}
async function toggleModel(id) {
  try { const r = await api(`/api/admin/models/${id}/toggle`, { method: 'POST' }); toast(r.message); }
  catch (e) { toast(e.message, true); }
  await loadAll(); renderPage();
}
async function setDefault(id) {
  try { const r = await api(`/api/admin/models/${id}/default`, { method: 'POST' }); toast(r.message); }
  catch (e) { toast(e.message, true); }
  await loadAll(); renderPage();
}
async function delModel(id) {
  const m = S.models.find(x => x.id === id);
  if (!confirm(`删除「${m?.name || ''}」？App 端会立刻改用同类其它模型。`)) return;
  try { const r = await api(`/api/admin/models/${id}`, { method: 'DELETE' }); toast(r.message); }
  catch (e) { toast(e.message, true); }
  await loadAll(); renderPage();
}

/* ---------------- 设备 ---------------- */
function devicesHTML() {
  if (!S.devices.length) {
    return `<div class="panel"><h3>App 设备</h3>
      <div class="empty">还没有设备接入。<br>用户打开 App 会自动连上这里，不需要注册账号。</div></div>`;
  }
  return `<div class="panel"><h3>App 设备（${S.devices.length}）</h3>
    <div class="note">App 用户无需账号，每台设备自动获取一个凭据。停用后该设备无法再调用 AI，但本地衣物数据不受影响。</div>
    <div class="table-wrap" role="region" aria-label="App 设备表" tabindex="0">
    <table><thead><tr><th>设备</th><th>平台</th><th>版本</th><th>调用次数</th>
      <th>最近活跃</th><th>状态</th><th>操作</th></tr></thead><tbody>
      ${S.devices.map(d => `<tr>
        <td><b>${esc(d.name || '未命名设备')}</b><div class="muted mono tiny">${esc(d.device_id.slice(0, 16))}…</div></td>
        <td>${esc(d.platform || '—')}</td><td>${esc(d.app_version || '—')}</td>
        <td>${d.call_count}</td><td class="muted">${ago(d.last_seen_at)}</td>
        <td>${badge(d.enabled, '正常', '停用')}</td>
        <td><div class="ops">
          <button class="btn ghost small" onclick="toggleDevice(${d.id})">${d.enabled ? '停用' : '启用'}</button>
          ${canSuper() ? `<button class="btn ghost small danger" onclick="delDevice(${d.id})">移除</button>` : ''}
        </div></td></tr>`).join('')}
    </tbody></table></div></div>`;
}
async function toggleDevice(id) {
  try { const r = await api(`/api/admin/devices/${id}/toggle`, { method: 'POST' }); toast(r.message); }
  catch (e) { toast(e.message, true); }
  await loadAll(); renderPage();
}
async function delDevice(id) {
  if (!confirm('移除后这台设备需要重新打开 App 才能接入，确定？')) return;
  try { const r = await api(`/api/admin/devices/${id}`, { method: 'DELETE' }); toast(r.message); }
  catch (e) { toast(e.message, true); }
  await loadAll(); renderPage();
}

/* ---------------- 用户 ---------------- */
function usersHTML() {
  if (!S.users.length) {
    return `<div class="panel"><h3>用户与权限</h3>
      <div class="empty">暂无后台账号记录。</div></div>`;
  }
  return `<div class="panel"><h3>用户与权限</h3>
    <div class="note">第一个注册的账号自动是超级管理员。之后注册的都是「只读」，需要你手动提升。</div>
    <div class="table-wrap" role="region" aria-label="用户权限表" tabindex="0">
    <table><thead><tr><th>账号</th><th>邮箱</th><th>角色</th><th>状态</th>
      <th>最近登录</th><th>操作</th></tr></thead><tbody>
    ${S.users.map(u => `<tr>
      <td><b>${esc(u.username)}</b>${u.id === S.user.id ? ' <span class="badge">我</span>' : ''}</td>
      <td class="mono">${esc(u.email)}</td>
      <td>${esc(u.role_label)}</td>
      <td>${badge(u.enabled, '正常', '停用')}</td>
      <td class="muted">${ago(u.last_login_at)}</td>
      <td><div class="ops">
        <select onchange="setRole(${u.id}, this.value)" ${u.id === S.user.id ? 'disabled' : ''}>
          ${S.roles.map(r => `<option value="${r.key}" ${u.role === r.key ? 'selected' : ''}>${r.label}</option>`).join('')}
        </select>
        <button class="btn ghost small" ${u.id === S.user.id ? 'disabled' : ''}
          onclick="toggleUser(${u.id}, ${u.enabled})">${u.enabled ? '停用' : '启用'}</button>
      </div></td></tr>`).join('')}
    </tbody></table></div></div>`;
}
async function setRole(id, role) {
  try { await api(`/api/admin/users/${id}`, { method: 'PATCH', body: { role } }); toast('角色已更新'); }
  catch (e) { toast(e.message, true); }
  await loadAll(); renderPage();
}
async function toggleUser(id, enabled) {
  try { await api(`/api/admin/users/${id}`, { method: 'PATCH', body: { enabled: !enabled } }); toast('已更新'); }
  catch (e) { toast(e.message, true); }
  await loadAll(); renderPage();
}

/* ---------------- 日志 ---------------- */
function logTable(rows) {
  if (!rows?.length) return '<div class="empty small">暂无记录</div>';
  return `<div class="table-wrap" role="region" aria-label="操作日志表" tabindex="0">
    <table><thead><tr><th>时间</th><th>操作人</th><th>动作</th><th>对象</th><th>详情</th></tr></thead><tbody>
    ${rows.map(l => `<tr><td class="muted nowrap">${ts(l.created_at)}</td>
      <td>${esc(l.actor_name)}</td><td>${esc(l.action_label || l.action)}</td>
      <td>${esc(l.target)}</td><td class="muted">${esc(l.detail)}</td></tr>`).join('')}
    </tbody></table></div>`;
}
function logsHTML() {
  return `<div class="panel"><div class="head"><h3>操作日志</h3>
    <div class="row">
      <select onchange="S.logFilter=this.value; loadLogs()">
        <option value="">全部动作</option>
        ${S.actions.map(a => `<option value="${a.key}" ${S.logFilter === a.key ? 'selected' : ''}>${a.label}</option>`).join('')}
      </select>
      <input id="log_kw" placeholder="搜对象/详情/人" style="width:180px" value="${esc(S.logKw || '')}"
        onkeydown="if(event.key==='Enter'&&!event.isComposing&&event.keyCode!==229) loadLogs()">
      <button class="btn gray small" onclick="loadLogs()">查询</button>
    </div></div>
    ${logTable(S.logs)}</div>`;
}
let logSeq = 0;
async function loadLogs() {
  S.logKw = $('#log_kw')?.value.trim() || '';
  const seq = ++logSeq;  // 请求序号：乱序返回时丢弃旧响应，避免旧结果覆盖新查询
  try {
    const r = await api(`/api/admin/logs?limit=200&action=${encodeURIComponent(S.logFilter)}&keyword=${encodeURIComponent(S.logKw)}`);
    if (seq !== logSeq) return;
    S.logs = r.logs; S.actions = r.actions;
    renderPage();
  } catch (e) { toast(e.message, true); }
}

/* ---------------- 设置 ---------------- */
const SWITCHES = [
  ['ai_service_enabled', 'App AI 服务总开关', '关闭后 App 内所有 AI 功能停用，手工记录不受影响'],
  ['direct_ai_enabled', '允许 App 直连（实验）', '开启后 App 可申请短时直连凭证，图片类 AI 请求直接发往厂商、不经服务器；停用设备或关闭本开关即可撤销'],
  ['device_auto_register', '允许新设备自动接入', '关闭后只有你手动添加的设备能用，适合只给自己用'],
  ['email_verification', '注册需要邮箱验证码', '关闭后注册不需要验证码，也无法自助找回密码'],
  ['login_code_required', '登录也要验证码', '更安全，但每次登录都要收邮件']
];
function settingsHTML() {
  const v = S.settings;
  return `<div class="panel"><h3>开关</h3>
    ${SWITCHES.map(([k, t, d]) => `<div class="switch-row"><div>
      <div class="t">${t} ${badge(v[k] === '1', '开启', '关闭')}</div><div class="d">${d}</div></div>
      <button class="switch ${v[k] === '1' ? 'on' : ''}" ${canSuper() ? '' : 'disabled'}
        onclick="saveSetting('${k}', '${v[k] === '1' ? '0' : '1'}')"></button></div>`).join('')}
  </div>
  <div class="panel"><h3>App 直连凭证（实验）</h3>
    <div class="field"><label>凭证有效期（小时）</label>
      <div class="row">
        <input id="set_credential_ttl_hours" type="number" min="1" max="168"
          value="${esc(v.credential_ttl_hours || '24')}" ${canSuper() ? '' : 'disabled'}>
        <button class="btn ghost small" ${canSuper() ? '' : 'disabled'}
          onclick="saveSetting('credential_ttl_hours', document.getElementById('set_credential_ttl_hours').value)">保存</button></div>
      <div class="note">App 申请直连凭证后按此时限有效（1-168 小时，默认 24），到期自动失效需重新申请。
        要立即撤销某台设备，去「App 设备」停用它即可（停用后连代理也用不了）。</div></div>
  </div>
  <div class="panel"><h3>白底图生成方式</h3>
    <div class="note">「手机本地」照片不出手机；「后台代跑」把单张图传到这台服务器转发给模型，速度更快，服务器不保存图片。</div>
    ${S.modes.map(m => `<label class="radio-row">
      <input type="radio" name="wbmode" value="${m.key}" ${v.white_bg_mode === m.key ? 'checked' : ''}
        ${canSuper() ? '' : 'disabled'} onchange="saveSetting('white_bg_mode','${m.key}')">
      <div><div class="t">${esc(m.label)}</div></div></label>`).join('')}
    ${v.white_bg_mode === 'server' ? `<div class="alert warn">已开启后台代跑：请确认「白底商品图」这类模型已配置并测试通过，否则 App 端会回退到本地处理。</div>` : ''}
  </div>
  <div class="panel"><h3>验证码与限流</h3><div class="grid2">
    ${[['code_ttl_seconds', '验证码有效期（秒）'], ['code_resend_seconds', '重发间隔（秒）'],
       ['code_max_per_hour', '每小时最多发送'], ['device_rate_limit', '每台设备每分钟 AI 次数']]
      .map(([k, t]) => `<div class="field"><label>${t}</label><div class="row">
        <input id="set_${k}" type="number" value="${esc(v[k] || '')}" ${canSuper() ? '' : 'disabled'}>
        <button class="btn ghost small" ${canSuper() ? '' : 'disabled'}
          onclick="saveSetting('${k}', document.getElementById('set_${k}').value)">保存</button></div></div>`).join('')}
  </div></div>
  <div class="panel"><h3>App 提示语</h3>
    <div class="field"><label>显示在 App 里的公告（可留空）</label>
      <div class="row"><input id="set_app_notice" value="${esc(v.app_notice || '')}"
        placeholder="如：AI 服务维护中，预计今晚恢复" style="flex:1" ${canSuper() ? '' : 'disabled'}>
      <button class="btn ghost small" ${canSuper() ? '' : 'disabled'}
        onclick="saveSetting('app_notice', document.getElementById('set_app_notice').value)">保存</button></div></div>
    <div class="field"><label>站点名称</label>
      <div class="row"><input id="set_site_name" value="${esc(v.site_name || '')}" style="flex:1" ${canSuper() ? '' : 'disabled'}>
      <button class="btn ghost small" ${canSuper() ? '' : 'disabled'}
        onclick="saveSetting('site_name', document.getElementById('set_site_name').value)">保存</button></div></div>
    ${canSuper() ? '' : '<div class="note">当前账号没有修改设置的权限，需要超级管理员。</div>'}
  </div>
  <div class="panel"><h3>接口说明（给二次开发用）</h3><div class="note mono">
    POST /api/app/device — App 首次接入，返回设备凭据<br>
    GET&nbsp; /api/app/config — App 拉取「哪些 AI 能力可用」<br>
    POST /api/app/credential — v1.9：申请直连凭证（需设备凭据）<br>
    POST /api/app/ai/v1/chat/completions — 文本/视觉统一代理<br>
    POST /api/app/ai/v1/images/edits — 图像编辑（试穿）<br>
    POST /api/app/white-bg — 白底图（需开启后台代跑）
  </div></div>`;
}
async function saveSetting(key, value) {
  try {
    await api('/api/admin/settings', { method: 'PUT', body: { key, value: String(value) } });
    toast('已保存');
    await Promise.all([loadAll(), refreshConfig()]);
    renderPage();
  } catch (e) { toast(e.message, true); }
}

/* ---------------- 启动 ---------------- */
// 请求期间全局锁：内联 onclick 调用的写操作统一防双击/连点重复提交
const lock = (fn) => async (...a) => {
  if (S._busy) return;
  S._busy = true;
  try { await fn(...a); } finally { S._busy = false; }
};
[sendCode, submitAuth, testModel, toggleModel, setDefault, delModel,
  toggleDevice, delDevice, setRole, toggleUser, loadLogs, saveSetting]
  .forEach(fn => { window[fn.name] = lock(fn); });

// 登录/注册/找回表单内回车即提交（IME-safe：输入法选词的回车不触发）
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter' || e.isComposing || e.keyCode === 229) return;
  const t = e.target;
  if (t && t.tagName === 'INPUT' && t.id !== 'log_kw' && t.closest('.auth')) submitAuth();
});

(async function boot() {
  await refreshConfig();
  if (!S.token) return renderAuth();
  $('#app').innerHTML = '<div class="auth-wrap"><div class="loading">正在进入管理后台…</div></div>';
  try {
    await loadAll();
    if (!S.user) throw new Error('unauthorized');
    render();
  } catch (_) {
    S.token = ''; localStorage.removeItem('wm_token');
    renderAuth();
  }
})();
