#!/bin/sh
set -eu

: "${DOMAIN:?DOMAIN is required}"
: "${API_DOMAIN:?API_DOMAIN is required}"

certificate="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
private_key="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

render_config() {
    if [ -s "$certificate" ] && [ -s "$private_key" ]; then
        envsubst "\${DOMAIN} \${API_DOMAIN}" \
            < /etc/nginx/templates/http-redirect.conf.template \
            > /etc/nginx/conf.d/http.conf
        envsubst "\${DOMAIN} \${API_DOMAIN}" \
            < /etc/nginx/templates/tls.conf.template \
            > /etc/nginx/conf.d/tls.conf
    else
        rm -f /etc/nginx/conf.d/tls.conf
        envsubst "\${DOMAIN} \${API_DOMAIN}" \
            < /etc/nginx/templates/http-bootstrap.conf.template \
            > /etc/nginx/conf.d/http.conf
    fi
}

certificate_fingerprint() {
    if [ -s "$certificate" ] && [ -s "$private_key" ]; then
        stat -c '%Y:%s' "$certificate"
    else
        printf 'missing\n'
    fi
}

render_config
nginx -t
nginx -g 'daemon off;' &
nginx_pid=$!

stop_nginx() {
    kill -TERM "$nginx_pid" 2>/dev/null || true
    wait "$nginx_pid" 2>/dev/null || true
}
trap stop_nginx INT TERM

last_fingerprint=$(certificate_fingerprint)
while kill -0 "$nginx_pid" 2>/dev/null; do
    sleep 15 &
    wait "$!" || true
    current_fingerprint=$(certificate_fingerprint)

    if [ "$current_fingerprint" != "$last_fingerprint" ]; then
        render_config
        if nginx -t && nginx -s reload; then
            last_fingerprint=$current_fingerprint
        else
            echo >&2 "Nginx could not reload after a certificate change"
        fi
    fi
done

wait "$nginx_pid"

