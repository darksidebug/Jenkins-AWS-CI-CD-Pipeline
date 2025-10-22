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
