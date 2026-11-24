#!/bin/sh
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repository_root"

image=swm-nginx:validation
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

mkdir -p "$temporary_directory/certs/live/example.com"
openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout "$temporary_directory/certs/live/example.com/privkey.pem" \
    -out "$temporary_directory/certs/live/example.com/fullchain.pem" \
    -subj "/CN=example.com" >/dev/null 2>&1

docker build --file deploy/nginx/Dockerfile --tag "$image" deploy/nginx
docker run --rm \
    --env DOMAIN=example.com \
    --env API_DOMAIN=api.example.com \
    --volume "$temporary_directory/certs:/etc/letsencrypt:ro" \
    --entrypoint /bin/sh \
    "$image" \
    -ec '
        envsubst '\''${DOMAIN} ${API_DOMAIN}'\'' \
            < /etc/nginx/templates/http-redirect.conf.template \
            > /etc/nginx/conf.d/http.conf
        envsubst '\''${DOMAIN} ${API_DOMAIN}'\'' \
            < /etc/nginx/templates/tls.conf.template \
            > /etc/nginx/conf.d/tls.conf
        nginx -t
    '

