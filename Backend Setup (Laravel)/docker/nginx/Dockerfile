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
