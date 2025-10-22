# =============================
# 1. Base Stage (common setup)
# =============================
FROM php:8.2-fpm AS base

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    locales \
    zip \
    jpegoptim optipng pngquant gifsicle \
    vim unzip git curl \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    libmagickwand-dev --no-install-recommends \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip \
    && pecl install imagick \
    && docker-php-ext-enable imagick \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
COPY --from=composer:2.6 /usr/bin/composer /usr/bin/composer

# Install dockerize (wait for db)
ARG DOCKERIZE_VERSION=v0.6.1
RUN if ! command -v dockerize >/dev/null 2>&1; then \
        curl -L https://github.com/jwilder/dockerize/releases/download/${DOCKERIZE_VERSION}/dockerize-linux-amd64-${DOCKERIZE_VERSION}.tar.gz \
        | tar -C /usr/local/bin -xzv; \
    fi

WORKDIR /var/www/html

# Copy composer files first for caching
COPY composer.json composer.lock ./

# =============================
# 2. Build Stage
# =============================
FROM base AS build

WORKDIR /var/www/html

# Copy full source code AFTER dependencies are installed
COPY . .

# Install PHP dependencies (no dev) – cached unless composer.json/lock changes
RUN composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist

# =============================
# 3. Development Stage
# =============================
FROM base AS dev

WORKDIR /var/www/html

# Copy full source
COPY . .

# Install PHP dependencies including dev (cached with composer files only)
RUN composer install --optimize-autoloader --no-interaction --prefer-dist

# Set permissions
RUN chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Copy entrypoint
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["entrypoint.sh"]

# Run php-fpm for dev
CMD ["php-fpm", "-F"]

# =============================
# 4. Production Stage
# =============================
FROM base AS prod

# Copy built application from build stage
COPY --from=build /var/www/html /var/www/html

# Copy example .env as actual .env
COPY .env.production.example /var/www/html/.env

# Set permissions
RUN chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Copy entrypoint
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["entrypoint.sh"]
CMD ["php-fpm", "-F"]
