# Jenkins-AWS-CI-CD-Pipeline (Next.Js and Laravel)

## FE (NextJs) Multi-Stage ``Dockerfile``

```yaml
# =============================
# 1. Base Stage (common setup)
# =============================
FROM node:22.14-alpine AS base
WORKDIR /app

# Install dependencies first (better caching)
COPY package*.json ./
RUN npm install --legacy-peer-deps

# Copy everything
COPY . .

# =============================
# 2. Development Stage
# =============================
FROM base AS dev

# Enable hot reload
CMD ["npm", "run", "dev"]

# =============================
# 3. Build Stage
# =============================
FROM base AS build
RUN npm run build

# =============================
# 4. Production Stage
# =============================
FROM node:22.14-alpine AS prod
WORKDIR /app

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S kreditinfo -u 1001 -G nodejs

# Copy only what’s needed for prod
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/.next ./.next
COPY --from=build /app/public ./public
COPY --from=build /app/next.config.ts ./next.config.ts

# Remove dev dependencies
RUN npm prune --omit=dev

USER kreditinfo

EXPOSE 3000
CMD ["npm", "start"]
```

## FE (NextJs) ``docker-compose.yml``
```yaml
services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: kreditinfo_client
    ports:
      - "3000:3000"
```

## FE (NextJs) ``docker-compose.override.yml``
```yaml
services:
  web:
    build:
      context: .
      target: dev
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      - CHOKIDAR_USEPOLLING=true
      - WATCHPACK_POLLING=true
      - NEXT_WEBPACK_USEPOLLING=1
      - CHOKIDAR_INTERVAL=200
      - NODE_ENV=development
    command: npm run dev
```

## FE (NextJs) ``docker-compose.prod.yml``
```yaml
services:
  web:
    build:
      context: .
      target: prod
    container_name: kreditinfo_client
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
```



## BE (Laravel) Multi-Stage ``Dockerfile``
```
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
```

## BE (Laravel) ``docker-compose.yml``
```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: dev
    container_name: linkage_app
    restart: unless-stopped
    volumes:
      - ./:/var/www/html
      - /var/www/html/vendor
    networks:
      - linkage_network
    depends_on:
      - db
      - minio

  nginx:
    build:
      context: ./docker/nginx
      dockerfile: Dockerfile
    ports:
      - "8000:80"
    container_name: linkage_nginx
    volumes:
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./public:/var/www/html
    networks:
      - linkage_network
    depends_on:
      - app
      - php

  php:
    image: php:8.2-fpm
    container_name: linkage_php
    restart: unless-stopped
    volumes:
      - .:/var/www
      - ./docker/php/uploads.ini:/usr/local/etc/php/conf.d/uploads.ini

  db:
    image: mysql:8.0
    container_name: linkage_db
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: ${DB_DATABASE}
      MYSQL_ROOT_PASSWORD: ${ROOT_PASSWORD}
      MYSQL_USER: ${DB_USERNAME}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    command: --default-authentication-plugin=mysql_native_password
    ports:
      - "3307:3306"
    volumes:
      - linkage_data:/var/lib/mysql
      - ./docker/mysql/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - linkage_network

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    container_name: linkage_phpmyadmin
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      PMA_HOST: ${PMA_HOST}
      PMA_USER: ${PMA_USER}
      PMA_PASSWORD: ${PMA_PASSWORD}
    networks:
      - linkage_network
    depends_on:
      - db

  minio:
    image: minio/minio:latest
    container_name: linkage_minio
    command: server --console-address ":9001" /data
    restart: unless-stopped
    ports:
      - "9002:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      MINIO_BUCKET: ${MINIO_BUCKET}
    volumes:
      - linkage_minio:/data
    networks:
      - linkage_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 5s
      timeout: 5s
      retries: 10

  mc:
    image: minio/mc:latest
    container_name: linkage_mc
    depends_on:
      minio:
        condition: service_healthy
    entrypoint: >
      sh -c "
        echo '>> Ensuring bucket: ${MINIO_BUCKET}';
        mc alias set local http://minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} &&
        mc mb --ignore-existing local/${MINIO_BUCKET} &&
        mc anonymous set download local/${MINIO_BUCKET} || true
      "
    networks:
      - linkage_network
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      MINIO_BUCKET: ${MINIO_BUCKET}
    restart: "no"

networks:
  linkage_network:

volumes:
  linkage_data:
  linkage_minio:

```

