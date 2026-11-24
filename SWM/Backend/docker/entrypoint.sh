#!/bin/sh
# Warms Laravel's caches from the container's environment before the main process starts.
# Runs for php-fpm (backend), queue:work and reverb:start; all share the same image.
set -e

cd /var/www/html

run_artisan() {
    if [ "$(id -u)" = "0" ]; then
        su -s /bin/sh www-data -c "php artisan $*"
    else
        php artisan "$@"
    fi
}

# Upload folders live on volumes that may predate a new folder; public/* symlinks point here.
if [ "$(id -u)" = "0" ]; then
    mkdir -p \
        storage/app/public/user/img storage/app/public/user/signature \
        storage/app/public/driver/img storage/app/public/Uploads/UlbOfficers \
        storage/app/public/documents \
        storage/app/private/Uploads/SwmTranDeactivation storage/app/private/Uploads/SwmDeactivation
    chown -R www-data:www-data storage/app/public storage/app/private
fi

if [ "${APP_ENV:-production}" = "production" ]; then
    run_artisan config:cache >/dev/null
    run_artisan route:cache >/dev/null
    run_artisan event:cache >/dev/null
    # Compiled views live on a shared volume; only the web container writes them.
    if [ "$1" = "php-fpm" ]; then
        run_artisan view:cache >/dev/null
    fi
else
    run_artisan optimize:clear >/dev/null
fi

exec docker-php-entrypoint "$@"
