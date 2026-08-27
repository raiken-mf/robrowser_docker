#!/bin/sh
set -e

# Default variables if not set
MARIADB_HOST="${MARIADB_HOST:-mariadb}"
MARIADB_DATABASE="${MARIADB_DATABASE:-ragnarok}"
MARIADB_USER="${MARIADB_USER:-ragnarok-user}"
MARIADB_PASSWORD="${MARIADB_PASSWORD:-ragnarok_db_pass}"
LOGIN_SERVER_HOST="${LOGIN_SERVER_HOST:-ragnarok-login}"
CHAR_SERVER_HOST="${CHAR_SERVER_HOST:-ragnarok-char}"
MAP_SERVER_HOST="${MAP_SERVER_HOST:-ragnarok-map}"
SET_INTERSRV_USER="${SET_INTERSRV_USER:-s1}"
SET_INTERSRV_PASSWORD="${SET_INTERSRV_PASSWORD:-p1}"

check_database_exist() {
    TABLE_COUNT=$(mariadb -u "${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -s -N -e "SELECT COUNT(DISTINCT table_name) FROM information_schema.columns WHERE table_schema = '${MARIADB_DATABASE}'" 2>/dev/null || echo 0)
    if [ "$TABLE_COUNT" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

setup_database() {
    echo "==> Checking database '${MARIADB_DATABASE}' at '${MARIADB_HOST}'..."
    if ! check_database_exist; then
        echo "==> Database empty. Initializing rAthena schema..."
        
        # Main tables
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/main.sql
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/logs.sql
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/roulette_default_data.sql
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/web.sql

        if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then
            echo "==> Importing Pre-Renewal DB files..."
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_db.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_skill_db.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_equip.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_etc.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_usable.sql
        else
            echo "==> Importing Renewal DB files..."
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_re.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_db_re.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_skill_db_re.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_re_equip.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_re_etc.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_re_usable.sql
        fi

        echo "==> Updating interserver credentials for account ID 1..."
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" \
          -e "UPDATE login SET userid = '${SET_INTERSRV_USER}', user_pass = '${SET_INTERSRV_PASSWORD}' WHERE account_id = 1;"
        echo "==> Database schema initialized successfully!"
    else
        echo "==> Database already initialized."
    fi
}

render_configs() {
    mkdir -p /opt/ragnarok/conf/import

    cat <<CONFIG_EOF > /opt/ragnarok/conf/import/inter_conf.txt
// Dynamic Runtime Config
login_server_ip: ${MARIADB_HOST}
login_server_db: ${MARIADB_DATABASE}
login_server_id: ${MARIADB_USER}
login_server_pw: ${MARIADB_PASSWORD}

map_server_ip: ${MARIADB_HOST}
map_server_db: ${MARIADB_DATABASE}
map_server_id: ${MARIADB_USER}
map_server_pw: ${MARIADB_PASSWORD}

char_server_ip: ${MARIADB_HOST}
char_server_db: ${MARIADB_DATABASE}
char_server_id: ${MARIADB_USER}
char_server_pw: ${MARIADB_PASSWORD}

ipban_db_ip: ${MARIADB_HOST}
ipban_db_db: ${MARIADB_DATABASE}
ipban_db_id: ${MARIADB_USER}
ipban_db_pw: ${MARIADB_PASSWORD}

log_db_ip: ${MARIADB_HOST}
log_db_db: ${MARIADB_DATABASE}
log_db_id: ${MARIADB_USER}
log_db_pw: ${MARIADB_PASSWORD}
CONFIG_EOF

    cat <<CONFIG_EOF > /opt/ragnarok/conf/import/char_conf.txt
userid: ${SET_INTERSRV_USER}
passwd: ${SET_INTERSRV_PASSWORD}

login_ip: ${LOGIN_SERVER_HOST}
char_ip: ${CHAR_SERVER_HOST}

pincode_enabled: ${SET_PINCODE_ENABLED:-no}
CONFIG_EOF

    cat <<CONFIG_EOF > /opt/ragnarok/conf/import/map_conf.txt
userid: ${SET_INTERSRV_USER}
passwd: ${SET_INTERSRV_PASSWORD}

char_ip: ${CHAR_SERVER_HOST}
map_ip: ${MAP_SERVER_HOST}
CONFIG_EOF

    cat <<CONFIG_EOF > /opt/ragnarok/conf/import/login_conf.txt
new_account: ${SET_NEW_ACCOUNT:-yes}
CONFIG_EOF

    if [ -n "${SET_MOTD:-}" ]; then
        printf "%s" "${SET_MOTD}" > /opt/ragnarok/conf/motd.txt
    fi
}

# 1. Render configurations
render_configs

# 2. Check and migrate database if requested or needed
if [ "${INIT_DB:-true}" = "true" ]; then
    setup_database
fi

# 3. Start specified command or default to shell
exec "$@"
