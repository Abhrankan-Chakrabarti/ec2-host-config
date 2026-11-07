# ec2-host-config

Sanitized configuration snapshot for the personal-services EC2 instance
(`i-0da26b37e9f8a0657`, AL2023, arm64). Public repo: contains hostnames and
paths, never credentials. Kept public on purpose so it stays recoverable
without access to the owner's account.

## Layout

| Path | Source on host |
| --- | --- |
| `nginx/` | `/etc/nginx/nginx.conf`, `/etc/nginx/conf.d/` |
| `backup/` | EBS Data Lifecycle Manager policy JSON (applied via AWS CLI) |
| `ssh/` | `/etc/ssh/sshd_config`, `/etc/ssh/sshd_config.d/` |
| `fail2ban/` | `/etc/fail2ban/jail.local`, `jail.d/`, `fail2ban.conf` |
| `journald/` | `/etc/systemd/journald.conf.d/` |
| `dnf/` | `/etc/dnf/automatic.conf` |
| `systemd/` | `/etc/systemd/system/*.service`, `*.timer` (host-local only) |
| `letsencrypt/` | `renewal/*.conf`, `cli.ini`, `options-ssl-nginx.conf` (no keys) |
| `scripts/` | `/usr/local/bin/update-all`, collection helper |
| `_meta/` | generated inventories: crontabs, enabled unit list |

## Never committed

- `/etc/pixel-forensics.env`, `/etc/quartz-oracle.env` (application secrets)
- `/etc/nginx/*.htpasswd` (password hashes)
- `/etc/letsencrypt/archive/`, `live/`, `accounts/` (TLS private keys)
- `/etc/ssh/ssh_host_*` (host private keys)
- AWS credentials, `.pem` files

## Restore

Review, then copy each tree back to its source path with `install -D -m 0644`.
`nginx -t` precedes any reload and `systemctl daemon-reload` precedes any unit
restart. Secrets are re-created on the host, not restored from this repo.

## Refresh

Run `scripts/collect-host-config.sh` on the host, then replace the trees here
with its output. The script re-execs under `sudo`, skips secret paths, and
prints a scan of anything that looks credential-like before you commit.

## License

MIT — see [LICENSE](LICENSE).
