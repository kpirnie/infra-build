# PHP_VERSION is the primary matrix variable; GH Actions drives 8.2 – 8.5
ARG PHP_VERSION=8.2

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 – Builder
# Compiles all extensions against the matching PHP version.
# Nothing from this stage lands in the final image.
# ─────────────────────────────────────────────────────────────────────────────
FROM docker.io/library/php:${PHP_VERSION}-fpm-alpine AS builder

# Re-declare so the value is available inside this stage
ARG PHP_VERSION

# ── Build-time system dependencies ───────────────────────────────────────────
RUN apk add --no-cache \
    autoconf          \
    build-base        \
    curl-dev          \
    freetype-dev      \
    gettext-dev       \
    icu-dev           \
    imagemagick-dev   \
    libjpeg-turbo-dev \
    libpng-dev        \
    libpq-dev         \
    libsodium-dev     \
    libwebp-dev       \
    libxml2-dev       \
    libxslt-dev       \
    yaml-dev       \
    libzip-dev        \
    linux-headers     \
    tidyhtml-dev      \
    util-linux-dev    \
    zlib-dev

# ── Core extensions (from PHP source tree) ───────────────────────────────────
# sodium is compiled into the PHP binary in 8.x – do not list here
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg     \
    --with-webp  && \
    docker-php-ext-install -j"$(nproc)" \
    bcmath    \
    calendar  \
    exif      \
    gd        \
    gettext   \
    intl      \
    mysqli    \
    pcntl     \
    pdo_mysql \
    pdo_pgsql \
    pgsql     \
    sockets   \
    tidy      \
    xsl       \
    zip

# ── PECL extensions ───────────────────────────────────────────────────────────
# igbinary + msgpack must be installed before redis so redis links against them

RUN pecl install igbinary && \
    docker-php-ext-enable igbinary

RUN pecl install msgpack && \
    docker-php-ext-enable msgpack

RUN pecl install apcu && \
    docker-php-ext-enable apcu

RUN pecl install imagick && \
    docker-php-ext-enable imagick

RUN pecl install uuid && \
    docker-php-ext-enable uuid

RUN pecl install yaml && \
    docker-php-ext-enable yaml

# redis: compiled with igbinary + msgpack serializer support
RUN pecl install \
    --configureoptions 'enable-redis-igbinary="yes" enable-redis-msgpack="yes"' \
    redis && \
    docker-php-ext-enable redis

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 – Runtime
# Fresh copy of the matching PHP-FPM Alpine image; no build toolchain.
# www-data (UID 82 / GID 82) is pre-created in the official PHP Alpine images.
# FPM master runs as root, worker pool drops to www-data via www.conf.
# ─────────────────────────────────────────────────────────────────────────────
ARG PHP_VERSION=8.2
FROM docker.io/library/php:${PHP_VERSION}-fpm-alpine

# ── OCI labels (injected by GH Actions at build time) ────────────────────────
ARG PHP_VERSION
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.created="${BUILD_DATE}"                  \
    org.opencontainers.image.revision="${VCS_REF}"                    \
    org.opencontainers.image.source="https://github.com/kpirnie/infra-build" \
    org.opencontainers.image.description="PHP ${PHP_VERSION}-FPM · apcu · bcmath · calendar · exif · gd · imagick · igbinary · intl · msgpack · mysqli · opcache · pcntl · pdo_mysql · pdo_pgsql · pgsql · redis · sodium · sockets · tidy · uuid · xsl · yaml · zip · WP-CLI · Composer"

# ── Runtime-only system dependencies ─────────────────────────────────────────
RUN apk add --no-cache \
    ca-certificates \
    freetype        \
    gettext-libs    \
    icu-libs        \
    imagemagick     \
    libjpeg-turbo   \
    libpng          \
    libpq           \
    libsodium       \
    libwebp         \
    libxslt         \
    libzip          \
    yaml            \
    tidyhtml        \
    util-linux      \
    zlib

# ── Copy compiled extensions + conf.d ini snippets from builder ───────────────
COPY --from=builder /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=builder /usr/local/etc/php/conf.d     /usr/local/etc/php/conf.d

# ── WP-CLI (verified via upstream sha512 checksum) ───────────────────────────
RUN curl -fsSL \
    https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /tmp/wp-cli.phar && \
    curl -fsSL \
    https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar.sha512 \
    -o /tmp/wp-cli.phar.sha512 && \
    echo "$(cat /tmp/wp-cli.phar.sha512)  /tmp/wp-cli.phar" | sha512sum -c - && \
    install -m 0755 /tmp/wp-cli.phar /usr/local/bin/wp && \
    rm /tmp/wp-cli.phar /tmp/wp-cli.phar.sha512

# ── Composer (verified via upstream installer.sig sha384 checksum) ────────────
RUN set -e && \
    EXPECTED_SIG=$(curl -fsSL https://composer.github.io/installer.sig) && \
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php && \
    php -r "if (hash_file('sha384', '/tmp/composer-setup.php') !== '${EXPECTED_SIG}') { fwrite(STDERR, 'Composer installer corrupt\n'); exit(1); }" && \
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
    rm /tmp/composer-setup.php

# ── Overlay our minimal configs ───────────────────────────────────────────────
# php.ini overlays the base; pool config replaces www.conf from the base image.
# Anything not covered here should be volume-mounted into:
#   /usr/local/etc/php/conf.d/       (php.ini overrides)
#   /usr/local/etc/php-fpm.d/        (pool overrides)
COPY conf/php.ini  /usr/local/etc/php/php.ini
COPY conf/www.conf /usr/local/etc/php-fpm.d/www.conf

# ── Runtime directories and hardening ─────────────────────────────────────────
RUN mkdir -p /var/log/php-fpm && \
    chown -R www-data:www-data /var/log/php-fpm && \
    find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | \
    xargs chmod a-s 2>/dev/null || true

# ── Expose FPM port; master listens on 9000, workers drop to www-data
EXPOSE 9000

CMD ["php-fpm"]