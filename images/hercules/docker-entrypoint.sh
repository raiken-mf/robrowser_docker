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

check_database_exist() {
  table_count=$(mariadb -u "${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -s -N \
    -e "SELECT COUNT(DISTINCT table_name) FROM information_schema.columns WHERE table_schema = '${MARIADB_DATABASE}'" 2>/dev/null || echo 0)
  [ "$table_count" -gt 0 ]
}

setup_database() {
  if check_database_exist; then
    echo "Database already initialized."
    return 0
  fi

  echo "Initializing Hercules database schema..."
  db="mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE}"
  $db < /opt/ragnarok/sql-files/main.sql
  $db < /opt/ragnarok/sql-files/logs.sql
  if [ "$SET_PRERENEWAL" -ne 0 ]; then
    $db < /opt/ragnarok/sql-files/item_db.sql
    $db < /opt/ragnarok/sql-files/mob_db.sql
    $db < /opt/ragnarok/sql-files/mob_skill_db.sql
  else
    $db < /opt/ragnarok/sql-files/item_db_re.sql
    $db < /opt/ragnarok/sql-files/mob_db_re.sql
    $db < /opt/ragnarok/sql-files/mob_skill_db_re.sql
  fi
  $db < /opt/ragnarok/sql-files/item_db2.sql
  $db < /opt/ragnarok/sql-files/mob_db2.sql
  $db < /opt/ragnarok/sql-files/mob_skill_db2.sql
  $db -e "UPDATE login SET userid = '${SET_INTERSRV_USER}', user_pass = '${SET_INTERSRV_PASSWORD}' WHERE account_id = 1;"
}

render_configs() {
  for server in login-server char-server map-server; do
    mkdir -p "/opt/ragnarok/conf/import/include/${server}/conf/global"
    cat > "/opt/ragnarok/conf/import/include/${server}/conf/global/sql_connection.conf" <<EOF
sql_connection: {
  db_hostname: "${MARIADB_HOST}"
  db_port: 3306
  db_username: "${MARIADB_USER}"
  db_password: "${MARIADB_PASSWORD}"
  db_database: "${MARIADB_DATABASE}"
}
EOF
  done

  cat > /opt/ragnarok/conf/import/login-server.conf <<EOF
login_configuration: {
  inter: { userid: "${SET_INTERSRV_USER}" passwd: "${SET_INTERSRV_PASSWORD}" }
  account: { new_account: true }
}
EOF
  cat > /opt/ragnarok/conf/import/char-server.conf <<EOF
char_configuration: {
  inter: { userid: "${SET_INTERSRV_USER}" passwd: "${SET_INTERSRV_PASSWORD}" login_ip: "ragnarok-login" }
  pincode: { enabled: false }
}
EOF
  cat > /opt/ragnarok/conf/import/map-server.conf <<EOF
map_configuration: {
  inter: { userid: "${SET_INTERSRV_USER}" passwd: "${SET_INTERSRV_PASSWORD}" char_ip: "ragnarok-char" }
}
EOF
  cat > /opt/ragnarok/npc/MOTD.txt <<EOF
- script HerculesMOTD FAKE_NPC,{ message strcharinfo(PC_NAME),"${SET_MOTD}"; end; }
EOF
}

render_configs
if [ "${INIT_DB:-false}" = "true" ]; then
  setup_database
fi
if [ "${INIT_ONLY:-false}" = "true" ]; then
  exit 0
fi
exec "$@"
