

"""
Air780EPM 短信 -> Windows 系统通知客户端
=========================================
轮询服务端 api.php?action=latest，新到的短信用 Windows 原生 toast 弹通知。
不开浏览器、后台常驻即可收到短信/来电/通知。

· 拉取用标准库（urllib），无第三方网络依赖
· 通知用 win10toast（需 pywin32）；打包进 exe 后零依赖
· 本地 sms_seen.json 记录已弹过的短信，避免重复弹窗
· 首跑跳过历史（不狂弹），之后重启也能补弹离线期间到达的短信

用法：
    python win_notify.py                      # 默认轮询 https://example.com/sms/...
    python win_notify.py --url "<你的地址>"   # 自定义接口
    python win_notify.py --interval 15        # 轮询间隔秒
    python win_notify.py --no-skip-history     # 首跑也弹历史
打包：
    pyinstaller --onefile --noconsole --name SmsNotify win_notify.py
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.request
import urllib.error

DEFAULT_URL = "https://example.com/sms/api.php?action=latest&n=50&order=asc"
POLL = 10
SEEN_MAX = 3000  

BASE = os.path.dirname(sys.executable) if getattr(sys, "frozen", False) \
    else os.path.dirname(os.path.abspath(__file__))
SEEN_FILE = os.path.join(BASE, "sms_seen.json")
LOG_FILE = os.path.join(BASE, "sms_notify.log")

LABEL = {"sms": "短信", "call": "来电", "msg": "通知"}


def log(*a):
    line = "[%s] %s" % (time.strftime("%H:%M:%S"), " ".join(str(x) for x in a))
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def load_seen():
    try:
        with open(SEEN_FILE, encoding="utf-8") as f:
            return set(json.load(f))
    except Exception:
        return set()


def save_seen(seen):
    try:
        with open(SEEN_FILE, "w", encoding="utf-8") as f:
            json.dump(sorted(seen), f, ensure_ascii=False)
    except Exception as e:
        log("seen 保存失败:", e)


def key_of(it):
    s = "%s|%s|%s" % (it.get("time", ""), it.get("from", ""), it.get("content", ""))
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def fetch_items(url):
    req = urllib.request.Request(url, headers={"User-Agent": "SmsWinNotify/1.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.loads(r.read().decode("utf-8"))
    return data.get("items", []) if isinstance(data, dict) else []


def show_toast(title, body):
    """零依赖弹通知：调用 Windows 自带的 PowerShell 原生 toast（不下载任何包）。
    用 -EncodedCommand + 环境变量传参，避免引号/转义地狱。"""
    ps = (
        'Add-Type -AssemblyName System.Runtime.WindowsRuntime;'
        '[void][Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime];'
        '[void][Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom,ContentType=WindowsRuntime];'
        '$appId="SmsNotify";'
        '$k="HKCU:\\Software\\Classes\\AppUserModelId\\$appId";'
        'if(!(Test-Path $k)){New-Item $k -Force|Out-Null;Set-ItemProperty $k DisplayName "短信通知"}'
        '$t=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);'
        '$x=$t.GetElementsByTagName("text");'
        '$x.Item(0).AppendChild($t.CreateTextNode($env:SMS_TITLE));'
        '$x.Item(1).AppendChild($t.CreateTextNode($env:SMS_BODY));'
        '[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($t)'
    )
    try:
        import base64, subprocess
        b64 = base64.b64encode(ps.encode("utf-16-le")).decode()
        env = dict(os.environ)
        env["SMS_TITLE"] = title
        env["SMS_BODY"] = body
        subprocess.run(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", b64],
            env=env, capture_output=True, timeout=15,
        )
    except Exception as e:
        log("toast 失败:", e)
        try:
            import ctypes
            ctypes.windll.user32.MessageBoxW(0, body, title, 0)
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser(description="Air780EPM 短信 Windows 通知客户端")
    ap.add_argument("--url", default=DEFAULT_URL, help="api.php?action=latest 地址")
    ap.add_argument("--interval", type=int, default=POLL, help="轮询间隔（秒）")
    ap.add_argument("--no-skip-history", action="store_true",
                    help="首次运行也弹历史（默认跳过已有，只弹新到的）")
    args = ap.parse_args()

    seen = load_seen()
    first_ever = (len(seen) == 0) and not args.no_skip_history
    if first_ever:
        log("首跑：跳过历史，仅弹新到短信")
    log("启动，轮询:", args.url, "间隔", args.interval, "s")

    to_toast = []  
    try:
        while True:
            try:
                items = fetch_items(args.url)
            except Exception as e:
                log("拉取失败:", e)
                time.sleep(args.interval)
                continue

            for it in items:
                k = key_of(it)
                if k in seen:
                    continue
                seen.add(k)
                if first_ever:
                    continue  
                to_toast.append(it)

            first_ever = False
            if len(seen) > SEEN_MAX:
                seen = set(sorted(seen)[-SEEN_MAX:])

            for it in to_toast:
                label = LABEL.get(it.get("type", "sms"), "短信")
                title = "%s · %s" % (label, it.get("from", "未知号码"))
                body = (it.get("content", "") or "").strip()[:240]
                extra = it.get("time", "")
                if extra:
                    body = body + "\n" + extra
                show_toast(title, body)
                log("弹通知:", title)
            to_toast = []
            save_seen(seen)
            time.sleep(args.interval)
    except KeyboardInterrupt:
        log("退出")
        save_seen(seen)


if __name__ == "__main__":
    main()
