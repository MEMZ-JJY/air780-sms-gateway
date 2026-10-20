package main

import (
	"crypto/md5"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/go-toast/toast"
)

const (
	defaultURL = "https://example.com/sms/api.php?action=latest&n=50&order=desc"
	poll       = 10 * time.Second
	appID      = "SmsNotify"
	appName    = "短信通知"
)

type item struct {
	Time    string `json:"time"`
	From    string `json:"from"`
	Content string `json:"content"`
	Type    string `json:"type"`
}

type apiResp struct {
	Items []item `json:"items"`
}

var label = map[string]string{"sms": "短信", "call": "来电", "msg": "通知"}

func baseDir() string {
	exe, err := os.Executable()
	if err != nil {
		return "."
	}
	return filepath.Dir(exe)
}

func seenFile() string { return filepath.Join(baseDir(), "sms_seen.json") }
func logFile() string  { return filepath.Join(baseDir(), "sms_notify.log") }

func logf(format string, a ...interface{}) {
	line := time.Now().Format("15:04:05") + " " + fmt.Sprintf(format, a...) + "\n"
	fmt.Print(line)
	if f, err := os.OpenFile(logFile(), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
		f.WriteString(line)
		f.Close()
	}
}

func loadSeen() map[string]bool {
	m := map[string]bool{}
	b, err := os.ReadFile(seenFile())
	if err == nil {
		var arr []string
		if json.Unmarshal(b, &arr) == nil {
			for _, k := range arr {
				m[k] = true
			}
		}
	}
	return m
}

func saveSeen(m map[string]bool) {
	arr := make([]string, 0, len(m))
	for k := range m {
		arr = append(arr, k)
	}
	if b, err := json.Marshal(arr); err == nil {
		_ = os.WriteFile(seenFile(), b, 0644)
	}
}

func keyOf(it item) string {
	s := it.Time + "|" + it.From + "|" + it.Content
	sum := md5.Sum([]byte(s))
	return fmt.Sprintf("%x", sum)
}

func fetch(url string) []item {
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("User-Agent", "SmsWinNotify/2.0")
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		logf("拉取失败: %v", err)
		return nil
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	var r apiResp
	if err := json.Unmarshal(b, &r); err != nil {
		logf("解析失败: %v", err)
		return nil
	}
	return r.Items
}

func showToast(title, body string) {
	n := toast.Notification{
		AppID:   appID,
		Title:   title,
		Message: body,
	}
	if err := n.Push(); err != nil {
		logf("toast 失败，弹窗兜底: %v", err)
		go fallbackMessageBox(title, body)
	}
}



func fallbackMessageBox(title, body string) {
	user32 := syscall.NewLazyDLL("user32.dll")
	proc := user32.NewProc("MessageBoxW")
	proc.Call(0,
		uintptr(unsafe.Pointer(syscall.StringToUTF16Ptr(body))),
		uintptr(unsafe.Pointer(syscall.StringToUTF16Ptr(title))),
		0)
}

func usage() {
	fmt.Println("Air780EPM 短信 -> Windows 原生通知 (exe 版)")
	fmt.Println("用法:")
	fmt.Println("  win_notify.exe                      默认轮询")
	fmt.Println("  win_notify.exe --url <地址>         自定义 api.php?action=latest")
	fmt.Println("  win_notify.exe --interval <秒>      轮询间隔")
	fmt.Println("  win_notify.exe --no-skip-history    首跑也弹历史")
}

func main() {
	url := defaultURL
	interval := poll
	noSkip := false

	for i := 1; i < len(os.Args); i++ {
		switch os.Args[i] {
		case "-h", "--help":
			usage()
			return
		case "--url":
			if i+1 < len(os.Args) {
				url = os.Args[i+1]
				i++
			}
		case "--interval":
			if i+1 < len(os.Args) {
				if sec, err := strconv.Atoi(os.Args[i+1]); err == nil && sec > 0 {
					interval = time.Duration(sec) * time.Second
				}
				i++
			}
		case "--no-skip-history":
			noSkip = true
		}
	}

	
	registerAppID()

	
	guardSingleInstance()

	
	showToast(appName, "已启动，正在后台监听新短信")

	seen := loadSeen()
	
	
	baseline := !noSkip
	if baseline {
		logf("首轮轮询作为基线（已有短信不弹），仅弹新到短信")
	} else {
		logf("--no-skip-history：首轮也弹历史")
	}
	logf("启动，轮询: %s 间隔 %v", url, interval)

	for {
		items := fetch(url)
		for _, it := range items {
			k := keyOf(it)
			if seen[k] {
				continue
			}
			seen[k] = true
			if baseline {
				continue
			}
			lbl := label[it.Type]
			if lbl == "" {
				lbl = "短信"
			}
			title := lbl + " · " + it.From
			body := strings.TrimSpace(it.Content)
			if it.Time != "" {
				body = body + "\n" + it.Time
			}
			logf("弹通知: %s", title)
			go showToast(title, body)
		}
		baseline = false
		saveSeen(seen)
		time.Sleep(interval)
	}
}
