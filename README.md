# ec2-host-config

Sanitized configuration snapshot for the personal-services EC2 instance
(`i-0da26b37e9f8a0657`, AL2023, arm64). Private repo: contains hostnames and
paths, never credentials.

## Layout

| Path | Source on host |
| --- | --- |
| `nginx/conf.d/` | `/etc/nginx/conf.d/` |
| `backup/` | EBS Data Lifecycle Manager policy JSON (applied via AWS CLI) |
| `ssh/` | `/etc/ssh/sshd_config.d/` |
| `fail2ban/` | `/etc/fail2ban/jail.local`, `/etc/fail2ban/jail.d/` |
| `journald/` | `/etc/systemd/journald.conf.d/` |
| `dnf/` | `/etc/dnf/automatic.conf` |
| `systemd/` | `/etc/systemd/system/*.service` for self-hosted services |
| `letsencrypt/` | `/etc/letsencrypt/renewal/*.conf`, `cli.ini` (no keys) |
| `scripts/` | `/usr/local/bin/update-all` and related helpers |
| `cron/` | `/etc/cron.d/` entries |

## Never committed

- `/etc/pixel-forensics.env`, `/etc/quartz-oracle.env` (application secrets)
- `/etc/nginx/*.htpasswd` (password hashes)
- `/etc/letsencrypt/archive/`, `live/`, `accounts/` (TLS private keys)
- `/etc/ssh/ssh_host_*` (host private keys)
- AWS credentials, `.pem` files

## Restore

Configs are copied back by hand after review; `nginx -t` precedes any reload and
`systemctl daemon-reload` precedes any unit restart. Secrets are re-created on
the host, not restored from this repo.
