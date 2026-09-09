FROM alpine:3.23 AS source

ARG FLUXCP_REF=98cd4b8fd83228c11b36fb3d097b8e0f7c105a8d
RUN apk add --no-cache git \
 && git clone https://github.com/rathena/FluxCP.git /fluxcp \
 && cd /fluxcp \
 && git checkout "${FLUXCP_REF}" \
 && rm -rf .git

FROM php:8.3-apache

RUN apt-get update \
 && apt-get install -y --no-install-recommends libfreetype6-dev libjpeg62-turbo-dev libpng-dev \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" gd pdo_mysql \
 && a2enmod rewrite \
 && rm -rf /var/lib/apt/lists/*

COPY --from=source --chown=www-data:www-data /fluxcp /var/www/html
COPY --chown=www-data:www-data application.php /var/www/html/config/import/application.php
COPY --chown=www-data:www-data servers.php /var/www/html/config/servers.php
RUN mkdir -p /var/www/html/data/logs /var/www/html/data/tmp \
 && chown -R www-data:www-data /var/www/html/data

EXPOSE 80
