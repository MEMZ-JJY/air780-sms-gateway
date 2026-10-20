import os
import sys
import paramiko

HOST = os.environ.get("SMS_HOST", "example.com")
USER = os.environ.get("SMS_SSH_USER", "root")
PWD = os.environ.get("SMS_SSH_PASS", "")
PORT = int(os.environ.get("SMS_SSH_PORT", "22"))
UPDIR = os.environ.get("SMS_REMOTE_DIR", "/var/www/sms")
BASE = os.environ.get("SMS_BASE_URL", "https://example.com/sms")
TOKEN = os.environ.get("SMS_TOKEN", "CHANGE_ME")

LOCAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "server")
FILES = ["index.html", "lite.php", "config.php", "sms.php", "api.php", "outbox.php"]
VFILES = ["mdui.css", "mdui.global.js", "icon.css", "material-icons.woff2"]


def main():
    if not PWD:
        print("SMS_SSH_PASS 未设置，无法连接服务器")
        sys.exit(1)

    cl = paramiko.SSHClient()
    cl.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cl.connect(HOST, port=PORT, username=USER, password=PWD,
               timeout=20, auth_timeout=20, banner_timeout=20)
    sf = cl.open_sftp()

    def sh(cmd, show=True):
        _, o, e = cl.exec_command(cmd, timeout=90)
        out = o.read().decode("utf-8", "replace")
        err = e.read().decode("utf-8", "replace")
        if show:
            print(f"$ {cmd}\n{out}{err}")
        return out, err

    print("=== 1. 备份旧文件 ===")
    stamp = sh("date +%Y%m%d_%H%M%S", show=False)[0].strip()
    sh(f"mkdir -p /root/sms_backup_{stamp} && "
       f"cd {UPDIR} && cp -a sms.php view.php sms.log /root/sms_backup_{stamp}/ 2>/dev/null; "
       f"echo '--- backup contents ---'; ls -la /root/sms_backup_{stamp}")
    print("备份目录: /root/sms_backup_%s" % stamp)

    print("\n=== 2. 归档旧 view.php ===")
    sh(f"[ -f {UPDIR}/view.php ] && mv {UPDIR}/view.php /root/sms_backup_{stamp}/view.php_old; "
       f"ls {UPDIR}")

    print("\n=== 3. 上传新文件 ===")
    for n in FILES:
        lp = os.path.join(LOCAL, n)
        if not os.path.isfile(lp):
            print(f"  !! 本地缺失 {n}")
            sys.exit(1)
        sf.put(lp, UPDIR + "/" + n)
        print(f"  [up] {n}  ({os.path.getsize(lp)} bytes)")

    vdir = UPDIR + "/vendor"
    try:
        sf.mkdir(vdir)
    except OSError:
        pass
    for n in VFILES:
        lp = os.path.join(LOCAL, "vendor", n)
        if not os.path.isfile(lp):
            print(f"  !! 本地缺失 vendor/{n}")
            sys.exit(1)
        sf.put(lp, vdir + "/" + n)
        print(f"  [up] vendor/{n}  ({os.path.getsize(lp)} bytes)")

    mabs = os.path.join(LOCAL, "vendor", "misans")
    try:
        sf.mkdir(vdir + "/misans")
    except OSError:
        pass
    mlocal = sorted(f for f in os.listdir(mabs) if os.path.isfile(os.path.join(mabs, f)))
    for f in mlocal:
        sf.put(os.path.join(mabs, f), vdir + "/misans/" + f)
    mbytes = sum(os.path.getsize(os.path.join(mabs, f)) for f in mlocal)
    print(f"  [up] vendor/misans/  ({len(mlocal)} 个文件, {mbytes / 1024 / 1024:.1f} MB)")

    print("\n=== 4. 修权限 ===")
    sh(f"chown -R www-data:www-data {UPDIR}; "
       f"chmod 755 {UPDIR} {vdir}; "
       f"chmod 755 {vdir}/misans; "
       f"chmod 644 {UPDIR}/*.php {UPDIR}/index.html {vdir}/* {vdir}/misans/*; "
       f"touch {UPDIR}/outbox.json {UPDIR}/latest.cache; "
       f"chmod 664 {UPDIR}/sms.log {UPDIR}/outbox.json {UPDIR}/latest.cache; "
       f"chown www-data:www-data {UPDIR}/outbox.json {UPDIR}/latest.cache; "
       f"ls -la {UPDIR}")

    print("\n=== 5. PHP 语法自检 ===")
    for f in ["config.php", "sms.php", "api.php", "outbox.php", "lite.php"]:
        _, o, e = cl.exec_command(f"php -l {UPDIR}/{f}", timeout=30)
        r = (o.read() + e.read()).decode("utf-8", "replace").strip()
        print(f"  {f}: {r}")

    def safe_head(text, n):
        s = text[:n]
        while s:
            try:
                s.encode("utf-8")
                break
            except UnicodeEncodeError:
                s = s[:-1]
        return s

    print("\n=== 6. 线上接口自检 ===")
    for u in ["api.php?action=latest",
              "api.php?action=latest&n=3",
              "api.php?action=latest&n=3&order=asc",
              "api.php?action=latest&n=2&since=2030-01-01%2000:00:00",
              f"api.php?action=list&token={TOKEN}",
              "api.php?action=list",
              f"api.php?action=del&idx=999&token={TOKEN}",
              f"api.php?action=nope&token={TOKEN}"]:
        _, o, el = cl.exec_command(
            f"curl -sk --max-time 15 -o /tmp/_r.txt -w '%{{http_code}}' "
            f"'{BASE}/{u}'; echo; head -c 400 /tmp/_r.txt; echo", timeout=60)
        raw = o.read().decode("utf-8", "replace")
        code, _, rest = raw.partition("\n")
        print(f"  GET {BASE}/{u}")
        print(f"    HTTP {code.strip()}  {safe_head(rest.strip(), 320)}")
        print(f"    {el.read().decode('utf-8', 'replace').strip()}")

    print("\n=== 7. 回写队列测试 ===")
    _, o, _ = cl.exec_command("curl -sk -X POST --max-time 15 "
                              "-H 'Content-Type: application/json' "
                              "-d '{\"num\":\"10086\",\"content\":\"deploy-test\"}' "
                              f"'{BASE}/api.php?action=send&token={TOKEN}'; echo", timeout=60)
    print("  send ->", o.read().decode("utf-8", "replace").strip()[:300])
    sh("cat %s/outbox.json; echo '--- sms.log tail ---'; tail -3 %s/sms.log" % (UPDIR, UPDIR))

    print("\n=== 8. 前端资源可达性校验 ===")
    for p in ["index.html", "vendor/mdui.css", "vendor/mdui.global.js",
              "vendor/icon.css", "vendor/material-icons.woff2",
              "vendor/misans/misans.css", "vendor/misans/" + mlocal[1]]:
        _, o, _ = cl.exec_command(
            f"curl -sk --max-time 15 -o /dev/null -w '%{{http_code}} %{{size_download}}' "
            f"'{BASE}/{p}'", timeout=40)
        code = o.read().decode().strip()
        print(f"  {'OK ' if code.startswith('200') else '!! '} {BASE}/{p}  ->  {code}")

    sf.close()
    cl.close()
    print("\nDONE. 备份: /root/sms_backup_%s" % stamp)


if __name__ == "__main__":
    try:
        main()
    except Exception as ex:
        print("DEPLOY_FAIL:", type(ex).__name__, ex)
        sys.exit(1)
