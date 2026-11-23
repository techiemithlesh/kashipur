#!/usr/bin/env bash
# Shared helpers. Source from the repo root: `source deploy/scripts/lib.sh "$@"`.
# Picks the env file and compose files for the environment:
#   production (default when .env.production exists): base + docker-compose.prod.yml
#   otherwise: base compose with .env.docker (local)

ENV_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$ENV_FILE" ]; then
  if [ -f .env.production ]; then ENV_FILE=.env.production; else ENV_FILE=.env.docker; fi
fi
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE" >&2; exit 1; }

COMPOSE_FILES=(-f docker-compose.yml)
if [ "$ENV_FILE" = ".env.production" ]; then
  COMPOSE_FILES+=(-f docker-compose.prod.yml)
fi

compose() {
  docker compose --env-file "$ENV_FILE" "${COMPOSE_FILES[@]}" "$@"
}

env_value() {
  { grep -E "^$1=" "$ENV_FILE" || true; } | tail -n1 | cut -d= -f2- | tr -d '"\r'
}
