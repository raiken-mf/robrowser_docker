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

export HOST="${HOST:-127.0.0.1}"
export PORT_HTTP="${PORT_HTTP:-8080}"
export PORT_WSPROXY="${PORT_WSPROXY:-5999}"
export PACKETVER="${PACKETVER:-20211103}"
export PACKET_OBFUSCATION_KEY1="${PACKET_OBFUSCATION_KEY1:-0x6DED6DEE}"
export PACKET_OBFUSCATION_KEY2="${PACKET_OBFUSCATION_KEY2:-0x3DFD6AED}"
export PACKET_OBFUSCATION_KEY3="${PACKET_OBFUSCATION_KEY3:-0x0A3D5C0D}"

# Generate configuration for existing Apache compatibility.
envsubst '${HOST} ${PORT_HTTP} ${PORT_WSPROXY} ${PACKETVER} ${PACKET_OBFUSCATION_KEY1} ${PACKET_OBFUSCATION_KEY2} ${PACKET_OBFUSCATION_KEY3}' \
  < "$ROOT/index.html.template" \
  > "$ROOT/index.html"

chmod 644 "$ROOT/index.html"

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
