import os
import paramiko

HOST = os.environ.get("SMS_HOST", "example.com")
USER = os.environ.get("SMS_SSH_USER", "root")
PWD = os.environ.get("SMS_SSH_PASS", "")
PORT = int(os.environ.get("SMS_SSH_PORT", "22"))
UPDIR = os.environ.get("SMS_REMOTE_DIR", "/var/www/sms")


def main():
    if not PWD:
        print("SMS_SSH_PASS 未设置，无法连接服务器")
        return

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, PORT, USER, PWD, timeout=15)
    for cmd in [
        f'ls -la {UPDIR}/heartbeat.php',
        'echo "---STATUS---"; cat %s/status.json 2>/dev/null || echo "NO_STATUS_FILE"' % UPDIR,
    ]:
        _, o, e = ssh.exec_command(cmd)
        print(o.read().decode().strip() or e.read().decode().strip())
    ssh.close()


if __name__ == "__main__":
    main()
