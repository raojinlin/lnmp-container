FROM ubuntu:18.04


RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install nginx git mysql-server php7.2-fpm php7.2-mysql nodejs -y && mkdir /run/php && rm -rf /var/lib/apt/lists/*

COPY phpupfile /var/www/phpupfile
COPY conf/php-vhost.conf /etc/nginx/sites-enabled/php
COPY conf/mysqld.conf /etc/mysql/mysql.conf.d/mysqld.cnf
COPY entrypoint.sh /entrypoint.sh
COPY server.js /var/www/nodejs/server.js

RUN cd /var/www/phpupfile && rm .git && git init . && git config --global user.email "test@example.com" && git config --global user.name test && git add . && git commit -am 'first commit'

ENTRYPOINT ["bash", "/entrypoint.sh"]
