#!/bin/sh
set -eu

umask 077

case "${ROBROWSER_ROLE:-web}" in
  web) ;;
  *)
    echo "Unsupported ROBROWSER_ROLE for Apache image" >&2
    exit 1
    ;;
esac

ROOT="/var/www/localhost/htdocs"

# Merge optional loose-file mounts after the baked translations. Empty mounts
# preserve the translated base; user files take precedence without hiding it.
for directory in data System; do
  if [ -d "/opt/client_files/$directory" ]; then
    cp -R "/opt/client_files/$directory/." "$ROOT/remote/$directory/"
  fi
done

# Generate encoding mappings when client resources are mounted.
if [ -f "$ROOT/remote/tools/convert-encoding.php" ] && \
   [ -f "/opt/client_files/resources/DATA.INI" ]; then
  (cd "$ROOT/remote" && php tools/convert-encoding.php)
else
  echo "Skipping encoding mapping: DATA.INI not mounted."
fi

echo "Starting Apache on port 8080..."
exec httpd -D FOREGROUND
