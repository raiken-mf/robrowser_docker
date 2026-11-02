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

# Generate encoding mappings when client resources are mounted.
if [ -f "$ROOT/remote/tools/convert-encoding.php" ] && \
   [ -f "/opt/client_files/resources/DATA.INI" ]; then
  (cd "$ROOT/remote" && php tools/convert-encoding.php)
else
  echo "Skipping encoding mapping: DATA.INI not mounted."
fi

echo "Starting Apache on port 8080..."
exec httpd -D FOREGROUND
