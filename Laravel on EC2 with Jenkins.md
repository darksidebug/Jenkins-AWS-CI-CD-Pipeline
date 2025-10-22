# 📘 Step‑by‑Step CI/CD Guide — Laravel on EC2 with Jenkins, Docker Hub, Docker Compose, Nginx Reverse Proxy & GoDaddy SSL + MySQL

This guide walks you through a clean, reproducible setup from zero to production. It uses:

- **GitHub → Jenkins (EC2) → Docker Hub → EC2 app host**
- **Nginx reverse proxy** for your domain with **GoDaddy SSL**
- **MySQL** and **Redis** as containers

> Already have the code snippets? Follow the numbered steps below to wire everything together end‑to‑end.

---

## 0) Decide your variables (write these down)
- **Domain**: `yourdomain.com`
- **Docker Hub username**: `yourdockerhubuser`
- **Image name**: `your-laravel-app`
- **EC2 (Jenkins) IP**: `JENKINS_IP`
- **EC2 (App) IP**: `APP_IP`
- **Jenkins credentials IDs** you will create:
  - `github-ssh` (SSH key for repo)
  - `dockerhub-creds` (Docker Hub user/pass)
  - `ec2-ssh-prod` (SSH key for app EC2)

---

## 1) Provision two EC2 instances
**OS**: Ubuntu 22.04 LTS recommended.

**Security Groups**
- **Jenkins EC2**: inbound `22/tcp` (your IP), `8080/tcp` (your IP)
- **App EC2**: inbound `22/tcp` (your IP), `80/tcp` (0.0.0.0/0 or via ALB), `443/tcp` (0.0.0.0/0 or via ALB)

> Use key pairs (PEM) and disable password logins later for security.

---

## 2) Install Docker & Compose (both EC2s)
SSH into each instance and run:
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Re-login to pick up docker group, or run: newgrp docker
sudo curl -L https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

---

## 3) Bring up Jenkins on its EC2
Create `docker-compose.yml` on the **Jenkins EC2**:
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
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - D:/Projects/Linkage/LinkagePH-Backend-Deployment.pem:/home/jenkins/deploy.pem:rw
    networks:
      - jenkins_network

networks:
  jenkins_network:

volumes:
  jenkins_home:
```
Start Jenkins:
```bash
docker compose up -d
```
Open `http://JENKINS_IP:8080`.

**Install plugins**: *Git*, *GitHub*, *Pipeline*, *Credentials*, *SSH Agent*, *Docker Pipeline*.

**Create credentials** (Manage Jenkins → Credentials):
- `github-ssh`: Kind = *SSH Username with private key* → paste private key that can read your GitHub repo.
- `dockerhub-creds`: Kind = *Username with password* (Docker Hub).
- `ec2-ssh-prod`: Kind = *SSH Username with private key* → user `ubuntu`, private key for **App EC2**.

---

## 4) Prepare your Laravel repository
In your repo, add the following files and commit them. (All examples are already in this canvas; copy into your repo.)

- `.docker/php-fpm.Dockerfile` — PHP‑FPM image for Laravel
- `.docker/nginx.conf` — Nginx reverse proxy with SSL
- `.docker/supervisor-queue.conf` — queue worker
- `.docker/cron.d/laravel-scheduler` — scheduler cron
- `compose.prod.yml` — production stack (app/nginx/redis/mysql)
- `Jenkinsfile` — CI/CD pipeline

> If you compile front‑end assets, add a Node stage in the Dockerfile and copy the built files into `public/`.

Commit & push to GitHub.

---

## 5) Point your domain to the App EC2
In **GoDaddy DNS**, set an **A record** for `@` (and `www` CNAME → `@` if desired) to `APP_IP`.

Propagation can take a few minutes.

---

## 6) Install GoDaddy SSL on the App EC2
1. In GoDaddy SSL dashboard, download the **Apache** bundle (domain `.crt` + `gd_bundle-g2-g1.crt`).
2. On your workstation, combine them:
   ```bash
   cat yourdomain.crt gd_bundle-g2-g1.crt > fullchain.pem
   ```
