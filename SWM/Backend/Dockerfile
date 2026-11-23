FROM php:8.3-fpm-bookworm

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

RUN apt-get update \
    && apt-get install -y --no-install-recommends $PHPIZE_DEPS libpq-dev \
    && apt-mark manual libpq5 \
    && docker-php-ext-install -j"$(nproc)" pdo_pgsql pcntl \
    && apt-get purge -y --auto-remove $PHPIZE_DEPS libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY composer.json composer.lock ./

RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip \
    && COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-dev \
        --no-interaction \
        --no-progress \
        --prefer-dist \
        --no-scripts \
        --no-autoloader \
    && apt-get purge -y --auto-remove unzip \
    && rm -rf /var/lib/apt/lists/*

COPY . .
COPY public/UlbLog ./storage/app/public/UlbLog

RUN mkdir -p \
        storage/app/public/user/img \
        storage/app/public/driver/img \
        storage/app/public/Uploads/UlbOfficers \
        storage/app/public/UlbLog \
        storage/app/private/user/signature \
        storage/app/private/Uploads/SwmTranDeactivation \
        storage/app/private/Uploads/SwmDeactivation \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs \
        bootstrap/cache \
        public/Uploads \
        user \
        driver \
        Uploads \
    && ln -s ../storage/app/public/user/img user/img \
    && ln -s ../storage/app/public/driver/img driver/img \
    && ln -s ../../storage/app/public/Uploads/UlbOfficers public/Uploads/UlbOfficers \
    && ln -s ../storage/app/private/user/signature user/signature \
    && ln -s ../storage/app/private/Uploads/SwmTranDeactivation Uploads/SwmTranDeactivation \
    && ln -s ../storage/app/private/Uploads/SwmDeactivation Uploads/SwmDeactivation \
    && COMPOSER_ALLOW_SUPERUSER=1 composer dump-autoload \
        --no-dev \
        --optimize \
        --no-interaction \
    && php artisan storage:link \
    && chown -R www-data:www-data \
        storage \
        bootstrap/cache \
        public/Uploads

COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/swm-entrypoint

EXPOSE 9000

ENTRYPOINT ["swm-entrypoint"]

CMD ["php-fpm"]