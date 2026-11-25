#!/usr/bin/env bash
# 在服务器上执行：sudo bash deploy.sh
set -euo pipefail

APP_DIR=/opt/wardrobe-admin
DATA_DIR=/var/lib/wardrobe-admin
ENV_FILE=/etc/wardrobe-admin.env

echo "==> 1/6 安装系统依赖"
apt-get update -y
apt-get install -y python3 python3-venv python3-pip nginx certbot python3-certbot-nginx

echo "==> 2/6 部署代码与目录"
mkdir -p "$APP_DIR" "$DATA_DIR"
cp -r core.py api_auth.py api_admin.py api_app.py api_public.py server.py static requirements.txt "$APP_DIR"/
[ -f "$ENV_FILE" ] || cp .env.example "$ENV_FILE"
chown -R www-data:www-data "$DATA_DIR"
chmod 750 "$DATA_DIR"
python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"

echo "==> 3/6 注册 systemd 服务"
cp deploy/wardrobe-admin.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now wardrobe-admin

echo "==> 4/6 配置 Nginx"
cp deploy/nginx.conf /etc/nginx/sites-available/ai.slongb.xyz
ln -sf /etc/nginx/sites-available/ai.slongb.xyz /etc/nginx/sites-enabled/
# 证书未申请前先临时禁用 443 段，避免 nginx -t 失败
if [ ! -f /etc/letsencrypt/live/ai.slongb.xyz/fullchain.pem ]; then
  echo "!! 请先执行：certbot --nginx -d ai.slongb.xyz，然后把本脚本再跑一次"
  nginx -t 2>/dev/null || true
else
  nginx -t && systemctl reload nginx
fi

echo "==> 5/6 检查服务"
sleep 2
curl -fsS http://127.0.0.1:8787/healthz || { journalctl -u wardrobe-admin -n 30; exit 1; }

echo "==> 6/6 完成"
echo "后台地址：https://ai.slongb.xyz"
echo "请检查 $ENV_FILE：WM_SECRET 必须改成随机长串，WM_DEV_CODE 必须设为 0"
echo "SMTP 未配置时验证码会回显在页面（开发模式），生产请配置 WM_SMTP_* 或关闭邮箱验证"
