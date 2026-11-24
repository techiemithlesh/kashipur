#!/bin/sh
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repository_root"

if [ "$#" -ne 1 ]; then
    echo >&2 "Usage: deploy/scripts/deploy.sh <40-character-commit-sha>"
    exit 2
fi

commit=$1
case "$commit" in
    *[!0123456789abcdef]*|'')
        echo >&2 "The deployment ref must be a lowercase Git commit SHA"
        exit 2
        ;;
esac
if [ "${#commit}" -ne 40 ]; then
    echo >&2 "The deployment ref must be a full 40-character commit SHA"
    exit 2
fi

if [ ! -f .env.production ]; then
    echo >&2 "Missing .env.production; copy .env.production.example and configure production values first"
    exit 1
fi
chmod 600 .env.production

read_env() {
    awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); value = $0 } END { print value }' .env.production
}

require_configured_value() {
    key=$1
    value=$(read_env "$key")
    case "$value" in
        ""|*replace_with*|*example.com*)
            echo >&2 "Configure $key in .env.production before deploying"
            exit 1
            ;;
    esac
}

for key in \
    APP_KEY \
    REDIS_PASSWORD \
    DB_DATABASE \
    DB_USERNAME \
    DB_PASSWORD \
    DB_READ_DATABASE \
    DB_READ_USERNAME \
    DB_READ_PASSWORD \
    DB_CONSUMER_DATABASE \
    DB_CONSUMER_USERNAME \
    DB_CONSUMER_PASSWORD \
    DB_CONSUMER_READ_DATABASE \
    DB_CONSUMER_READ_USERNAME \
    DB_CONSUMER_READ_PASSWORD \
    REVERB_APP_KEY \
    REVERB_APP_SECRET \
    ACME_EMAIL
do
    require_configured_value "$key"
done

if [ -n "$(git status --porcelain)" ]; then
    echo >&2 "The deployment checkout has local changes; commit or safely preserve them before deploying"
    exit 1
fi

git fetch --no-tags origin "$commit"
git cat-file -e "$commit^{commit}"
git checkout --detach "$commit"

data_root=$(read_env SWM_DATA_ROOT)
if [ -z "$data_root" ]; then
    data_root=/data/swm
fi
for path in "$data_root/public" "$data_root/private"; do
    if [ ! -d "$path" ]; then
        echo >&2 "Missing persistent storage directory: $path"
        echo >&2 "Run sudo deploy/scripts/prepare-host.sh before the first deployment"
        exit 1
    fi
done

export SWM_ENV_FILE=.env.production
docker compose --env-file .env.production config -q
docker compose --env-file .env.production up \
    --detach \
    --build \
    --remove-orphans \
    --wait \
    --wait-timeout 900

api_domain=$(read_env API_DOMAIN)
curl --fail --silent --show-error --retry 12 --retry-delay 5 --retry-connrefused \
    --output /dev/null "https://${api_domain}/up"
curl --fail --silent --show-error --retry 12 --retry-delay 5 --retry-connrefused \
    --output /dev/null "https://$(read_env DOMAIN)/"

docker compose --env-file .env.production ps
echo "Deployment of $commit completed. Database migrations were not run."

