#!/bin/sh
set -eu

# Runtime configuration and database setup. Secrets are read only at container runtime.
umask 077

: "${MARIADB_HOST:=database}"
: "${MARIADB_DATABASE:=ragnarok}"
: "${MARIADB_USER:=ragnarok}"
: "${MARIADB_PASSWORD:?MARIADB_PASSWORD must be set}"
: "${SET_INTERSRV_USER:=s1}"
: "${SET_INTERSRV_PASSWORD:?SET_INTERSRV_PASSWORD must be set}"
: "${SET_MOTD:=Welcome}"
: "${SET_PRERENEWAL:=0}"

sql_hex() {
  printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
}

config_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

carriage_return=$(printf '\r')
for value in "$MARIADB_HOST" "$MARIADB_DATABASE" "$MARIADB_USER" "$MARIADB_PASSWORD" "$SET_INTERSRV_USER" "$SET_INTERSRV_PASSWORD" "$SET_MOTD"; do
  case "$value" in *"$carriage_return"*|*'
'*) echo 'Configuration values must not contain line breaks' >&2; exit 1 ;; esac
done
case "$SET_PRERENEWAL" in 0|1) ;; *) echo 'SET_PRERENEWAL must be 0 or 1' >&2; exit 1 ;; esac
export MYSQL_PWD="$MARIADB_PASSWORD"

check_database_exist() {
  database_hex=$(sql_hex "$MARIADB_DATABASE")
  table_count=$(mariadb -u "$MARIADB_USER" -h "$MARIADB_HOST" -s -N \
    -e "SELECT COUNT(DISTINCT table_name) FROM information_schema.columns WHERE table_schema = CONVERT(UNHEX('${database_hex}') USING utf8mb4)") || return 2
  case "$table_count" in ''|*[!0-9]*) return 2 ;; esac
  [ "$table_count" -gt 0 ]
}

setup_database() {
  result=0
  check_database_exist || result=$?
  [ "$result" -ne 2 ] || { echo 'Database check failed' >&2; return 1; }
  if [ "$result" -eq 0 ]; then
    echo "Database already initialized."
    return 0
  fi

  echo "Initializing Hercules database schema..."
  set -- mariadb -u "$MARIADB_USER" -h "$MARIADB_HOST" -D "$MARIADB_DATABASE"
  "$@" < /opt/ragnarok/sql-files/main.sql
  "$@" < /opt/ragnarok/sql-files/logs.sql
  if [ "$SET_PRERENEWAL" -ne 0 ]; then
    "$@" < /opt/ragnarok/sql-files/item_db.sql
    "$@" < /opt/ragnarok/sql-files/mob_db.sql
    "$@" < /opt/ragnarok/sql-files/mob_skill_db.sql
  else
    "$@" < /opt/ragnarok/sql-files/item_db_re.sql
    "$@" < /opt/ragnarok/sql-files/mob_db_re.sql
    "$@" < /opt/ragnarok/sql-files/mob_skill_db_re.sql
  fi
  "$@" < /opt/ragnarok/sql-files/item_db2.sql
  "$@" < /opt/ragnarok/sql-files/mob_db2.sql
  "$@" < /opt/ragnarok/sql-files/mob_skill_db2.sql
  interserver_user_hex=$(sql_hex "$SET_INTERSRV_USER")
  interserver_password_hex=$(sql_hex "$SET_INTERSRV_PASSWORD")
  printf '%s\n' "UPDATE login SET userid = CONVERT(UNHEX('${interserver_user_hex}') USING utf8mb4), user_pass = CONVERT(UNHEX('${interserver_password_hex}') USING utf8mb4) WHERE account_id = 1;" | "$@"
}

render_configs() {
  db_host=$(config_escape "$MARIADB_HOST")
  db_user=$(config_escape "$MARIADB_USER")
  db_password=$(config_escape "$MARIADB_PASSWORD")
  db_name=$(config_escape "$MARIADB_DATABASE")
  inter_user=$(config_escape "$SET_INTERSRV_USER")
  inter_password=$(config_escape "$SET_INTERSRV_PASSWORD")
  motd=$(config_escape "$SET_MOTD")
  cat > /opt/ragnarok/conf/global/sql_connection.conf <<EOF
sql_connection: {
  db_hostname: "${db_host}"
  db_port: 3306
  db_username: "${db_user}"
  db_password: "${db_password}"
  db_database: "${db_name}"
}
EOF

  cat > /opt/ragnarok/conf/import/login-server.conf <<EOF
login_configuration: {
  console: { console_silent: 5 console_msg_log: 0 }
  account: { new_account: true }
}
EOF
  cat > /opt/ragnarok/conf/import/char-server.conf <<EOF
char_configuration: {
  inter: { userid: "${inter_user}" passwd: "${inter_password}" login_ip: "ragnarok-login" }
  pincode: { enabled: false }
}
EOF
  cat > /opt/ragnarok/conf/import/map-server.conf <<EOF
map_configuration: {
  inter: { userid: "${inter_user}" passwd: "${inter_password}" char_ip: "ragnarok-char" }
}
EOF
  cat > /opt/ragnarok/npc/MOTD.txt <<EOF
- script HerculesMOTD FAKE_NPC,{ message strcharinfo(PC_NAME),"${motd}"; end; }
EOF
}

render_configs
if [ "${INIT_DB:-false}" = "true" ]; then
  setup_database
fi
unset MYSQL_PWD
if [ "${INIT_ONLY:-false}" = "true" ]; then
  exit 0
fi
exec "$@"