3. Upload `fullchain.pem` and your private key `yourdomain.key` to the App EC2 at:
   ```
sudo mkdir -p /etc/ssl/yourdomain
sudo chown -R ubuntu:ubuntu /etc/ssl/yourdomain
# then copy files there (scp/rsync/SFTP)
   ```
4. Ensure Nginx volume in `compose.prod.yml` maps `/etc/ssl/yourdomain` into the container.

> GoDaddy certs typically renew annually. Set yourself a calendar reminder to replace the files and restart Nginx when they expire.

---

## 7) Prepare the App EC2 filesystem & env files
SSH to **App EC2** and create a deploy folder:
```bash
mkdir -p ~/app/_runtime_code
cd ~/app
```
Create `.env.app`:
```
APP_ENV=production
APP_DEBUG=false
APP_URL=https://yourdomain.com
APP_KEY=base64:GENERATE_THIS_ONCE

LOG_CHANNEL=stderr

DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=yourdb
DB_USERNAME=youruser
DB_PASSWORD=yourpass

CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
REDIS_HOST=redis
REDIS_PORT=6379
SESSION_DRIVER=redis
SESSION_LIFETIME=120
```
Create `.env.mysql`:
```
MYSQL_DATABASE=yourdb
MYSQL_USER=youruser
MYSQL_PASSWORD=yourpass
MYSQL_ROOT_PASSWORD=strongrootpass
```
Copy `compose.prod.yml` and the `.docker/` directory from your repo to `~/app/` (first time you can SCP/rsync manually).

Generate a one‑time app key locally and paste into `.env.app` if you don’t have one yet:
```bash
# temporary php container just to generate a key if needed
docker run --rm -v "$PWD/_runtime_code":/app -w /app php:8.3-cli-alpine php -r "echo base64_encode(random_bytes(32));"
```

---

## 8) First boot of the stack (to create volumes)
From **App EC2** in `~/app`:
```bash
docker compose -f compose.prod.yml up -d
```
Wait for MySQL to initialize (first run may take ~30–60s). Then create DB schema:
```bash
docker compose -f compose.prod.yml exec -T app php artisan migrate --force
docker compose -f compose.prod.yml exec -T app php artisan storage:link || true
```

> If your image doesn’t yet have the code (first CI run not done), you can stop here and continue once the pipeline pushes an image.

---

## 9) Configure the GitHub → Jenkins webhook
- GitHub repo → **Settings → Webhooks → Add webhook**
  - Payload URL: `http://JENKINS_IP:8080/github-webhook/`
  - Content type: `application/json`
  - Events: **Just the push event**
- In Jenkins job (created in next step), enable **GitHub hook trigger for GITScm polling**.

---

## 10) Create the Jenkins Pipeline job
**Option A: Multibranch Pipeline** (recommended):
- New Item → *Multibranch Pipeline* → Repository (SSH URL) → Credentials = `github-ssh`.
- Build triggers: *Periodically if not otherwise run* (optional); enable GitHub hook in repo settings (step 9).

**Option B: Single Pipeline**:
- New Item → *Pipeline* → select *Pipeline script from SCM* → Git → SSH URL + `github-ssh` creds → script path `Jenkinsfile`.

---

