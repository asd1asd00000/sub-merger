package db

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/big"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/asd1asd00000/sub-merger/internal/models"
)

const DBFile = "/etc/merge_subs/database.json"
const SettingsFile = "/etc/merge_subs/settings.json"

var mu sync.RWMutex

// تابع تولید رمز عبور بسیار امن و تصادفی
func generateSecurePassword(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, length)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		b[i] = charset[n.Int64()]
	}
	return string(b)
}

func LoadDB() (map[string]models.User, error) {
	mu.RLock()
	defer mu.RUnlock()

	data := make(map[string]models.User)
	file, err := os.ReadFile(DBFile)
	if err != nil {
		if os.IsNotExist(err) {
			return data, nil
		}
		return nil, err
	}

	err = json.Unmarshal(file, &data)
	return data, err
}

func SaveDB(data map[string]models.User) error {
	mu.Lock()
	defer mu.Unlock()

	err := os.MkdirAll(filepath.Dir(DBFile), 0755)
	if err != nil {
		return err
	}

	file, err := json.MarshalIndent(data, "", "    ")
	if err != nil {
		return err
	}

	return os.WriteFile(DBFile, file, 0644)
}

func LoadSettings() (models.SystemSettings, error) {
	mu.RLock()
	file, err := os.ReadFile(SettingsFile)
	mu.RUnlock() // باز کردن قفل خواندن پیش از هرگونه تغییر

	var settings models.SystemSettings

	// اگر فایل وجود نداشت (اجرای اول یا حذف شدن فایل توسط ادمین)
	if err != nil || len(file) == 0 {
		randomPass := generateSecurePassword(12)
		settings = models.SystemSettings{
			AdminUsername: "admin",
			AdminPassword: randomPass,
		}
		SaveSettings(settings)

		log.Println("\n=====================================================================")
		log.Println("🛡️ INITIAL SECURITY SETUP: New settings file generated!")
		log.Println("👤 Admin Username : admin")
		log.Println("🔑 Admin Password :", randomPass)
		log.Println("💡 Keep this safe! You can view it anytime via SSH using:")
		log.Println("   cat /etc/merge_subs/settings.json")
		log.Println("=====================================================================\n")
		
		return settings, nil
	}

	err = json.Unmarshal(file, &settings)
	
	// جلوگیری از ایجاد باگ در صورتی که فایل خراب شده باشد یا فیلدها خالی باشند
	if settings.AdminUsername == "" || settings.AdminPassword == "" {
		settings.AdminUsername = "admin"
		settings.AdminPassword = generateSecurePassword(12)
		SaveSettings(settings)
		
		log.Println("\n⚠️ WARNING: Empty credentials detected in settings.json!")
		log.Println("🛡️ SECURITY TRIGGERED: Credentials have been forcefully reset.")
		log.Println("🔑 New Password:", settings.AdminPassword, "\n")
	}

	return settings, err
}

func SaveSettings(settings models.SystemSettings) error {
	mu.Lock()
	defer mu.Unlock()

	err := os.MkdirAll(filepath.Dir(SettingsFile), 0755)
	if err != nil {
		return err
	}

	file, err := json.MarshalIndent(settings, "", "    ")
	if err != nil {
		return err
	}

	return os.WriteFile(SettingsFile, file, 0644)
}

func StartAutoBackup() {
	ticker := time.NewTicker(1 * time.Hour)
	go func() {
		for range ticker.C {
			mu.RLock()
			data, err := os.ReadFile(DBFile)
			mu.RUnlock()

			if err == nil && len(data) > 0 {
				sendToTelegram()
			}
		}
	}()
}

func TriggerInitialTelegramSync(settings models.SystemSettings) {
	if settings.TelegramToken == "" || settings.TelegramChatID == "" {
		return
	}

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", settings.TelegramToken)
	msg := "✅ ارتباط با موفقیت برقرار شد!\n\nسیستم بکاپ‌گیری خودکار (ساعتی) برای شما فعال گردید. سیستم هم‌اکنون در حال پردازش و ارسال اولین فایل بکاپ است... ⏳"
	
	payload := map[string]string{
		"chat_id": settings.TelegramChatID,
		"text":    msg,
	}
	jsonPayload, _ := json.Marshal(payload)
	http.Post(url, "application/json", bytes.NewBuffer(jsonPayload))

	time.Sleep(2 * time.Second)
	sendToTelegram()
}

func sendToTelegram() {
	settings, _ := LoadSettings()
	
	if settings.TelegramToken == "" || settings.TelegramChatID == "" {
		log.Println("⚠️ Telegram settings are empty. Skipping auto-backup.")
		return
	}

	zipPass := settings.TelegramPassword
	if zipPass == "" {
		zipPass = "12345"
	}

	zipPath := "/etc/merge_subs/backup.zip"

	cmd := exec.Command("zip", "-j", "-P", zipPass, zipPath, DBFile)
	err := cmd.Run()
	if err != nil {
		log.Println("❌ Error creating zip file:", err)
		return
	}
	defer os.Remove(zipPath)

	file, err := os.Open(zipPath)
	if err != nil {
		return
	}
	defer file.Close()

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("chat_id", settings.TelegramChatID)

	fileName := fmt.Sprintf("SubMerger_Backup_%s.zip", time.Now().Format("2006-01-02_15-04"))
	part, err := writer.CreateFormFile("document", fileName)
	if err != nil {
		return
	}
	io.Copy(part, file)
	writer.Close()

	url := fmt.Sprintf("https://api.telegram.org/bot%s/sendDocument", settings.TelegramToken)
	req, err := http.NewRequest("POST", url, body)
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		log.Println("❌ Error sending backup to Telegram:", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == 200 {
		log.Println("✅ Backup successfully encrypted and sent to Telegram!")
	} else {
		log.Printf("❌ Failed to send backup. Telegram API returned status: %d", resp.StatusCode)
	}
}
