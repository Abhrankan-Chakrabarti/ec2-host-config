#!/usr/bin/env bash
# Run ON the EC2 host. Read-only: copies configs to /tmp and tars them.
set -u
OUT=/tmp/hostcfg
TAR=/tmp/hostcfg.tar.gz
rm -rf "$OUT" "$TAR"
mkdir -p "$OUT"

copy() {
  for f in "$@"; do
    [ -e "$f" ] || continue
    case "$f" in
      */.env|*.env|*.htpasswd|*.pem|*.key|*/ssh_host_*|*/archive/*|*/live/*|*/accounts/*)
        echo "SKIP(secret) $f"; continue ;;
    esac
    install -D -m 0644 "$f" "$OUT/${f#/}"
  done
}

copy /etc/nginx/nginx.conf
copy /etc/nginx/conf.d/*.conf
copy /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf
copy /etc/fail2ban/jail.local /etc/fail2ban/fail2ban.conf /etc/fail2ban/jail.d/*.conf
copy /etc/systemd/journald.conf.d/*.conf
copy /etc/dnf/automatic.conf
copy /etc/letsencrypt/renewal/*.conf /etc/letsencrypt/cli.ini
copy /etc/letsencrypt/options-ssl-nginx.conf
copy /etc/cron.d/* 2>/dev/null || true
copy /usr/local/bin/update-all 2>/dev/null || true

# Only host-local (non-symlink) unit files; vendor units are reproducible from packages.
for u in /etc/systemd/system/*.service; do
  [ -f "$u" ] && [ ! -L "$u" ] && copy "$u"
done

sudo crontab -l -u root 2>/dev/null > "$OUT/cron/root.crontab" || true
sudo crontab -l -u ec2-user 2>/dev/null > "$OUT/cron/ec2-user.crontab" || true
sudo systemctl list-unit-files --type=service --state=enabled --no-pager \
  > "$OUT/systemd/enabled-units.txt" 2>/dev/null || true

echo "--- secret scan (inspect before upload) ---"
grep -rniE 'password|passwd|secret|token|api[_-]?key|BEGIN [A-Z ]*PRIVATE' "$OUT" \
  | grep -viE 'server_tokens off|auth_basic_user_file|#[[:space:]]*(no|never)' || echo "no matches"

tar czf "$TAR" -C "$OUT" .
echo "--- done ---"
echo "files: $(find "$OUT" -type f | wc -l)  size: $(du -h "$TAR" | cut -f1)  path: $TAR"
