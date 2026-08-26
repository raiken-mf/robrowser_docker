#!/bin/sh
set -e

export HOST=${HOST:-"127.0.0.1"}
export PORT_HTTP=${PORT_HTTP:-"8080"}
export PORT_WSPROXY=${PORT_WSPROXY:-"5999"}
export PACKETVER=${PACKETVER:-"20211103"}
export PACKET_OBFUSCATION_KEY1=${PACKET_OBFUSCATION_KEY1:-"0x6DED6DEE"}
export PACKET_OBFUSCATION_KEY2=${PACKET_OBFUSCATION_KEY2:-"0x3DFD6AED"}
export PACKET_OBFUSCATION_KEY3=${PACKET_OBFUSCATION_KEY3:-"0x0A3D5C0D"}

envsubst '${HOST} ${PORT_HTTP} ${PORT_WSPROXY} ${PACKETVER} ${PACKET_OBFUSCATION_KEY1} ${PACKET_OBFUSCATION_KEY2} ${PACKET_OBFUSCATION_KEY3}' \
  < /var/www/localhost/htdocs/index.html.template \
  > /var/www/localhost/htdocs/index.html

if [ -f "/var/www/localhost/htdocs/client/tools/convert-encoding.php" ]; then
    php /var/www/localhost/htdocs/client/tools/convert-encoding.php
fi

httpd

cd /var/www/localhost/htdocs
exec npx vite --host 0.0.0.0 --port 3000 --cors --no-open
