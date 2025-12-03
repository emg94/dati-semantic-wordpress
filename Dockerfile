# Stage 1: BusyBox
FROM busybox:1.36.1 AS busybox-stage

# Stage 2: WordPress
FROM wordpress:6.8.3-php8.4-apache

# Copia BusyBox dentro WordPress
COPY --from=busybox-stage /bin/sh /bin/sh
COPY --from=busybox-stage /bin/busybox /bin/busybox

# Cambia porta Apache
RUN sed -i "s/Listen 80/Listen 8080/g" /etc/apache2/ports.conf && \
    sed -i "s/80/8080/g" /etc/apache2/sites-enabled/000-default.conf

# Installa WP-CLI, MySQL client, unzip
RUN apt-get update && \
    apt-get install -y default-mysql-client unzip curl && \
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp && \
    rm -rf /var/lib/apt/lists/*

# Copia plugin e contenuti
COPY ./imported-content/*.wpress /tmp/content.wpress
COPY ./imported-content/plugins/all-in-one-wp-migration-unlimited-extension.zip /tmp/plugins/

# Copia script bootstrap
COPY scripts/wp-bootstrap.sh /usr/local/bin/wp-bootstrap.sh
RUN chmod +x /usr/local/bin/wp-bootstrap.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]

