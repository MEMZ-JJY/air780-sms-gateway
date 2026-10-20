import os
import paramiko

HOST = os.environ.get("SMS_HOST", "example.com")
USER = os.environ.get("SMS_SSH_USER", "root")
PWD = os.environ.get("SMS_SSH_PASS", "")
PORT = int(os.environ.get("SMS_SSH_PORT", "22"))
UPDIR = os.environ.get("SMS_REMOTE_DIR", "/var/www/sms")

LOCAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "server")


def main():
    if not PWD:
        print("SMS_SSH_PASS 未设置，无法连接服务器")
        return

    cl = paramiko.SSHClient()
    cl.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cl.connect(HOST, port=PORT, username=USER, password=PWD, timeout=25)
    sf = cl.open_sftp()
    lp = os.path.join(LOCAL, "lite.php")
    sf.put(lp, UPDIR + "/lite.php")
    print("上传 lite.php (%d bytes)" % os.path.getsize(lp))
    sf.close()

    def sh(cmd, t=60):
        _, o, e = cl.exec_command(cmd, timeout=t)
        out = o.read().decode("utf-8", "replace").strip()
        err = e.read().decode("utf-8", "replace").strip()
        print("$ %s\n%s%s" % (cmd, out, err))
        return out

    sh(f"php -l {UPDIR}/lite.php")
    sh(f"chmod 644 {UPDIR}/lite.php; chown www-data:www-data {UPDIR}/lite.php; "
       f"[ -f {UPDIR}/lite.html ] && rm -f {UPDIR}/lite.html && echo '旧 lite.html 已删'; "
       f"ls -la {UPDIR} | grep -E 'lite|php'")
    cl.close()


if __name__ == "__main__":
    main()
