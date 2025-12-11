# Jenkins-AWS-CI/CD-Pipeline (Next.Js and Laravel)

## FE (NextJs) Multi-Stage ``Dockerfile``

```Dockerfile
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
    adduser -S <your_user> -u 1001 -G nodejs

# Copy only what’s needed for prod
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/.next ./.next
COPY --from=build /app/public ./public
COPY --from=build /app/next.config.ts ./next.config.ts

# Remove dev dependencies
RUN npm prune --omit=dev

USER <your_user>

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
      target: dev
    container_name: <contianer_name>
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
    ports:
      - "3000:3000"
```

## FE (NextJs) ``docker-compose.prod.yml``
```yaml
services:
  web:
    build:
      context: .
      target: prod
    container_name: <conatiner_name>
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
```



## BE (Laravel) Multi-Stage ``Dockerfile``
```Dockerfile
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

## BE (Laravel) Multi-Stage ``Dockerfile`` with ``cron`` job
```Dockerfile
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

# Install cron and supervisor
RUN apt-get update && apt-get install -y cron supervisor && apt-get clean

# Copy full source
COPY . .

# Copy supervisor configuration
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

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

# Start Supervisor (which runs php-fpm, cron, and queue)
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

# =============================
# 4. Production Stage
# =============================
FROM base AS prod

# Copy built application from build stage
COPY --from=build /var/www/html /var/www/html

# Install cron and supervisor
RUN apt-get update && apt-get install -y cron supervisor && apt-get clean

# Copy supervisor configuration
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Set permissions
RUN chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Copy entrypoint
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create log file for cron
RUN touch /var/log/cron.log && chmod 666 /var/log/cron.log

EXPOSE 9000

ENTRYPOINT ["entrypoint.sh"]

# Start Supervisor (which runs php-fpm, cron, and queue)
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

## BE (Laravel) ``docker-compose.yml``
```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: dev
    container_name: <app_container_name>
    restart: unless-stopped
    volumes:
      - ./:/var/www/html
      - /var/www/html/vendor
    networks:
      - <project_name>_network
    depends_on:
      - db
      - minio # remove this if you don't need minio

  nginx:
    build:
      context: ./docker/nginx
      dockerfile: Dockerfile
    ports:
      - "8000:80"
    container_name: <nginx_container_name>
    volumes:
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./public:/var/www/html
    networks:
      - <project_name>_network
    depends_on:
      - app

  db:
    image: mysql:8.0
    container_name: <db_container_name>
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
      - <project_name>_data:/var/lib/mysql
      - ./docker/mysql/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - <project_name>_network

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    container_name: <phpmyadmin_contianer_name>
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      PMA_HOST: ${PMA_HOST}
      PMA_USER: ${PMA_USER}
      PMA_PASSWORD: ${PMA_PASSWORD}
    networks:
      - <project_name>_network
    depends_on:
      - db

  # optional
  minio:
    image: minio/minio:latest
    container_name: <minio_container_name>
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
      - <project_name>_minio:/data
    networks:
      - <project_name>_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 5s
      timeout: 5s
      retries: 10

  # optional
  mc:
    image: minio/mc:latest
    container_name: <mc_container_name>
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
      - <project_name>_network
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      MINIO_BUCKET: ${MINIO_BUCKET}
    restart: "no"

networks:
  <project_name>_network:

volumes:
  <project_name>_data:
  <project_name>_minio:

```

## BE (Laravel) ``docker-compose.prod.yml``
```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: prod
    image: <image_name> 
    container_name: <container_name>
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
dockerize -wait tcp://<your-db-service>:3306 -timeout 60s

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
user  <your_user>_nginx;
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
RUN addgroup -g 1001 -S nginx && \
    adduser -S nginx -u 1001 -G nginx

# Set permissions for logs and www
RUN mkdir -p /var/www/html \
    && chown -R <your_user>_nginx:<your_user>_nginx /var/www/html /var/log/nginx /var/cache/nginx /var/run

# Copy configs
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf
```

