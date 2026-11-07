#!/usr/bin/env bash
# Run ON the EC2 host. Read-only: copies configs to /tmp and tars them.
set -u

# /etc/nginx, /etc/ssh and several units are root-only; re-exec once with sudo.
if [ "$(id -u)" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

INVOKER=${SUDO_USER:-ec2-user}
OUT=/tmp/hostcfg
TAR=/tmp/hostcfg.tar.gz
rm -rf "$OUT" "$TAR"
mkdir -p "$OUT/_meta"

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
copy /etc/fail2ban/jail.local /etc/fail2ban/fail2ban.conf /etc/fail2ban/jail.d/*.conf /etc/fail2ban/filter.d/*.local
copy /etc/systemd/journald.conf.d/*.conf
copy /etc/dnf/automatic.conf
copy /etc/letsencrypt/renewal/*.conf /etc/letsencrypt/cli.ini
copy /etc/letsencrypt/options-ssl-nginx.conf
copy /etc/cron.d/* 2>/dev/null || true
copy /usr/local/bin/update-all 2>/dev/null || true

# Only host-local (non-symlink) unit files; vendor units are reproducible from packages.
for u in /etc/systemd/system/*.service /etc/systemd/system/*.timer; do
  [ -f "$u" ] && [ ! -L "$u" ] && copy "$u"
done

dump_crontab() {
  local user=$1 dest=$2
  if crontab -l -u "$user" 2>/dev/null | grep -q .; then
    crontab -l -u "$user" 2>/dev/null > "$dest"
  else
    echo "# no crontab entries for $user" > "$dest"
  fi
}
dump_crontab root "$OUT/_meta/root.crontab"
dump_crontab ec2-user "$OUT/_meta/ec2-user.crontab"
systemctl list-unit-files --type=service --state=enabled --no-pager \
  > "$OUT/_meta/enabled-units.txt" 2>/dev/null || true

echo "--- secret scan (inspect before upload) ---"
grep -rniE 'password|passwd|secret|token|api[_-]?key|BEGIN [A-Z ]*PRIVATE' "$OUT" \
  | grep -viE 'server_tokens off|auth_basic_user_file|#[[:space:]]*(no|never)' || echo "no matches"

tar czf "$TAR" -C "$OUT" .
chown -R "$INVOKER" "$OUT" "$TAR" 2>/dev/null || true
echo "--- done ---"
echo "files: $(find "$OUT" -type f | wc -l)  size: $(du -h "$TAR" | cut -f1)  path: $TAR"
