<#
.SYNOPSIS
  Clones the local (pgAdmin) PostgreSQL databases into the Docker "db" service.

.DESCRIPTION
  1. pg_dump (custom format) of db_swm_master and db_swm_consumer from the local server.
  2. Wipes the public schema of the matching Docker databases.
  3. pg_restore into Docker with ownership remapped to the app roles from .env.docker
     (DB_USERNAME / DB_CONSUMER_USERNAME), so the app never runs as a superuser.

  The password is prompted for and kept only in this process's environment.
  Dumps go to docker/postgres/dumps (git-ignored). Re-running is safe: it replaces the Docker data.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\db\clone-local-to-docker.ps1
#>
param(
    [string]$SourceHost = "127.0.0.1",
    [int]$SourcePort = 5432,
    [string]$SourceUser = "postgres",
    [string]$MasterDb = "db_swm_master",
    [string]$ConsumerDb = "db_swm_consumer",
    [string]$PgBin = "C:\Program Files\PostgreSQL\17\bin",
    [switch]$SkipDump
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $root
$dumpDir = Join-Path $root "docker\postgres\dumps"
New-Item -ItemType Directory -Force $dumpDir | Out-Null
$compose = @("compose", "--env-file", ".env.docker")

if (-not $SkipDump) {
    $pgDump = Join-Path $PgBin "pg_dump.exe"
    if (-not (Test-Path $pgDump)) { throw "pg_dump not found at $pgDump (pass -PgBin)" }

    $secure = Read-Host "Password for local PostgreSQL user '$SourceUser'" -AsSecureString
    $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    try {
        foreach ($db in @($MasterDb, $ConsumerDb)) {
            $out = Join-Path $dumpDir "$db.dump"
            Write-Host "Dumping $db -> $out"
            & $pgDump -h $SourceHost -p $SourcePort -U $SourceUser -d $db -Fc --no-owner --no-acl -f $out
            if ($LASTEXITCODE -ne 0) { throw "pg_dump failed for $db" }
        }
    } finally {
        Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
    }
}

Write-Host "Ensuring Docker db is up..."
& docker @compose up -d --wait db
if ($LASTEXITCODE -ne 0) { throw "docker db did not become healthy" }

# Map each dump to the env var inside the db container that holds its owner role.
$targets = @(
    @{ Db = $MasterDb;   RoleVar = 'DB_USERNAME' },
    @{ Db = $ConsumerDb; RoleVar = 'DB_CONSUMER_USERNAME' }
)

foreach ($t in $targets) {
    $file = Join-Path $dumpDir "$($t.Db).dump"
    if (-not (Test-Path $file)) { throw "Missing dump $file" }
    Write-Host "Restoring $($t.Db)..."

    & docker @compose cp $file "db:/tmp/$($t.Db).dump"
    if ($LASTEXITCODE -ne 0) { throw "docker cp failed" }

    $sh = @"
set -e
role="`$$($t.RoleVar)"
psql -v ON_ERROR_STOP=1 -U "`$POSTGRES_USER" -d "$($t.Db)" -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public AUTHORIZATION \"`$role\";"
pg_restore -U "`$POSTGRES_USER" -d "$($t.Db)" --no-owner --no-acl --role="`$role" /tmp/$($t.Db).dump || echo "pg_restore reported warnings (see above)"
rm -f /tmp/$($t.Db).dump
psql -U "`$POSTGRES_USER" -d "$($t.Db)" -Atc "SELECT '$($t.Db): ' || count(*) || ' tables' FROM information_schema.tables WHERE table_schema='public'"
"@
    $sh -replace "`r", "" | & docker @compose exec -T db sh
    if ($LASTEXITCODE -ne 0) { throw "restore failed for $($t.Db)" }
}

Write-Host "Recreating master->consumer foreign tables (postgres_fdw)..."
$fdwSql = Join-Path $root "docker\postgres\fdw\consumer-fdw.sql"
& docker @compose cp $fdwSql "db:/tmp/consumer-fdw.sql"
$fdwSh = "psql -U `"`$POSTGRES_USER`" -d `"$ConsumerDb`" -f /tmp/consumer-fdw.sql && rm -f /tmp/consumer-fdw.sql"
& docker @compose exec -T db sh -c $fdwSh
if ($LASTEXITCODE -ne 0) { throw "FDW setup failed" }

Write-Host "Baselining Laravel migrations and applying newer ones..."
$baseSql = Join-Path $root "docker\postgres\baseline-migrations.sql"
& docker @compose cp $baseSql "db:/tmp/baseline-migrations.sql"
& docker @compose exec -T db sh -c "psql -q -U `"`$POSTGRES_USER`" -d `"$MasterDb`" -f /tmp/baseline-migrations.sql && rm -f /tmp/baseline-migrations.sql"
if ($LASTEXITCODE -ne 0) { throw "migration baseline failed" }
& docker @compose exec -T backend php artisan migrate --force --no-interaction
if ($LASTEXITCODE -ne 0) { throw "migrate failed" }

Write-Host "Clearing Laravel caches..."
& docker @compose exec -T backend php artisan optimize:clear | Out-Null
Write-Host "Done."