## BE (Laravel) ``docker/mysql/init.sql``
```sql
GRANT ALL PRIVILEGES ON *.* TO '<db_name>'@'%' IDENTIFIED BY '<db_username>' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

## Create folder for your Jenkins ``Dockerfile``
```Dockerfile
FROM jenkins/jenkins:lts

USER root

# Install Docker CLI and docker-compose
RUN apt-get update && apt-get install -y \
  docker.io \
  docker-compose \
  git \
  curl \
  sudo \
  && rm -rf /var/lib/apt/lists/*

# Add jenkins user to docker group
RUN usermod -aG docker jenkins

USER jenkins

```

## Jenkins ``docker-compose.yml``
```yaml
version: "3.9"

services:
  jenkins:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: jenkins
    user: root
    restart: unless-stopped
    ports:
      - "8081:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - jenkins_network

networks:
  jenkins_network:

volumes:
  jenkins_home:

```

## Jenkins Credentials and Pipeline Script (Laravel)

### Create credentials in your jenkins
- Open Jenkins → Dashboard
- Click Manage Jenkins
- Click Credentials
- Select:
  - System
  - Global credentials (unrestricted)
- Then click Add Credentials.

- Add Each Credential (Type-by-Type)
  - GitHub Credentials (for Checkout Stage)
  - Kind: _Username with password_
  - Username: Your GitHub username
  - Password: GitHub Personal Access Token
  - ID: Example `github-creds`
  - Description: GitHub Access Token for Jenkins - optional.
 
- Docker Hub Credentials
  - Kind: _Username with password_
  - Username: Docker Hub username
  - Password: Docker Hub access token / password
  - ID: Example `docker-hub-creds`
  - Description: Docker Hub login for pipeline - optional
 
- SSH Key for EC2 Server (or in-house server) Deployment
  - Kind: _SSH Username with private key_
  - Username: `ec2-user` or `ubuntu` (Your EC2 SSH user) or your in-house server user
  - Private Key: paste your `.pem` file
    Note: Important:
    Select → “Enter directly” → paste private key content.

- Remote Host IP
  - Kind: _Secret Text_
  - Secret text: `your_ec2_user@ip_address` or `your_user@ip_address`
  - ID: Example `ec2-host-ip`
  - Description: EC2 public IP for deployment - optional
    Note: Important:
    If you have separate server for your backend specify your ID: e.g. `be-ec2-host-ip`, for separate server for frontend app ID: e.g. `fe-ec2-host-ip`

- App / Database / Service Environment Variables
  `DB_HOST` will be your database service name
  
| Credential ID           | Type        | Value                           |
| ----------------------- | ----------- | ------------------------------- |
| `APP_KEY`               | Secret Text | Your Laravel app key            |
| `DB_HOST`               | Secret Text | Usually `mysql` or RDS endpoint |
| `DB_DATABASE`           | Secret Text | e.g., `laravel_db`              |
| `DB_USERNAME`           | Secret Text | DB username                     |
| `DB_PASSWORD`           | Secret Text | DB password                     |
| `MAIL_USERNAME`         | Secret Text | Email login                     |
| `MAIL_PASSWORD`         | Secret Text | Email password                  |
| `AWS_ACCESS_KEY_ID`     | Secret Text | AWS key                         |
| `AWS_SECRET_ACCESS_KEY` | Secret Text | AWS secret                      |
| `GOOGLE_CLIENT_ID`      | Secret Text | OAuth client id                 |
| `GOOGLE_CLIENT_SECRET`  | Secret Text | OAuth secret                    |
| `GHL_SECRET_KEY`        | Secret Text | Your GHL secret                 |
| `GHL_MERCHANT_ID`       | Secret Text | Merchant ID                     |
| `JWT_SECRET`            | Secret Text | JWT secret                      |

## Laravel Pipeline Script
```groovy
pipeline {
    agent any

    environment {
        IMAGE_NAME = "<your_docker_hub_username>/<repository>"
        IMAGE_TAG = "latest"
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'develop',
                url: 'https://github.com/<your-repo>.git',
                credentialsId: 'github-creds'
            }
        }

        stage('Build Docker Image') { 
            steps { 
                script { 
                    sh """ 
                        echo ">> Building image for app service"
                        docker-compose -f docker-compose.prod.yml build 
                    """ 
                } 
            } 
        }
        
        stage('Push Docker Image') { 
            steps { 
                script { 
                    withCredentials([
                        usernamePassword( 
                            credentialsId: '<your-docker-hub-creds-id>', 
                            usernameVariable: 'DOCKER_HUB_USER', 
                            passwordVariable: 'DOCKER_HUB_PASS' 
                        )]
                    ) { 
                        sh ''' 
                            set -e 
                            echo "🔑 Logging into Docker Hub..." 
                            echo "$DOCKER_HUB_PASS" | docker login -u "$DOCKER_HUB_USER" --password-stdin 
                            
                            echo "🏷️ Tagging images..."
                            docker tag <tag_name> $IMAGE_NAME-app:$IMAGE_TAG
                            
                            echo "📦 Pushing versioned images..." 
                            docker push $IMAGE_NAME-app:$IMAGE_TAG
                            
                            echo "🏷️ Tagging as latest..."
                            docker tag $IMAGE_NAME-app:$IMAGE_TAG $IMAGE_NAME-app:latest 
                            
                            echo "📦 Pushing latest..." 
                            docker push $IMAGE_NAME-app:latest
                            
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
                            credentialsId: '<your-deploy-ssh-key-id>', 
                            keyFileVariable: 'SSH_KEY_FILE', 
                            usernameVariable: 'SSH_USER' 
                        ), 
                        string( 
                            credentialsId: '<your-remote-host-ip-id>', 
                            variable: 'REMOTE_HOST' 
                        ), 
                        string( 
                            credentialsId: 'APP_KEY', 
                            variable: 'APP_KEY' 
                        ), 
                        string( 
                            credentialsId: 'DB_HOST', 
                            variable: 'DB_HOST' 
                        ), 
                        string( 
                            credentialsId: 'DB_DATABASE', 
                            variable: 'DB_DATABASE' 
                        ), 
                        string( 
                            credentialsId: 'DB_USERNAME', 
                            variable: 'DB_USERNAME' 
                        ), 
                        string( 
                            credentialsId: 'DB_PASSWORD', 
                            variable: 'DB_PASSWORD' 
                        ), 
                        string( 
                            credentialsId: 'MAIL_USERNAME', 
                            variable: 'MAIL_USERNAME' 
                        ), 
                        string( 
                            credentialsId: 'MAIL_PASSWORD', 
                            variable: 'MAIL_PASSWORD' 
                        ), 
                        string( 
                            credentialsId: 'AWS_ACCESS_KEY_ID', 
                            variable: 'AWS_ACCESS_KEY_ID' 
                        ), 
                        string( 
                            credentialsId: 'AWS_SECRET_ACCESS_KEY', 
                            variable: 'AWS_SECRET_ACCESS_KEY' 
                        ), 
                        string( 
                            credentialsId: 'GOOGLE_CLIENT_ID', 
                            variable: 'GOOGLE_CLIENT_ID' 
                        ), 
                        string( 
                            credentialsId: 'GOOGLE_CLIENT_SECRET', 
                            variable: 'GOOGLE_CLIENT_SECRET' 
                        ), 
                        string( 
                            credentialsId: 'GHL_SECRET_KEY', 
                            variable: 'GHL_SECRET_KEY' 
                        ), 
                        string( 
                            credentialsId: 'GHL_MERCHANT_ID', 
                            variable: 'GHL_MERCHANT_ID' 
                        ), 
                        string( 
                            credentialsId: 'JWT_SECRET', 
                            variable: 'JWT_SECRET' 
                        )
                    ]) {
                        sh """
                            set -e  # Stop on any command failure
                            
                            echo "🔐 Setting up SSH for deployment..."
                            if ! grep -q "$REMOTE_HOST" "$HOME/.ssh/known_hosts" 2>/dev/null; then
                                ssh-keyscan -H "$REMOTE_HOST" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
                            fi
                            
                            chmod 600 "$SSH_KEY_FILE"
                            
                            echo "🚀 Deploying to EC2: $REMOTE_HOST"
                            
                            ssh -i "$SSH_KEY_FILE" \
                                -o StrictHostKeyChecking=no \
                                -o UserKnownHostsFile=/dev/null \
                                "$SSH_USER@$REMOTE_HOST" << 'EOF'
                                
                            set -e
                            
                            echo "🧹 Cleaning up dangling images..."
                            sudo docker image prune -f
                            
                            echo "📦 Pulling latest app image..."
                            sudo docker pull <dockerhub-username>/<docker-hub-repository>-app:latest
                            
                            echo "🔁 Stopping and removing existing containers..."
                            sudo docker rm -f <container_name> 2>/dev/null || true
                            
                            echo "🚀 Running app container..."
                            sudo docker run -d \
                                --name <container_name> \
                                --network <service_network> \
                                -p 9001:9000 \
                                -e NODE_ENV=production \
                                -e APP_KEY="${APP_KEY}" \
                                -e DB_HOST=<your-db-service> \
                                -e DB_DATABASE="${DB_DATABASE}" \
                                -e DB_USERNAME="${DB_USERNAME}" \
                                -e DB_PASSWORD="${DB_PASSWORD}" \
                                -e MAIL_USERNAME="${MAIL_USERNAME}" \
                                -e MAIL_PASSWORD="${MAIL_PASSWORD}" \
                                -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
                                -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
                                -e GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID}" \
                                -e GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET}" \
                                -e GHL_SECRET_KEY="${GHL_SECRET_KEY}" \
                                -e GHL_MERCHANT_ID="${GHL_MERCHANT_ID}" \
                                -e JWT_SECRET="${JWT_SECRET}" \
                                <dockerhub-username>/<docker-hub-repository>-app:latest
                            
                            echo "✅ Deployment complete."
                        """
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
            echo '✅  Backend Docker deployment successful via Docker Hub!'
        }
        failure {
            echo '❌ Deployment failed.'
        }
    }
}

```

## Jenkins Pipeline Script (Next.Js)
```groovy
pipeline {
    agent any

    environment {
        IMAGE_NAME = "<your_docker_hub_username>/<repository>"
        IMAGE_TAG = "latest"
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main',
                url: 'https://github.com/<your-repo>.git',
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
                            credentialsId: '<your-docker-hub-creds-id>', 
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
                            credentialsId: '<your-deploy-ssh-key-id>', 
                            keyFileVariable: 'SSH_KEY_FILE', 
                            usernameVariable: 'SSH_USER' 
                        ), 
                        string( 
                            credentialsId: '<your-remote-host-ip-id>', 
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
                        
                            echo "📂 Checking access to /home/<your-user>/your-project-dir> ..."
                            if [ ! -d /home/<your-user>/<your-project-dir> ]; then
                                echo "❌ Directory /home/ubuntu/<your-project-dir> not found!"
                                exit 1
                            fi
                        
                            echo "🔐 Fixing permissions for Jenkins access..."
                            sudo chmod -R 755 /home/<your-user>/<your-project-dir>
                        
                            cd /home/<your-user>/<your-project-folder> || {
                                echo "❌ Failed to cd into /home/<your-user>/<your-project-dir>"
                                exit 1
                            }
                            
                            echo "📦 Pulling latest app image..."
                            sudo docker pull <dockerhub-username>/<docker-hub-repository>-app:latest
                            
                            echo "🔁 Stopping and removing existing containers..."
                            sudo docker rm -f <container_name> 2>/dev/null || true
                            
                            echo "🚀 Running app container..."
                            sudo docker run -d \
                              --name <container_name> \
                              -p 3000:3000 \
                              -e NODE_ENV=production \
                              <dockerhub-username>/<docker-hub-repository>-app:latest
                        
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
            echo '✅  Frontend docker deployment successful via Docker Hub!'
        }
        failure {
            echo '❌ Deployment failed.'
        }
    }
}

```

## For server setup follow the steps here:
Read the documentation part for server setup at README.md
https://github.com/darksidebug/Laravel-CICD-Pipeline


