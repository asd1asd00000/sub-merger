#!/bin/bash
# اسکریپت نصب خودکار و هوشمند پورتال تجمیع سابسکریپشن

echo "🚀 شروع فرآیند نصب هوشمند پنل..."

# ۱. نصب پیش‌نیازها (اضافه شدن curl برای پیدا کردن آخرین نسخه)
apt update && apt install zip git wget curl -y

# اطمینان از اینکه مسیر Go در همین جلسه ترمینال شناخته می‌شود
export PATH=$PATH:/usr/local/go/bin

# ۲. بررسی و نصب زبان گو به صورت کاملاً داینامیک
if ! command -v go &> /dev/null; then
    echo "📥 در حال پیدا کردن و نصب آخرین نسخه زبان Go..."
    # پیدا کردن آخرین نسخه به صورت خودکار از سرور گوگل
    LATEST_GO=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
    echo "✅ نسخه پیدا شده: $LATEST_GO"
    
    wget https://go.dev/dl/${LATEST_GO}.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf ${LATEST_GO}.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    rm ${LATEST_GO}.linux-amd64.tar.gz
fi

# ۳. ایجاد پوشه‌های ساختاری سیستم
mkdir -p /etc/merge_subs

# ۴. کامپایل پروژه گولنگ
echo "⚙️ در حال بیلد کردن فایل اجرایی پروژه..."
go mod tidy
go build -o /usr/local/bin/sub-merger-app cmd/server/main.go

# ۵. ساخت سرویس لینوکسی برای اجرای دائمی در پس‌زمینه
echo "🛠️ در حال ساخت سرویس لینوکس (Systemd)..."
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

# ۶. فعال‌سازی و روشن کردن سرویس
systemctl daemon-reload
systemctl enable sub-merger.service
systemctl restart sub-merger.service

echo "✅ نصب با موفقیت تمام شد! پنل در پس‌زمینه سرور شما در حال اجراست."
