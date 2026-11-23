# SWM production runbook (Hostinger VPS)

```
Internet ──443/80──► Caddy (TLS, HSTS, HTTP/3) ──► frontend nginx ──► /        React build
                                                                  ├─► /api/*   PHP-FPM (Laravel)
                                                                  ├─► /app/*   Reverb WebSockets
                                                                  └─► uploads  shared volume
                      backend / queue / reverb ──► PostgreSQL 17, Redis   (internal network only)
Your PC (pgAdmin) ──SSH tunnel──► VPS 127.0.0.1:5432 ──► PostgreSQL       (never public)
```

Public ports: **22 (SSH, keys only), 80, 443**. Nothing else is reachable from the internet.

## 1. One-time server setup

1. **Hostinger hPanel → VPS:** Ubuntu 24.04. Add your SSH public key. In the VPS **Firewall**, allow
   only 22, 80, 443 (TCP) and 443 (UDP).
2. **DNS** (wherever the domain is managed): `A  swm.example.com → <VPS IP>` (and `www` if wanted).
   Wait until `nslookup swm.example.com` returns the VPS IP; Caddy needs it to get the certificate.
3. **Harden + install Docker** (as root, once):
   ```bash
   scp deploy/scripts/server-setup.sh root@<VPS IP>:/root/
   ssh root@<VPS IP> bash /root/server-setup.sh
   ```
   After this, root login and passwords are off. Use `ssh deploy@<VPS IP>`.
   (If you lock yourself out, Hostinger's browser console in hPanel still works.)
4. **Repository access** (on the VPS, as `deploy`):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/github_deploy -N ""
   cat ~/.ssh/github_deploy.pub    # GitHub repo → Settings → Deploy keys → add (read-only)
   printf 'Host github.com\n  IdentityFile ~/.ssh/github_deploy\n' >> ~/.ssh/config
   git clone git@github.com:techiemithlesh/kashipur.git /opt/swm
   ```
5. **Secrets:**
   ```bash
   cd /opt/swm
   cp .env.production.example .env.production && chmod 600 .env.production
   nano .env.production     # domain, email, all passwords/keys (openssl rand -base64 36)
   ```
   `APP_KEY`: generate after the first build with
   `docker run --rm swm-backend:<tag> php artisan key:generate --show`, or reuse the one from `.env.docker`.

## 2. Deploy

```bash
cd /opt/swm && deploy/scripts/deploy.sh            # latest main
deploy/scripts/deploy.sh <commit-sha>               # specific version / rollback
```
It checks out the revision, builds images tagged with the commit SHA, waits for health checks,
runs migrations, restarts queue workers and smoke-tests `https://DOMAIN`.
The 5 latest image tags are kept; `.deploy-history` lists what was deployed when.

From GitHub instead: **Actions → Deploy → Run workflow** (needs the secrets listed in
`.github/workflows/deploy.yml`, set on the `production` environment).

## 3. Database access with pgAdmin (SSH tunnel)

PostgreSQL listens only on the VPS's `127.0.0.1:5432`. In pgAdmin → *Register → Server*:

| Tab | Field | Value |
|---|---|---|
| Connection | Host | `127.0.0.1` |
| | Port | `5432` |
| | Username | `swm_bootstrap` (admin) or the app users from `.env.production` |
| SSH Tunnel | Use SSH tunneling | on |
| | Tunnel host / port | `<VPS IP>` / `22` |
| | Username | `deploy` |
| | Authentication | Identity file → your private key |

Command line equivalent: `ssh -N -L 5433:127.0.0.1:5432 deploy@<VPS IP>`, then connect to `localhost:5433`.

### Restore (first go-live, or from a backup)

1. In pgAdmin (connected as **`swm_bootstrap`**), restore into `db_swm_master` and `db_swm_consumer`:
   *Restore → Format: Custom*, **Data/Objects → Do not save: Owner, Privilege**, *Role name*: the
   app user for that database (`swm_master_user` / `swm_consumer_user`).
   Errors about `dblink`, `postgres_fdw`, foreign tables and event triggers are expected.
2. Then on the VPS, re-link the consumer DB to master and bring migrations up to date:
   ```bash
   cd /opt/swm && deploy/scripts/db-post-restore.sh
   ```

## 4. Backups

```bash
mkdir -p /opt/swm/backups && crontab -e   # as deploy, then add:
30 2 * * * /opt/swm/deploy/scripts/backup-db.sh >> /opt/swm/backups/backup.log 2>&1
```
Each night: both databases (`pg_dump -Fc`, verified) + uploaded files, with checksums, kept 14 days.
**Copy them off the server** regularly, e.g. from your PC:
`scp -r deploy@<VPS IP>:/opt/swm/backups/<date> D:\swm-backups\`. A backup that lives only on
the VPS is lost with the VPS. Test a restore every few months.

## 5. Day-to-day

```bash
cd /opt/swm
C="docker compose --env-file .env.production -f docker-compose.yml -f docker-compose.prod.yml"
$C ps                         # health
$C logs -f --tail 100 backend # logs (also: queue, reverb, caddy, frontend)
$C exec backend php artisan queue:failed
$C restart queue
```

## Notes

- The mobile app (`SWMAPK`) must point `WASTE_MANAGEMENT_BACKEND_API` at `https://DOMAIN`.
- Restrict the Google Maps key in Google Cloud Console (Android app + SHA-1, Maps APIs only).
- The schema is managed in pgAdmin; Laravel migrations are baselined by
  `docker/postgres/baseline-migrations.sql`, so `migrate --force` only runs genuinely new migrations.
