FROM nginx:alpine

# Create non-root user
RUN addgroup -g 1001 -S <your_user>_nginx && \
    adduser -S <your_user>_nginx -u 1001 -G <your_user>_nginx

# Set permissions for logs and www
RUN mkdir -p /var/www/html \
    && chown -R <your_user>_nginx:<your_user>_nginx /var/www/html /var/log/nginx /var/cache/nginx /var/run

# Copy configs
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf
