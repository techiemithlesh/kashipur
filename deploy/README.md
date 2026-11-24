# Production deployment

This deployment runs the SWM frontend, Laravel PHP-FPM backend, Nginx ingress, Redis, queue worker, scheduler, Reverb, and Certbot with Docker Compose. PostgreSQL remains installed directly on the VPS. Public and private uploads persist in `/data/swm`.

## Local run and test

Run these commands from the repository root. The local override exposes the frontend directly on port `8080` and does not start the production TLS stack.

```powershell
# 1. Create writable persistent upload directories.
New-Item -ItemType Directory -Force .local-data\public,.local-data\private | Out-Null

# 2. Validate configuration.
docker compose --env-file .env.docker -f docker-compose.yml -f docker-compose.local.yml config -q

# 3. Build and start Redis, PHP-FPM, frontend, Reverb, queue, and scheduler.
docker compose --env-file .env.docker -f docker-compose.yml -f docker-compose.local.yml up -d --build

# 4. Wait until the containers report healthy/running.
docker compose --env-file .env.docker -f docker-compose.yml -f docker-compose.local.yml ps

# 5. Test the frontend.
curl.exe --fail --show-error http://localhost:8080/

# 6. Test the Laravel API health endpoint.
curl.exe --fail --show-error http://localhost:8080/up

# 7. Inspect application logs if a test fails.
docker compose --env-file .env.docker -f docker-compose.yml -f docker-compose.local.yml logs --tail=100 backend frontend reverb queue scheduler redis

# 8. Stop the local stack when finished.
docker compose --env-file .env.docker -f docker-compose.yml -f docker-compose.local.yml down
```

On Linux, replace the PowerShell directory command with `mkdir -p .local-data/public .local-data/private`.

## DNS and firewall

Before requesting a certificate, create these DNS A records:

| Name | Address |
| --- | --- |
| `kashipurcontrolcentre.com` | `189.72.177.80` |
| `api.kashipurcontrolcentre.com` | `189.72.177.80` |

Allow inbound SSH, TCP 80, and TCP 443 in the Hostinger firewall and Ubuntu firewall. Do not expose PostgreSQL (5432), Redis (6379), PHP-FPM (9000), or Reverb (8080) publicly.

## VPS preparation

Install Docker Engine and the Docker Compose plugin on Ubuntu 26.04, then create a dedicated deployment account with Docker access. Clone this repository to `/opt/swm`; the account used by GitHub Actions must be able to fetch from the repository and run Docker Compose there.

Create persistent storage directories once, preserving any existing data:

```sh
cd /opt/swm
sudo sh deploy/scripts/prepare-host.sh /data/swm
```

The script applies PHP UID/GID 33 ownership and writable directory/file modes across the complete public and private trees. This keeps files and directories created by application code manageable regardless of upload path. It copies bundled `UlbLog` files only when a destination file does not already exist.

Create the server-only environment file and restrict its permissions:

```sh
cd /opt/swm
cp .env.production.example .env.production
chmod 600 .env.production
```

Edit `.env.production` and replace all placeholders. The configured database names/user are `db_system`, `db_swm_consumer`, and `swm_user`; enter the PostgreSQL password in the `DB_PASSWORD`, `DB_READ_PASSWORD`, `DB_CONSUMER_PASSWORD`, and `DB_CONSUMER_READ_PASSWORD` fields in this server-only file. Set a valid `ACME_EMAIL`, a Laravel key, a strong unique Redis password, and Reverb credentials. Do not commit `.env.production` or put database passwords in tracked examples.

Generate a Redis password on the VPS and place it after `REDIS_PASSWORD=` in `.env.production` (do not share or commit it):

```sh
openssl rand -hex 32
nano .env.production
```

Compose requires every deployment value to be present even when starting only selected services. Validate the complete file before starting containers:

```sh
docker compose --env-file .env.production config -q
```

Generate a Laravel key after building the backend image, without writing it into the repository:

```sh
docker compose --env-file .env.production build backend
docker compose --env-file .env.production run --rm --no-deps backend php artisan key:generate --show
```

Put the generated `base64:...` value into `APP_KEY`. Keep the same key across deployments; changing it invalidates encrypted application data. The example Reverb app ID/key/secret may be replaced with random values, but the key and secret must be consistent between backend and frontend build settings.

The frontend API and Reverb endpoints are build-time values. Keep `VITE_REACT_APP_BACKEND_API=https://api.kashipurcontrolcentre.com`, `API_DOMAIN=api.kashipurcontrolcentre.com`, and the HTTPS Reverb port/scheme settings aligned.

## Host PostgreSQL

