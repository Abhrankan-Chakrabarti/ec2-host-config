# ec2-host-config

[![Config CI](https://github.com/Abhrankan-Chakrabarti/ec2-host-config/actions/workflows/ci.yml/badge.svg)](https://github.com/Abhrankan-Chakrabarti/ec2-host-config/actions/workflows/ci.yml)

Sanitized configuration snapshot for the personal-services EC2 instance
(`i-0da26b37e9f8a0657`, AL2023, arm64). Public repo: contains hostnames and
paths, never credentials. Kept public on purpose so it stays recoverable
without access to the owner's account.

## Layout

| Path | Source on host |
| --- | --- |
| `nginx/` | `/etc/nginx/nginx.conf`, `/etc/nginx/conf.d/`, `/etc/nginx/stream.d/` |
| `backup/` | EBS Data Lifecycle Manager policy JSON (applied via AWS CLI) |
| `monitoring/` | AWS API, not on host: CloudWatch burst-credit alarms and SNS topic |
| `ssh/` | `/etc/ssh/sshd_config`, `/etc/ssh/sshd_config.d/` |
| `fail2ban/` | `/etc/fail2ban/jail.local`, `jail.d/`, `fail2ban.conf` |
| `journald/` | `/etc/systemd/journald.conf.d/` |
| `dnf/` | `/etc/dnf/automatic.conf` |
| `systemd/` | `/etc/systemd/system/*.service`, `*.socket`, `*.timer`, and `*.d/*.conf` (host-local only) |
| `letsencrypt/` | `renewal/*.conf`, `cli.ini`, `options-ssl-nginx.conf` (no keys) |
| `scripts/` | `/usr/local/bin/update-all`, `/usr/local/bin/quartz-oracle-heartbeat`, collection helper |
| `tor-hidden-service/` | `~/tor-hidden-service-docker/` compose project; onion keys live in its `tor-hidden-service-docker_tor-data` volume |
| `_meta/` | generated inventories: crontabs, enabled services/sockets/timers |

## Never committed

- `/etc/pixel-forensics.env`, `/etc/quartz-oracle.env` (application secrets)
- `/etc/quartz-oracle-heartbeat.env` (Uptime Kuma push token)
- `/etc/nginx/*.htpasswd` (password hashes)
- `/etc/letsencrypt/archive/`, `live/`, `accounts/` (TLS private keys)
- `/etc/ssh/ssh_host_*` (host private keys)
- `tor-hidden-service-docker_tor-data` Docker volume (onion service private keys)
- AWS credentials, `.pem` files

## Restore

Two cases: putting files back on a live host, or rebuilding the host.

`v1.2.8` is the known-good baseline. If this repo is lost or rewritten, download
the release archive (`Source code (zip)`) from the Releases page rather than
cloning `main`.

### Config onto a live host

Copy each tree back to its source path with `install -D -m 0644`. Drop-in
trees are not covered by copying the flat units, so install them explicitly
(`cockpit.socket.d/override.conf` pins the socket to loopback):

```bash
sudo install -D -m 0644 systemd/cockpit.socket.d/override.conf /etc/systemd/system/cockpit.socket.d/override.conf
sudo install -D -m 0644 systemd/dnf-automatic-install.timer.d/time.conf /etc/systemd/system/dnf-automatic-install.timer.d/time.conf
sudo install -D -m 0644 systemd/dnf-automatic-install.service.d/autoreboot.conf /etc/systemd/system/dnf-automatic-install.service.d/autoreboot.conf
sudo install -D -m 0644 systemd/quartz-oracle.service.d/bind.conf /etc/systemd/system/quartz-oracle.service.d/bind.conf
sudo install -D -m 0644 systemd/quartz-oracle.service.d/hardening.conf /etc/systemd/system/quartz-oracle.service.d/hardening.conf
```

then:

```bash
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl daemon-reload
sudo systemctl restart pixel-forensics quartz-oracle lab-api crypto-lab abhrankan-status
```

### Tor hidden service

The compose project is vendored under `tor-hidden-service/` (upstream
[hundehausen/tor-hidden-service-docker](https://github.com/hundehausen/tor-hidden-service-docker),
MIT). Its compose file pins `name: tor-hidden-service-docker`, so it keeps
using the existing `tor-hidden-service-docker_tor-data` volume regardless of
where the repo is cloned. Restore it with:

```bash
mkdir -p ~/tor-hidden-service-docker
cp -a tor-hidden-service/. ~/tor-hidden-service-docker/
cd ~/tor-hidden-service-docker
docker compose up -d --build
```

Both services run with `restart: unless-stopped`, so they return when Docker
starts. `example-site/` mirrors `abhrankan.github.io`'s `index.html`; copy the
page over when it changes. The onion keys are not in this repo: restoring only
from the release archive generates a new onion address, while an EBS snapshot
preserves the volume.

### HTTP hardening

The vhosts are not stock: `nginx.conf` sets `server_tokens off` globally and
enables gzip for CSS/JS/JSON/SVG, including proxied responses, and every
`listen 443 ssl` block uses `http2 on;` — syntax that needs nginx 1.25.1 or
newer (the host runs 1.30.x; check `nginx -v` on a fresh build before trusting
the reload).

All HTTPS vhosts advertise `Strict-Transport-Security`,
`X-Content-Type-Options: nosniff`, `X-Frame-Options`, `Referrer-Policy` and
`Permissions-Policy`, declared once at server level so they inherit into every
location. `X-Frame-Options` is `DENY` except on cockpit, which must stay
`SAMEORIGIN` (Cockpit frames its own pages) with `Referrer-Policy: no-referrer`;
that vhost also `proxy_hide_header`s the upstream copies of HSTS, nosniff, XFO
and Referrer-Policy, because a second, conflicting `X-Frame-Options` makes
browsers fall back to `deny` and breaks Cockpit's shell. Status additionally
keeps `X-Robots-Tag` and `Cache-Control: no-store`; only the abhrankan vhost
serves filesystem assets,
so only it has the nested `expires 30d` rule. Cockpit's `gzip off` and the
Cockpit/Kuma asset cache headers are intentional — do not add filesystem
`expires` rules to proxied vhosts, they would 404 the apps' own assets.

After applying, check negotiation and headers (the three private vhosts answer
401, which still carries the `always` headers):

```bash
for host in status cockpit uptime; do
  echo | openssl s_client -alpn h2 -connect "$host.abhrankan.duckdns.org:443" \
    -servername "$host.abhrankan.duckdns.org" 2>/dev/null | grep 'ALPN protocol'
done
sudo nginx -T | grep -c 'http2 on'    # 5 with every vhost enabled
curl -skI https://uptime.abhrankan.duckdns.org/ | grep -iE 'strict-transport|x-content-type|x-frame|referrer|permissions'
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
   `/etc/quartz-oracle.env`, `/etc/quartz-oracle-heartbeat.env`, and
   `/etc/nginx/{school,status,cockpit}.htpasswd` (`htpasswd -B` per user).

3. Clone this repo and apply the trees from the Layout table, then run the
   live-host commands above. `nginx.conf` loads the `stream{}` block, so the
   module package is required on a fresh host:

   ```bash
   sudo dnf install -y nginx-mod-stream
   sudo install -D -m 0644 nginx/stream.d/quartz-oracle.conf /etc/nginx/stream.d/quartz-oracle.conf
   ```

   Install the scripts with their mode intact:

   ```bash
   sudo install -m 0755 scripts/update-all /usr/local/bin/update-all
   sudo install -m 0755 scripts/quartz-oracle-heartbeat /usr/local/bin/quartz-oracle-heartbeat
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

5. Restore the [Tor hidden service](#tor-hidden-service) compose project, then
   verify: `curl -fsS https://pixel.forensic.dpdns.org/api/health`, run the
   [HTTP hardening](#http-hardening) checks, then check that the UptimeRobot
   monitors recover. Recreate the CloudWatch burst-credit alarms
   (see [Burst-credit alarms](#burst-credit-alarms)); they live in the account,
   not on the volume.

## Refresh

Run `scripts/collect-host-config.sh` on the host, then replace the trees here
with its output. The script re-execs under `sudo`, skips secret paths, and
prints a scan of anything that looks credential-like before you commit. The
Tor project lives outside `/etc`, so it is not in the collector output; update
`tor-hidden-service/` by hand from `~/tor-hidden-service-docker`.

Enable the commit guard once per clone:

```bash
git config core.hooksPath .githooks
```

`.githooks/pre-commit` rejects sensitive filenames and scans staged text for
private keys, AWS/GitHub/Slack tokens, URL credentials, and htpasswd hashes.
Bypass with `--no-verify` only after checking the hit by hand.

## Validation

CI checks shell syntax (including the alarm setup script), parses the DLM
policy JSON, and runs `nginx -t` against `nginx.conf` plus every vhost using
generated stub certificates and htpasswd files, so a broken refresh fails here
rather than on the host.

## Monitoring

`quartz-oracle-heartbeat` connects to the oracle's loopback upstream, sends one
`0a` query, and requires a numeric timing reply before pushing `up` to Uptime
Kuma. A TCP port check cannot do this: nginx accepts `:9998` even with the
oracle dead, and the kernel backlog completes handshakes while the serial
server is busy.

Install the script and units, then create a **Push** monitor in Uptime Kuma
(interval 300s, retries 2) and put its URL in the env file:

```bash
sudo install -m 0755 scripts/quartz-oracle-heartbeat /usr/local/bin/
sudo install -m 0644 systemd/quartz-oracle-heartbeat.{service,timer} /etc/systemd/system/
sudo install -m 0600 /dev/null /etc/quartz-oracle-heartbeat.env
sudo vi /etc/quartz-oracle-heartbeat.env   # KUMA_PUSH_URL=http://127.0.0.1:3001/api/push/<token>
sudo systemctl daemon-reload
sudo systemctl enable --now quartz-oracle-heartbeat.timer
```

When a player holds the serial oracle, the heartbeat times out but stays
silent rather than pushing `down`, so a long solve does not page anyone; the
monitor's own staleness rule decides. Run it by hand to check: exit 0 means
answered, exit 1 means unverified or dead.

### Burst-credit alarms

`t4g.micro` burst credits are invisible to `cpu.stat`, so a sustained burn shows
up as throttling rather than anything the host can watch. The instance runs in
`unlimited` credit mode, so `monitoring/setup-cpucredit-alarms.sh` creates two
alarms on the `ec2-cpucredit-alerts` SNS topic:

- `ec2-cpucreditbalance-low` — `CPUCreditBalance` minimum below 30 for 15
  minutes. The instance earns 12 credits/hour and caps at 288, so this fires
  roughly five hours into sustained 100% CPU, before throttling starts.
- `ec2-cpusurplus-charged` — `CPUSurplusCreditsCharged` above 0 in any 5-minute
  period. This is the money signal: usage above the 20% baseline that is not
  repaid becomes billable surplus.

The script is idempotent and takes the email as an argument, never as committed
text; the subscription must be confirmed from the AWS email before it delivers.
Missing datapoints (stopped instance) are treated as `notBreaching`, and
`INSTANCE_ID` overrides the default when the instance is replaced.

```bash
ALERT_EMAIL=you@example.com monitoring/setup-cpucredit-alarms.sh
```

## License

MIT — see [LICENSE](LICENSE).
