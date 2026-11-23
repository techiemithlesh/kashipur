#!/usr/bin/env bash
# Build and roll out a git revision on the VPS. Run as the deploy user in /opt/swm.
#   deploy/scripts/deploy.sh                 # deploy latest origin/main
#   deploy/scripts/deploy.sh <git-sha|tag>   # deploy (or roll back to) a specific revision
#   RUN_MIGRATIONS=0 deploy/scripts/deploy.sh   # skip `artisan migrate`
#
# Images are tagged with the commit SHA, so the previous images stay available for rollback.
set -euo pipefail

cd "$(dirname "$0")/../.."
REF="${1:-origin/main}"

git fetch --prune origin
git checkout --detach "$REF"
# Re-exec from the checked-out revision so this script itself is the deployed version.
if [ -z "${SWM_DEPLOY_REEXEC:-}" ]; then
  SWM_DEPLOY_REEXEC=1 exec "$0" "$@"
fi

source deploy/scripts/lib.sh --env-file .env.production
[ "$(stat -c %a .env.production)" = "600" ] || chmod 600 .env.production

export IMAGE_TAG
IMAGE_TAG="$(git rev-parse --short=12 HEAD)"
echo "==> Deploying $(git log -1 --format='%h %s') as tag $IMAGE_TAG"

compose build --pull
compose up -d --wait --remove-orphans

if [ "${RUN_MIGRATIONS:-1}" = "1" ]; then
  echo "==> Migrations"
  compose exec -T backend php artisan migrate --force --no-interaction
fi

# Queue workers hold the old code in memory until restarted.
compose exec -T backend php artisan queue:restart >/dev/null

echo "==> Smoke test"
DOMAIN="$(env_value DOMAIN)"
curl -fsS -o /dev/null --retry 5 --retry-delay 3 --retry-all-errors "https://${DOMAIN}/" && echo "    https://${DOMAIN}/ OK"
curl -fsS -o /dev/null --retry 3 --retry-delay 3 --retry-all-errors -X POST "https://${DOMAIN}/api/fyear/list" && echo "    API OK"

echo "$IMAGE_TAG $(date -Is)" >> .deploy-history
# Keep the 5 most recent image tags per service for rollback; remove older ones.
for repo in swm-backend swm-frontend; do
  docker image ls "$repo" --format '{{.CreatedAt}}\t{{.Repository}}:{{.Tag}}' \
    | sort -r | tail -n +6 | cut -f2 | xargs -r docker image rm >/dev/null 2>&1 || true
done
docker image prune -f >/dev/null
echo "==> Done: $IMAGE_TAG"
