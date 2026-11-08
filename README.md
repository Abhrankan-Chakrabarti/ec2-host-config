# ec2-host-config

[![Config CI](https://github.com/Abhrankan-Chakrabarti/ec2-host-config/actions/workflows/ci.yml/badge.svg)](https://github.com/Abhrankan-Chakrabarti/ec2-host-config/actions/workflows/ci.yml)

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

Two cases: putting files back on a live host, or rebuilding the host.

### Config onto a live host

Copy each tree back to its source path with `install -D -m 0644`, then:

```bash
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl daemon-reload
sudo systemctl restart pixel-forensics quartz-oracle lab-api crypto-lab abhrankan-status
```

### Rebuild the instance

1. Create a volume from the newest snapshot and attach it as the root device:

   ```bash
   aws ec2 describe-snapshots --owner-ids self --filters Name=tag:Backup,Values=daily \
     --query 'sort_by(Snapshots,&StartTime)[-1].SnapshotId' --output text
   aws ec2 create-volume --snapshot-id <snap-id> --availability-zone <az> --volume-type gp3
   ```

   Attach it to a new instance as `/dev/xvda`, then boot and confirm SSH.

2. Recreate the files deliberately kept out of this repo: `/etc/pixel-forensics.env`,
   `/etc/quartz-oracle.env`, and `/etc/nginx/{school,status,cockpit}.htpasswd`
   (`htpasswd -B` per user).

3. Clone this repo and apply the trees from the Layout table, then run the
   live-host commands above. Install the scripts with their mode intact:

   ```bash
   sudo install -m 0755 scripts/update-all /usr/local/bin/update-all
   sudo sshd -t && sudo systemctl reload sshd    # after copying ssh/
   ```

4. Reissue certificates one name at a time, matching the existing `live/`
   layout — `letsencrypt/` here holds renewal *configuration* only, never keys:

   ```bash
   for d in abhrankan.duckdns.org cockpit.abhrankan.duckdns.org \
            status.abhrankan.duckdns.org uptime.abhrankan.duckdns.org \
            forensic.dpdns.org pixel.forensic.dpdns.org; do
     sudo certbot certonly --nginx -d "$d"
   done
   ```

5. Verify: `curl -fsS https://pixel.forensic.dpdns.org/api/health`, then check
   the UptimeRobot monitors recover.

## Refresh

Run `scripts/collect-host-config.sh` on the host, then replace the trees here
with its output. The script re-execs under `sudo`, skips secret paths, and
prints a scan of anything that looks credential-like before you commit.

Enable the commit guard once per clone:

```bash
git config core.hooksPath .githooks
```

`.githooks/pre-commit` rejects sensitive filenames and scans staged text for
private keys, AWS/GitHub/Slack tokens, URL credentials, and htpasswd hashes.
Bypass with `--no-verify` only after checking the hit by hand.

## Validation

CI checks shell syntax, parses the DLM policy JSON, and runs `nginx -t` against
`nginx.conf` plus every vhost using generated stub certificates and htpasswd
files, so a broken refresh fails here rather than on the host.

## License

MIT — see [LICENSE](LICENSE).
