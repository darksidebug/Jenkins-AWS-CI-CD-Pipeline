# Jenkins-AWS-CI-CD-Pipeline

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
