#!/bin/sh
set -eu

: "${DOMAIN:?DOMAIN is required}"
: "${API_DOMAIN:?API_DOMAIN is required}"
: "${ACME_EMAIL:?ACME_EMAIL is required}"

certificate="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"

request_certificate() {
    certbot certonly \
        --non-interactive \
        --agree-tos \
        --no-eff-email \
        --email "$ACME_EMAIL" \
        --webroot \
        --webroot-path /var/www/certbot \
        --cert-name "$DOMAIN" \
        -d "$DOMAIN" \
        -d "$API_DOMAIN"
}

while [ ! -s "$certificate" ]; do
    if request_certificate; then
        break
    fi

    echo >&2 "Initial certificate request failed; retrying in five minutes"
    sleep 300
done

while :; do
    sleep 12h
    if ! certbot renew --webroot --webroot-path /var/www/certbot --quiet; then
        echo >&2 "Certificate renewal attempt failed; it will be retried in twelve hours"
    fi
done

