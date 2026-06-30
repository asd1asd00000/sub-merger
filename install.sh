#!/bin/bash
# نصاب تعاملی و هوشمند پورتال تجمیع سابسکریپشن

# تعریف رنگ‌های گرافیکی برای ترمینال
C_DEF='\033[0m'          # حذف رنگ
C_GREEN='\033[1;32m'     # سبز درخشان
C_CYAN='\033[1;36m'      # فیروزه‌ای
C_YELLOW='\033[1;33m'    # زرد
C_BOX='\033[38;5;63m'    # آبی-بنفش (برای حاشیه جدول)

echo -e "${C_CYAN}=================================================${C_DEF}"
echo -e "  🚀 ${C_GREEN}SVM-Panel Installer - Pro Edition${C_DEF} 🚀  "
echo -e "${C_CYAN}=================================================${C_DEF}"

# ۱. دریافت اطلاعات از کاربر با مقادیر پیش‌فرض
read -p "👤 Enter Admin Username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

DEFAULT_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
read -p "🔑 Enter Admin Password [$DEFAULT_PASS]: " ADMIN_PASS
ADMIN_PASS=${ADMIN_PASS:-$DEFAULT_PASS}

echo "-------------------------------------------------"
echo "⚠️ نکته: اگر می‌خواهید SSL نصب شود، ساب‌دامنه شما باید الان به IP این سرور متصل باشد."
read -p "🌐 Enter Subdomain (e.g., sub.domain.com) [Leave blank for IP only]: " DOMAIN
echo "================================================="

# ۲. نصب پیش‌نیازها
echo -e "📥 ${C_CYAN}در حال نصب پکیج‌های لینوکس...${C_DEF}"
apt update && apt install zip git wget curl jq nginx certbot python3-certbot-nginx -y

# ۳. نصب داینامیک زبان Go
export PATH=$PATH:/usr/local/go/bin
if ! command -v go &> /dev/null; then
    echo -e "📥 ${C_CYAN}در حال دانلود آخرین نسخه Go...${C_DEF}"
    LATEST_GO=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
    wget https://go.dev/dl/${LATEST_GO}.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf ${LATEST_GO}.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    rm ${LATEST_GO}.linux-amd64.tar.gz
fi

# ۴. ساخت پوشه تنظیمات و ایجاد فایل Credentials
echo -e "⚙️  ${C_CYAN}در حال تنظیم دیتابیس و رمزهای عبور...${C_DEF}"
mkdir -p /etc/merge_subs
cat <<EOF > /etc/merge_subs/settings.json
{
  "admin_username": "$ADMIN_USER",
  "admin_password": "$ADMIN_PASS",
  "token": "",
  "chat_id": "",
  "password": "",
  "tutorials_url": "",
  "announcements_url": ""
}
EOF

# ۵. کامپایل پروژه گولنگ
echo -e "⚙️  ${C_CYAN}در حال بیلد کردن هسته پنل...${C_DEF}"
go mod tidy
go build -o /usr/local/bin/sub-merger-app cmd/server/main.go
chmod +x /usr/local/bin/sub-merger-app

# ۶. ساخت سرویس لینوکس
echo -e "🛠️  ${C_CYAN}راه‌اندازی سرویس Systemd...${C_DEF}"
cat <<EOF > /etc/systemd/system/sub-merger.service
[Unit]
Description=SVM Subscription Merger Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
ExecStart=/usr/local/bin/sub-merger-app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sub-merger.service
systemctl restart sub-merger.service

# ۷. پیکربندی وب‌سرور (Nginx) و SSL در صورت وارد کردن دامنه
FINAL_URL="http://$(curl -s ifconfig.me):5000/admin"

if [ ! -z "$DOMAIN" ]; then
    echo -e "🌍 ${C_CYAN}در حال تنظیمات Nginx و دریافت گواهینامه SSL برای $DOMAIN ...${C_DEF}"
    
    rm -f /etc/nginx/sites-enabled/default

    cat <<EOF > /etc/nginx/sites-available/sub-merger
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    ln -s /etc/nginx/sites-available/sub-merger /etc/nginx/sites-enabled/
    systemctl restart nginx

    certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN --redirect

    FINAL_URL="https://$DOMAIN/admin"
else
    ufw allow 5000/tcp > /dev/null 2>&1
fi

# ==========================================
# ۸. چاپ جدول گرافیکی و رنگی اطلاعات پایانی
# ==========================================
echo -e ""
echo -e "${C_BOX}╭──────────────────────────────────────────────────────────────────╮${C_DEF}"
echo -e "${C_BOX}│${C_DEF}  ${C_GREEN}✅ نصب پنل SVM با موفقیت به پایان رسید!${C_DEF}                       ${C_BOX}│${C_DEF}"
echo -e "${C_BOX}├──────────────────────────────────────────────────────────────────┤${C_DEF}"
echo -e "${C_BOX}│${C_DEF}  🌐 ${C_CYAN}آدرس ورود:${C_DEF}  $FINAL_URL"
echo -e "${C_BOX}│${C_DEF}  👤 ${C_YELLOW}نام کاربری:${C_DEF} $ADMIN_USER"
echo -e "${C_BOX}│${C_DEF}  🔑 ${C_YELLOW}رمز عبور:${C_DEF}   $ADMIN_PASS"
echo -e "${C_BOX}╰──────────────────────────────────────────────────────────────────╯${C_DEF}"
echo -e "💡 ${C_GREEN}نکته:${C_DEF} حتماً این اطلاعات را در جای امنی ذخیره کنید."
echo -e ""
