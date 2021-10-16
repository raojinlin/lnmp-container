#!/bin/bash


set -m
echo "start nginx...."
nginx -g 'daemon off;' &

mkdir -v /var/run/mysqld
chmod 777 /var/run/mysqld
chown www-data:www-data /var/www/phpupfile

echo "start mysql..."
/usr/sbin/mysqld --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib/mysql/plugin --log-error=/var/log/mysql/error.log --pid-file=/var/run/mysqld/mysqld.pid --socket=/var/run/mysqld/mysqld.sock &

echo "start php-fpm..."
php-fpm7.2 -F &

echo "start nodejs server";
node /var/www/nodejs/server.js &


sleep 5;

mysql -e "CREATE USER 'upfile'@'localhost' IDENTIFIED BY 'MyPassword'"
mysql -e 'CREATE DATABASE mydb';
mysql -e "GRANT ALL ON mydb.* TO 'upfile'@'localhost'"
cat /var/www/phpupfile/schema/photos.sql | mysql --database mydb


echo "running"
jobs -l

fg %1
