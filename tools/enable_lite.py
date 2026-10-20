import os
import re
import paramiko

HOST = os.environ.get("SMS_HOST", "example.com")
USER = os.environ.get("SMS_SSH_USER", "root")
PWD = os.environ.get("SMS_SSH_PASS", "")
PORT = int(os.environ.get("SMS_SSH_PORT", "22"))
AVAIL = os.environ.get("SMS_NGINX_CONF", "/etc/nginx/sites-available/default")

MARK = "location = /sms/lite"
ANCHOR = "    location / { try_files $uri $uri/ =404; }"
BLOCK = (
    "    # Lite 版：只显示最新一条短信（服务端渲染，零 CSS/JS）\n"
    "    location = /sms/lite {\n"
    "        rewrite /sms/lite /sms/lite.php last;\n"
    "    }\n"
)


def main():
    if not PWD:
        print("SMS_SSH_PASS 未设置，无法连接服务器")
        return

    cl = paramiko.SSHClient()
    cl.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cl.connect(HOST, port=PORT, username=USER, password=PWD, timeout=20)

    def sh(cmd, t=60):
        _, o, e = cl.exec_command(cmd, timeout=t)
        return (o.read().decode("utf-8", "replace") + e.read().decode("utf-8", "replace")).strip()

    def run_py(src_text):
        sf = cl.open_sftp()
        with sf.open("/tmp/_lite_conf.py", "w") as f:
            f.write(src_text)
        sf.close()
        return sh("python3 /tmp/_lite_conf.py")

    PATCH = """
import io, re, sys
p, anchor, blk, mark = ARG_P, ARG_A, ARG_B, ARG_M
s = io.open(p, encoding='utf-8').read()
m = re.search(r'(?:#[^\n]*\n\s*)?' + re.escape(mark) + r'\s*\{[^}]*\}', s)
if m:
    s = s[:m.start()] + s[m.end():]
    print('REPLACED_OLD_BLOCK')
if mark not in s:
    if anchor not in s:
        print('ANCHOR_NOT_FOUND')
        sys.exit(1)
    s = s.replace(anchor, blk + anchor, 1)
io.open(p, 'w', encoding='utf-8').write(s)
print('WRITTEN', len(s))
""".replace("ARG_P", repr(AVAIL)).replace("ARG_A", repr(ANCHOR)) \
        .replace("ARG_B", repr(BLOCK)).replace("ARG_M", repr(MARK))

    print("链接关系:", sh(f"readlink /etc/nginx/sites-enabled/$(basename {AVAIL})"))
    before = sh(f"wc -c < {AVAIL}")
    print("改前大小:", before)

    print("insert  :", run_py(PATCH))

    t = sh("nginx -t 2>&1")
    t1 = t.replace("\n", " | ")
    print("nginx -t:", t1)
    if "successful" not in t1:
        print("!!! 不通过，需要人工看，不自动回滚")
        cl.close()
        raise SystemExit(1)

    print("reload  :", sh("nginx -s reload 2>&1") or "ok")
    print("--- 探活 ---")
    for u in ["/sms/lite", "/sms/lite.php", "/sms/", "/"]:
        code = sh(f"curl -sk -o /dev/null -w '%{{http_code}}' --max-time 12 "
                  f"'https://127.0.0.1{u}' -H 'Host: example.com'")
        ct = sh(f"curl -sk -o /dev/null -w '%{{content_type}}' --max-time 12 "
                f"'https://127.0.0.1{u}' -H 'Host: example.com'")
        print("  %-16s -> %s  %s" % (u, code, ct))
    print("--- /sms/lite 响应体 ---")
    print(sh("curl -sk --max-time 12 'https://127.0.0.1/sms/lite' -H 'Host: example.com' | head -c 600"))
    cl.close()


if __name__ == "__main__":
    main()