The Compose services use `host.docker.internal` via Docker's `host-gateway` mapping. PostgreSQL must accept TCP connections on the host-gateway address and have `pg_hba.conf` entries for the Compose network's subnet, limited to the required existing databases/users and `scram-sha-256` authentication. Do not bind PostgreSQL to a public interface or allow public 5432 access.

The Compose network name depends on the Compose project name. Since this checkout is in `/opt/swm/kashipur`, the default network is `kashipur_default` unless `COMPOSE_PROJECT_NAME` is set. Inspect the actual network subnet and the host-gateway address on the VPS before changing PostgreSQL configuration. PostgreSQL versions and config paths can differ:

```sh
docker network ls
docker network inspect kashipur_default
docker compose --env-file .env.production exec backend getent hosts host.docker.internal
```

Apply the server-specific `listen_addresses` and `pg_hba.conf` updates, reload PostgreSQL, and verify connectivity from a backend container before production traffic. The current Laravel database configuration exposes the main `pgsql` connection to `db_system` and the consumer `pgsql_swm` connection to `db_swm_consumer`, both using `swm_user`. Important: the database-creation command supplied for the VPS names the second database `db_swm`, while the selected backend `.env` value is `db_swm_consumer`. Verify the actual database list on the VPS and reconcile this mismatch before deploying; the deployment will not create, rename, or migrate either database automatically. The old backend example also mentions property/water/trade variables that are not configured as connections in `config/database.php`; confirm whether any separate databases are still required before proceeding.

Back up existing databases and confirm the migration plan before running any migration. The deployment script deliberately does not run migrations or create/reset databases. If migrations are approved, use the backend container during a maintenance window:

```sh
docker compose --env-file .env.production exec backend php artisan migrate --force
```

## Start and update the application

Once DNS, PostgreSQL access, storage, and `.env.production` are ready, run the production start as separate steps:

```sh
cd /opt/swm

# 1. Install/confirm Docker Engine and the Compose plugin.
docker --version
docker compose version

# 2. Validate all required production environment values.
docker compose --env-file .env.production config -q

# 3. Prepare persistent public/private upload storage.
sudo sh deploy/scripts/prepare-host.sh /data/swm

# 4. Build all application images.
docker compose --env-file .env.production build

# 5. Start Redis and the application services.
docker compose --env-file .env.production up -d --build --wait --wait-timeout 900

# 6. Wait for and verify the certificate request.
docker compose --env-file .env.production ps certbot

# 7. Verify the frontend and API health endpoints.
curl --fail --show-error --retry 12 --retry-delay 5 --retry-connrefused https://kashipurcontrolcentre.com/
curl --fail --show-error --retry 12 --retry-delay 5 --retry-connrefused https://api.kashipurcontrolcentre.com/up

# 8. Inspect status and logs after startup.
docker compose --env-file .env.production ps
docker compose --env-file .env.production logs --tail=100 backend frontend reverb queue scheduler nginx certbot
```

The first start serves no application traffic over HTTP until Certbot has obtained certificates for both hostnames. Nginx then enables HTTPS and redirects HTTP to HTTPS. Ensure DNS resolves to this VPS and ports 80/443 are reachable before starting. Certbot renews certificates automatically; the Nginx container watches the certificate and reloads its configuration after issuance/renewal.

For a GitHub Actions deployment, configure a `production` environment and the secrets `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, and `VPS_KNOWN_HOSTS`. The VPS user needs repository fetch access and Docker Compose permission in `/opt/swm`. The manual **Deploy** workflow checks out the selected commit and invokes `sh ./deploy/scripts/deploy.sh`; that script validates configuration, waits for healthy services/certificates, smoke-checks the frontend and `/up`, and never migrates the database.

Useful operations:

```sh
docker compose --env-file .env.production ps
docker compose --env-file .env.production logs -f backend queue scheduler reverb nginx certbot
docker compose --env-file .env.production down
```

`down` does not remove named volumes. Do not add `--volumes` unless intentionally deleting Redis and certificate state. For code rollback, redeploy a previous commit through the workflow; database rollback is separate and requires a reviewed backup/restore plan.

## Backups and validation

Back up PostgreSQL with `pg_dump` for each database and back up `/data/swm` (including both public and private files) to storage outside this VPS. Test restores periodically. Redis uses an AOF-backed named volume; it is operational state, not a substitute for PostgreSQL or document backups. Set a production SMTP mailer and SMS provider credentials before relying on password-reset/OTP delivery; the safe example uses log mail and test SMS settings.

CI validates Compose interpolation, shell scripts, Nginx templates, and backend/frontend/ingress image builds. Before exposing the host, verify HTTPS for both names, API `/up`, CORS from the frontend origin, Reverb WebSockets, public document access, private document authorization, and a queue/scheduler smoke test.