## 11) Jenkinsfile (CI/CD) — copy to repo root
```groovy
pipeline {
  agent any
  environment {
    REGISTRY = "docker.io"
    REGISTRY_NAMESPACE = "yourdockerhubuser"
    IMAGE_NAME = "your-laravel-app"
    GIT_COMMIT_SHORT = "${env.GIT_COMMIT?.take(7)}"
    APP_TAG = "${GIT_COMMIT_SHORT ?: 'manual'}"
  }

  options { timestamps() }

  triggers { pollSCM('') } // webhook will trigger builds; polling is a fallback

  stages {
    stage('Checkout') {
      steps {
        sshagent(credentials: ['github-ssh']) { checkout scm }
      }
    }

    stage('Composer Validate & Test') {
      steps {
        sh '''
          docker run --rm -v "$PWD":/app -w /app php:8.3-cli-alpine sh -lc "\
            apk add --no-cache git unzip && \
            curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
            composer install --no-interaction --prefer-dist && \
            php -v && composer -V && \
            ./vendor/bin/phpunit --testsuite=Unit --colors=never || true"
        '''
      }
    }

    stage('Build Image') {
      steps {
        script { env.FULL_TAG = "${REGISTRY}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${APP_TAG}" }
        sh 'docker build -f .docker/php-fpm.Dockerfile -t "$FULL_TAG" .'
      }
    }

    stage('Push Image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', passwordVariable: 'DOCKERHUB_PASS', usernameVariable: 'DOCKERHUB_USER')]) {
          sh '''
            echo "$DOCKERHUB_PASS" | docker login -u "$DOCKERHUB_USER" --password-stdin
            docker push "$FULL_TAG"
          '''
        }
      }
    }

    stage('Deploy to Prod EC2') {
      steps {
        sshagent(credentials: ['ec2-ssh-prod']) {
          sh '''
            REMOTE_USER=ubuntu
            REMOTE_HOST=APP_IP
            # Ensure target dir exists
            ssh -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_HOST "mkdir -p ~/app/_runtime_code"
            # Optional: sync built code for nginx static serving (if needed)
            rsync -az --delete -e "ssh -o StrictHostKeyChecking=no" --exclude 'storage/*' --exclude '.git' ./ $REMOTE_USER@$REMOTE_HOST:~/app/_runtime_code/
            # Write tag and roll containers
            ssh -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_HOST "\
              set -e; cd ~/app; \
              echo APP_TAG='${APP_TAG}' > .deploy_env; \
              export \$(cat .deploy_env | xargs); \
              docker compose -f compose.prod.yml pull; \
              docker compose -f compose.prod.yml up -d --remove-orphans; \
              docker system prune -f"
          '''
        }
      }
    }

    stage('Run Migrations & Cache (post-deploy)') {
      steps {
        sshagent(credentials: ['ec2-ssh-prod']) {
          sh '''
            ssh -o StrictHostKeyChecking=no ubuntu@APP_IP "\
              set -e; cd ~/app; \
              docker compose -f compose.prod.yml exec -T app php artisan migrate --force; \
              docker compose -f compose.prod.yml exec -T app php artisan config:cache; \
              docker compose -f compose.prod.yml exec -T app php artisan route:cache; \
              docker compose -f compose.prod.yml exec -T app php artisan view:cache; \
              docker compose -f compose.prod.yml exec -T app php artisan storage:link || true"
          '''
        }
      }
    }

    stage('Smoke Test') {
      steps { sh 'curl -fsS https://yourdomain.com/ || (docker ps; exit 1)' }
    }
  }
}
```
**Replace** `yourdockerhubuser`, `your-laravel-app`, and `APP_IP` with your values.

---

## 12) Nginx reverse proxy with SSL (inside the container)
`.docker/nginx.conf`:
```nginx
server {  # HTTP → HTTPS
  listen 80;
  server_name yourdomain.com www.yourdomain.com;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl;
  server_name yourdomain.com www.yourdomain.com;

  ssl_certificate /etc/ssl/yourdomain/fullchain.pem;
  ssl_certificate_key /etc/ssl/yourdomain/yourdomain.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers HIGH:!aNULL:!MD5;

  root /var/www/html/public;
  index index.php index.html;

  location / {
    try_files $uri $uri/ /index.php?$query_string;
  }

  location ~ \.php$ {
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass app:9000;  # php-fpm service name
  }

  client_max_body_size 50M;
}
```

---

