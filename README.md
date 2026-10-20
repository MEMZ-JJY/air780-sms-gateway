# Luat SMS 转发系统

基于合宙 Air780 系列（LuatOS）的短信转发系统,设备端把收到的短信/来电/通知上报到服务端。
支持网页端查看与回复，Windows toast返回最新短信

```
firmware/   设备端 LuatOS 源码
server/     PHP 服务端 + 网页前端
client/     Windows 通知客户端（Go 版为主，另含 Python 备选）
tools/      部署脚本
docs/       使用与部署说明
```

## 组件

### 1. 设备端 `firmware/`
用 LuaTools 打开 `firmware/` 整个目录作为工程，编译烧录到 Air780E（或同系列）开发板。
- `main.lua` 引导与编排（网络/订阅/定时器）
- `commands.lua` 指令分发（`##` 协议：sms/stat/loc/net/volt/led/gpio/ping/echo/smsclear/reboot/call）
- `sms_at.lua` 纯 AT 短信收发（不依赖固件是否编入 sms 库）
- `model/sim/led/lbs/params/outbox/subscribe/cc.lua` 各功能模块

设备端配置文件 `firmware/config.lua` 需要你修改：
- `notify.http.token`：与服务端 `SMS_TOKEN` 一致的鉴权令牌（当前为占位符 `CHANGE_ME`）
- `notify.http.channel.mySms` / `outbox.url` 中的服务器地址（当前占位 `example.com`）
- `system.ctrl`：允许下发 `##` 指令的号码白名单

### 2. 服务端 `server/`
上传到支持 PHP 7.4 的 Web 目录（例如 `/var/www/sms`）。需要 `php` 可执行。
- `config.php`：服务端配置，先改 `SMS_TOKEN`（与设备端一致），`SMS_ENABLE_TOKEN` 控制是否校验
- `api.php`：统一 JSON 接口（list/del/clear/send/cmd/outbox_*）
- `sms.php`：设备上报接收端
- `outbox.php`：待发短信/指令队列（轮询取件）
- `heartbeat.php`：设备健康心跳
- `index.html`：网页端（基于mdui仿一些手机的短信页面）
- `lite.php`：极简只读页（连IE8都支持了，）

服务端会在目录下生成 `sms.log`、`outbox.json`、`status.json`、`latest.cache` 等运行时文件，
确保 Web 服务对该目录可写（部署脚本会 `chown www-data` 并设权限）。

如需 `/sms/lite` 无扩展名直访，参考 `tools/enable_lite.py` 加一条 nginx `rewrite`。

### 3. Windows 通知客户端 `client/`
轮询服务端免鉴权接口 `api.php?action=latest`，增量拉取并弹系统 toast。
- `client/go/`：Go 版（`go-toast`），编译：`go build -ldflags="-s -w -H windowsgui"`，产物零依赖
- `client/python/win_notify.py`：备选
- 默认轮询 `example.com` 地址，可用 `--url` 自定义；

### 4. 部署脚本 `tools/`
请用环境变量传入凭据而不是去全局定义：

```bash
export SMS_HOST=your.host
export SMS_SSH_USER=root
export SMS_SSH_PASS='******'
export SMS_REMOTE_DIR=/var/www/sms
export SMS_BASE_URL=https://your.host/sms
export SMS_TOKEN=your_token

python tools/deploy.py          # 全量上传
python tools/deploy_lite.py     # 仅 lite.php
python tools/_deploy_webcmd.py  # 仅改了网页端相关文件
python tools/_check_hb.py       # 查看设备心跳状态
python tools/enable_lite.py     # 配置 nginx /sms/lite 路由
```

## 安全警告
- 所有token，服务器地址等内容均为占位符，请一定要修改！！
- 服务端 `api.php` 有一个免鉴权的 `latest` 接口用于获取最新短信轮询，如果不需要可以自己去注释掉，这个是为了方便桌面端toast通知
- `lite.php` 如果不需要也请删除掉！！！


## 致谢
参考了一些开源的仓库但是找不到了等有时间一定补上www

## 许可证
[MIT](LICENSE)
