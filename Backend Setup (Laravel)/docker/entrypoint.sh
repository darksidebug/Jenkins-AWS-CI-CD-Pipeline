#!/bin/sh
set -e

echo "📦 Checking Composer dependencies..."

# Compute checksum file
LOCK_HASH_FILE=".composer.lock.hash"

# If vendor folder doesn't exist, or composer.lock changed, run install
if [ ! -d "vendor" ]; then
  echo "📂 No vendor directory found — installing dependencies..."
  composer install --no-dev --optimize-autoloader --no-interaction
  sha1sum composer.lock > "$LOCK_HASH_FILE"

elif [ ! -f "$LOCK_HASH_FILE" ] || ! sha1sum -c --status "$LOCK_HASH_FILE" 2>/dev/null; then
  echo "🔄 composer.lock has changed — updating dependencies..."
  composer install --no-dev --optimize-autoloader --no-interaction
  sha1sum composer.lock > "$LOCK_HASH_FILE"

else
  echo "✅ Dependencies are up-to-date."
fi

echo "🔑 Checking APP_KEY..."
if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "base64:" ]; then
  echo "⚡ No APP_KEY set, generating one..."
  php artisan key:generate --force
else
  echo "✅ APP_KEY already set."
fi

echo "⏳ Waiting for database..."
dockerize -wait tcp://db:3306 -timeout 60s

echo "🚀 Running migrations..."
php artisan migrate --force || echo "⚠️ Migration skipped (already up to date)"
php artisan db:seed || echo "⚠️ Seeder skipped (already up to date)"

echo "✅ Starting PHP-FPM..."
exec "$@"

