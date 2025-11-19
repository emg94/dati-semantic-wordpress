FROM wordpress:6.8.3-php8.4-apache

# -------------------------------------------
# Cambia porta 80 → 8080
# -------------------------------------------
RUN sed -i "s/Listen 80/Listen 8080/g" /etc/apache2/ports.conf && \
    sed -i "s/80/8080/g" /etc/apache2/sites-enabled/000-default.conf

# -------------------------------------------
# Installa WP-CLI
# -------------------------------------------
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp

# -------------------------------------------
# Copia il file .wpress generato dal branch content
# -------------------------------------------
COPY ./imported-content/*.wpress /tmp/content.wpress

# -------------------------------------------
# Copia gli script di importazione
# -------------------------------------------
COPY scripts/import-content.sh /usr/local/bin/import-content.sh
COPY scripts/docker-entrypoint-wrapper.sh /usr/local/bin/docker-entrypoint-wrapper.sh
RUN chmod +x /usr/local/bin/import-content.sh /usr/local/bin/docker-entrypoint-wrapper.sh

ENTRYPOINT ["docker-entrypoint-wrapper.sh"]
CMD ["apache2-foreground"]