## BE (Laravel) ``docker-compose.prod.yml``
```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: prod
    image: linkage_backend 
    container_name: linkage_app
    restart: unless-stopped
    volumes:
      - ./:/var/www/html

```

## BE (Laravel) ``docker/entrypoint.sh``
```bash
#!/bin/sh
set -e

ENV_FILE=/var/www/html/.env

if [ ! -f "$ENV_FILE" ]; then
    cp /var/www/html/.env.example "$ENV_FILE"
fi

echo "📦 Checking Composer dependencies..."
if [ ! -d "vendor" ]; then
  composer install --no-dev --optimize-autoloader --no-interaction
fi

echo "🔑 Checking APP_KEY..."
if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "base64:" ]; then
  echo "⚡ No APP_KEY set, generating one..."
  php artisan key:generate --force
else
  echo "✅ APP_KEY already set."
fi

echo "⏳ Waiting for database..."
dockerize -wait tcp://mysql-linkage:3306 -timeout 60s

echo "🚀 Running migrations..."
php artisan migrate --force || echo "⚠️ Migration skipped (already up to date)"
php artisan db:seed || echo "⚠️ Seeder skipped (already up to date)"

echo "🧹 Caching config, routes, views..."
php artisan config:clear
php artisan route:clear
php artisan view:clear
# php artisan optimize:clear

php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "✅ Starting PHP-FPM..."
exec php-fpm -F

```

## BE (Laravel) ``docker/php/uploads.ini``
```
upload_max_filesize = 1024M
post_max_size = 1024M
memory_limit = 2048M
expose_php = Off
```

## BE (Laravel) ``docker/nginx/default.conf``
```bash
server {
  listen 80;
  index index.php index.html;
  server_name localhost;

  root /var/www/html/public;

  # Enable error logging
  error_log  /var/log/nginx/error.log debug;
  access_log /var/log/nginx/access.log;

  # increase request size
  client_max_body_size 1024M;
  proxy_hide_header X-Powered-By;
  fastcgi_hide_header X-Powered-By;

  location / {
    try_files $uri $uri/ /index.php?$query_string;
  }

  location ~ \.php$ {
    include fastcgi_params;
    fastcgi_pass app:9000;
    fastcgi_index index.php;
    fastcgi_param PATH_INFO $fastcgi_path_info;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;

    # PHP error visibility
    # comment this if you don't want to show php errors
    fastcgi_param PHP_VALUE "display_errors=1 \n error_reporting=E_ALL";

    fastcgi_buffers 16 16k;
    fastcgi_buffer_size 32k;
  }

  location ~ /\.ht {
    deny all;
  }
}

```

## BE (Laravel) ``docker/nginx/nginx.conf``
```bash
user  kreditinfo_nginx;
worker_processes  auto;

events {
  worker_connections 1024;
}

http {
  server_tokens off;
  add_header Server "";

  include /etc/nginx/mime.types;
  sendfile        on;
  keepalive_timeout  65;

  include /etc/nginx/conf.d/*.conf;
}
```

## BE (Laravel) ``docker/nginx/Dockerfile``
```yaml
FROM nginx:alpine

# Create non-root user
RUN addgroup -g 1001 -S kreditinfo_nginx && \
    adduser -S kreditinfo_nginx -u 1001 -G kreditinfo_nginx

# Set permissions for logs and www
RUN mkdir -p /var/www/html \
    && chown -R kreditinfo_nginx:kreditinfo_nginx /var/www/html /var/log/nginx /var/cache/nginx /var/run

# Copy configs
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf
```

## BE (Laravel) ``docker/mysql/init.sql``
```sql
GRANT ALL PRIVILEGES ON *.* TO 'admin_kreditinfo'@'%' IDENTIFIED BY 'adm1n_krEditInfo' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```


