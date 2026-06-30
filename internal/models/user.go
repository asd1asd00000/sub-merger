package models

// ساختار دقیق کاربر
type User struct {
	Username   string   `json:"username"`
	URLs       []string `json:"urls"`
	CreatedAt  int64    `json:"created_at"`
	LastActive int64    `json:"last_active"`
}

// ساختار تنظیمات کل سیستم (ورود + تلگرام + وبلاگ)
type SystemSettings struct {
	AdminUsername    string `json:"admin_username"`
	AdminPassword    string `json:"admin_password"`
	TelegramToken    string `json:"token"`
	TelegramChatID   string `json:"chat_id"`
	TelegramPassword string `json:"password"`
	TutorialsURL     string `json:"tutorials_url"`     // لینک آموزش‌ها
	AnnouncementsURL string `json:"announcements_url"` // لینک اطلاعیه‌ها
}
