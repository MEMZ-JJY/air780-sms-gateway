import os
import paramiko

HOST = os.environ.get("SMS_HOST", "example.com")
USER = os.environ.get("SMS_SSH_USER", "root")
PWD = os.environ.get("SMS_SSH_PASS", "")
PORT = int(os.environ.get("SMS_SSH_PORT", "22"))
UPDIR = os.environ.get("SMS_REMOTE_DIR", "/var/www/sms")

LOCAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "server")
FILES = ["config.php", "api.php", "outbox.php", "index.html"]


def main():
    if not PWD:
        print("SMS_SSH_PASS 未设置，无法连接服务器")
        return

    cl = paramiko.SSHClient()
    cl.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cl.connect(HOST, port=PORT, username=USER, password=PWD, timeout=25)
    sf = cl.open_sftp()
    for f in FILES:
        lp = os.path.join(LOCAL, f)
        if not os.path.exists(lp):
            print("跳过(本地缺失):", f)
            continue
        sf.put(lp, UPDIR + "/" + f)
        print("上传 %s (%d bytes)" % (f, os.path.getsize(lp)))
    sf.close()

    def sh(cmd, t=60):
        _, o, e = cl.exec_command(cmd, timeout=t)
        out = o.read().decode("utf-8", "replace").strip()
        err = e.read().decode("utf-8", "replace").strip()
        print("$ %s\n%s%s" % (cmd, out, err))
        return out

    for f in ["config.php", "api.php", "outbox.php"]:
        sh("php -l %s/%s" % (UPDIR, f))
    sh("chown www-data:www-data %s/{config.php,api.php,outbox.php,index.html} 2>/dev/null; "
       "chmod 644 %s/{config.php,api.php,outbox.php,index.html} 2>/dev/null; "
       "echo done" % (UPDIR, UPDIR))
    cl.close()
    print("=== 部署完成 ===")


if __name__ == "__main__":
    main()