## Jenkins Pipeline script
```groovy
pipeline {
    agent any

    environment {
        IMAGE_NAME = "darksidebug/linkage-admin"
        IMAGE_TAG = "latest"
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main',
                url: 'https://github.com/awesome-devs-team/linkage-info-solutions-admin-v2.git',
                credentialsId: 'github-creds'
            }
        }

        stage('Build Docker Image') { 
            steps { 
                script { 
                    sh """ 
                        echo ">> Building image for app service"
                        docker-compose -f docker-compose.prod.yml build app
                    """ 
                } 
            } 
        }
        
        stage('Push Docker Image') { 
            steps { 
                script { 
                    withCredentials([
                        usernamePassword( 
                            credentialsId: 'docker-hub-creds', 
                            usernameVariable: 'DOCKER_HUB_USER', 
                            passwordVariable: 'DOCKER_HUB_PASS' 
                        )]
                    ) { 
                        sh ''' 
                            set -e 
                            echo "🔑 Logging into Docker Hub..." 
                            echo "$DOCKER_HUB_PASS" | docker login -u "$DOCKER_HUB_USER" --password-stdin 
                        
                            echo "📦 Pushing latest..." 
                            docker-compose -f docker-compose.prod.yml push app
                            
                            echo "✅ Docker images pushed successfully." 
                        ''' 
                    }
                } 
            } 
        }

        stage('Deploy to EC2') {
            steps {
                script {
                    withCredentials([
                        sshUserPrivateKey( 
                            credentialsId: 'linkage-frontend-deploy-ssh-key', 
                            keyFileVariable: 'SSH_KEY_FILE', 
                            usernameVariable: 'SSH_USER' 
                        ), 
                        string( 
                            credentialsId: 'ec2-frontend-host', 
                            variable: 'REMOTE_HOST' 
                        )
                    ]) {
                        sh '''
                            set -e  # Stop on any command failure
                            
                            echo "🔐 Setting up SSH for deployment..."
                            if ! grep -q "$REMOTE_HOST" "$HOME/.ssh/known_hosts" 2>/dev/null; then
                                ssh-keyscan -H "$REMOTE_HOST" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
                            fi
                            
                            chmod 600 "$SSH_KEY_FILE"
                            
                            ssh -i "$SSH_KEY_FILE" \
                                -o StrictHostKeyChecking=no \
                                -o UserKnownHostsFile=/dev/null \
                                "$SSH_USER@$REMOTE_HOST" << 'EOF'
                                
                            set -e
                            
                            echo "=============================="
                            echo "🚀 Starting Docker deployment..."
                            echo "=============================="
                        
                            echo "🔍 Checking Docker socket permissions..."
                            if [ ! -w /var/run/docker.sock ]; then
                                echo "⚠️ Fixing Docker socket permissions..."
                                sudo chmod 666 /var/run/docker.sock || {
                                    echo "❌ Failed to chmod docker.sock"
                                    exit 1
                                }
                            fi
                        
                            echo "📂 Checking access to /home/ubuntu/linkage ..."
                            if [ ! -d /home/ubuntu/linkage ]; then
                                echo "❌ Directory /home/ubuntu/linkage not found!"
                                exit 1
                            fi
                        
                            echo "🔐 Fixing permissions for Jenkins access..."
                            sudo chmod -R 755 /home/ubuntu/linkage
                        
                            cd /home/ubuntu/linkage || {
                                echo "❌ Failed to cd into /home/ubuntu/linkage"
                                exit 1
                            }
                            
                            echo "📦 Pulling latest app image..."
                            sudo docker pull darksidebug/linkage-admin-app:latest
                            
                            echo "🔁 Stopping and removing existing containers..."
                            sudo docker rm -f linkage_admin 2>/dev/null || true
                            
                            echo "🚀 Running app container..."
                            sudo docker run -d \
                              --name linkage_admin \
                              -p 3001:3000 \
                              -e NODE_ENV=production \
                              darksidebug/linkage-admin-app:latest
                        
                            echo "🧹 Cleaning up unused Docker resources..."
                            sudo docker system prune -f
                        
                            echo "✅ Deployment completed successfully!"
                            echo "=============================="
                        '''
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo "🧹 Cleaning workspace..."
            cleanWs()
        }
        success {
            echo '✅  Linkageph Admin Docker deployment successful via Docker Hub!'
        }
        failure {
            echo '❌ Deployment failed.'
        }
    }
}

```


