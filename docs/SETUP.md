# 部署说明

## 设备端（Air780E）
1. 用 LuaTools 打开 `firmware/` 目录作为工程。
2. 修改 `firmware/config.lua`：
   - `notify.http.token` 改为你自己的令牌（与服务端 `config.php` 的 `SMS_TOKEN` 一致）。
   - `notify.http.channel.mySms` / `outbox.url` 中的 `example.com` 改为你的服务器域名。
   - `system.ctrl` 填入允许下发 `##` 指令的号码白名单。
3. 编译并烧录。

## 服务端（PHP 7.4+）
1. 将 `server/` 上传到 Web 目录（如 `/var/www/sms`），确保目录可写。
2. 修改 `server/config.php` 的 `SMS_TOKEN` 与设备端一致。
3. `php -l` 自检各 php 文件。
4. 需要 `/sms/lite` 无扩展名直访时，用 `tools/enable_lite.py` 配置 nginx `rewrite`。

## Windows 通知客户端
- Go 版：`cd client/go && go build -ldflags="-s -w -H windowsgui"`，运行 `win_notify.exe --url <你的 api 地址>`。
- Python 版：`python client/python/win_notify.py --url <你的 api 地址>`。

## 部署脚本
凭据通过环境变量传入（`SMS_HOST` / `SMS_SSH_USER` / `SMS_SSH_PASS` / `SMS_REMOTE_DIR` / `SMS_BASE_URL` / `SMS_TOKEN`），见 `tools/` 各脚本。
