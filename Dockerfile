FROM wordpress:6.8.3-php8.4-apache

RUN sed -i "s/Listen 80/Listen 8080/g" /etc/apache2/ports.conf
RUN sed -i "s/80/8080/g" /etc/apache2/sites-enabled/000-default.conf

# Install wp-cli
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp
