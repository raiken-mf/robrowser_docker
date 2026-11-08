#!/usr/bin/env bash
set -euo pipefail
apache_image="${1:-remote:ci}"
vite_image="${2:-robrowser:ci}"

docker run --rm --network none --entrypoint sh "$apache_image" -ec '
  root=/var/www/localhost/htdocs
  test -f "$root/remote/index.php"
  test -f "$root/remote/.htaccess"
  test -f /etc/apache2/httpd.conf
  test -f /etc/apache2/conf.d/robrowser-access.conf
  test -f /etc/php84/conf.d/99-robrowser-security.ini
  apache_check=$(httpd -t 2>&1)
  printf "%s\n" "$apache_check" | grep -Fq "Syntax OK"
  ! printf "%s\n" "$apache_check" | grep -Fq "AH01574"
  for file in src applications vite.config.js package.json package-lock.json index.html.template; do
    test ! -e "$root/$file"
  done
  ! command -v node
  ! command -v npm
'
# Also reject a frontend checkout hidden in an earlier image layer.
history=$(docker history --no-trunc --format '{{.CreatedBy}}' "$apache_image")
if grep -Eq 'ROBROWSER_(REF|REPOSITORY)|/roBrowserLegacy\.git' <<< "$history"; then
  echo 'Apache image history contains a frontend build dependency' >&2
  exit 1
fi

docker run --rm --network none --entrypoint sh "$vite_image" -ec '
  test -d /app/src
  test -f /app/applications/api/api.js
  test -f /app/index.html.template
  test -f /app/vite.config.js
  test -f /app/vite.upstream.config.js
  ! command -v php
  ! command -v httpd
'
echo 'Image filesystem and build-history boundaries passed'