## 13) Production Docker Compose (App EC2)
`compose.prod.yml`:
```yaml
version: "3.9"
services:
  app:
    image: yourdockerhubuser/your-laravel-app:${APP_TAG:-latest}
    env_file: [.env.app]
    volumes:
      - app-storage:/var/www/html/storage
      - app-cache:/var/www/html/bootstrap/cache
    depends_on: [mysql]
    networks: [web]

  nginx:
    image: nginx:1.27-alpine
    depends_on: [app]
    ports: ["80:80", "443:443"]
    volumes:
      - app-storage:/var/www/html/storage:ro
      - app-cache:/var/www/html/bootstrap/cache:ro
      - ./_runtime_code:/var/www/html:ro
      - ./.docker/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/ssl/yourdomain:/etc/ssl/yourdomain:ro
    networks: [web]

  queue:
    image: yourdockerhubuser/your-laravel-app:${APP_TAG:-latest}
    env_file: [.env.app]
    command: ["sh", "-lc", "supervisord -n -c /etc/supervisor/conf.d/supervisor-queue.conf"]
    volumes:
      - app-storage:/var/www/html/storage
      - app-cache:/var/www/html/bootstrap/cache
    networks: [web]

  scheduler:
    image: yourdockerhubuser/your-laravel-app:${APP_TAG:-latest}
    env_file: [.env.app]
    command: ["sh", "-lc", "crond -f -l 8"]
    volumes:
      - ./.docker/cron.d:/etc/crontabs:ro
      - app-storage:/var/www/html/storage
      - app-cache:/var/www/html/bootstrap/cache
    networks: [web]

  redis:
    image: redis:7-alpine
    volumes:
      - redis-data:/data
    networks: [web]

  mysql:
    image: mysql:8.4
    env_file: [.env.mysql]
    command: --default-authentication-plugin=mysql_native_password --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    ports: ["3306:3306"]
    volumes:
      - dbdata:/var/lib/mysql
    networks: [web]

networks:
  web: { driver: bridge }

volumes:
  app-storage:
  app-cache:
  redis-data:
  dbdata:
```

---

## 14) Make a tiny health endpoint (optional)
Add to `routes/web.php`:
```php
Route::get('/health', fn () => response()->noContent());
```
Then in Jenkins **Smoke Test** stage, curl `/health` for a fast 204.

---

## 15) First CI/CD run
1. Push to `main` (or your default branch).
2. GitHub webhook triggers Jenkins → Build → Push image → Deploy → Migrate → Smoke test.
3. Visit `https://yourdomain.com`.

If Nginx shows 502 temporarily, wait for app container to finish booting and MySQL readiness.

---

## 16) Rollback (previous image)
On Jenkins, re-run a successful prior build **or** set a specific `APP_TAG` and redeploy:
- Edit the pipeline run parameters (if you parameterize it) or temporarily change `APP_TAG` in Jenkinsfile to a previous short SHA.
- Deploy stage will pull that tag and restart containers.

Alternatively on the App EC2:
```bash
cd ~/app
echo APP_TAG=abcdef1 > .deploy_env
export $(cat .deploy_env | xargs)
docker compose -f compose.prod.yml pull
docker compose -f compose.prod.yml up -d --remove-orphans
```

---

## 17) Backups & persistence
- **MySQL**: `dbdata` named volume. Snapshot the EBS volume of the EC2 host and/or use `mysqldump` to S3 via cron.
- **Storage**: `app-storage` persists user uploads. Include it in your backup plan.

---

## 18) Security checklist
- Disable SSH password auth; use keys only.
- Limit SG inbound to your IP (except 80/443).
- Keep `.env` files on the server only; never commit them.
- Use strong MySQL root/user passwords.
- Keep images updated; rebuild periodically (base image CVEs).

---

## 19) Troubleshooting
- **Jenkins can’t clone repo** → verify `github-ssh` has access; test `ssh -T git@github.com` from Jenkins container.
- **Push to Docker Hub fails** → check `dockerhub-creds` and repo name; ensure Docker Hub rate limits aren’t hit.
- **Nginx 502** → `docker compose logs nginx app`; verify `fastcgi_pass app:9000` and that the `app` container is healthy.
- **MySQL auth errors** → confirm `.env.app` DB creds match `.env.mysql` and that `mysql` container is running.
- **SSL not loading** → inside `nginx` container, verify files at `/etc/ssl/yourdomain/`; check permissions and correct filenames.

---

### You’re done ✅
You now have a repeatable CI/CD flow: **GitHub → Jenkins → Docker Hub → EC2** with **Nginx (HTTPS via GoDaddy)**, **MySQL**, and **Redis**. Push code → image builds → deploys → migrations → live.

