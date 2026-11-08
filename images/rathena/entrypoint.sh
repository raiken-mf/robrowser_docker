#!/bin/sh
set -e

# Default variables if not set
export MARIADB_HOST="${MARIADB_HOST:-mariadb}"
export MARIADB_DATABASE="${MARIADB_DATABASE:-ragnarok}"
export MARIADB_USER="${MARIADB_USER:-ragnarok-user}"
export MARIADB_PASSWORD="${MARIADB_PASSWORD:-ragnarok_db_pass}"
export LOGIN_SERVER_HOST="${LOGIN_SERVER_HOST:-ragnarok-login}"
export CHAR_SERVER_HOST="${CHAR_SERVER_HOST:-ragnarok-char}"
export MAP_SERVER_HOST="${MAP_SERVER_HOST:-ragnarok-map}"
export SET_INTERSRV_USER="${SET_INTERSRV_USER:-s1}"
export SET_INTERSRV_PASSWORD="${SET_INTERSRV_PASSWORD:-p1}"
export SET_PINCODE_ENABLED="${SET_PINCODE_ENABLED:-no}"
export SET_NEW_ACCOUNT="${SET_NEW_ACCOUNT:-yes}"

# Security hardening
umask 077

TEMPLATE_DIR="/usr/local/share/rathena/templates"

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

    envsubst '${MARIADB_HOST} ${MARIADB_DATABASE} ${MARIADB_USER} ${MARIADB_PASSWORD}' \
      < "${TEMPLATE_DIR}/inter_conf.txt.template" \
      > /opt/ragnarok/conf/import/inter_conf.txt

    envsubst '${SET_INTERSRV_USER} ${SET_INTERSRV_PASSWORD} ${LOGIN_SERVER_HOST} ${CHAR_SERVER_HOST} ${SET_PINCODE_ENABLED}' \
      < "${TEMPLATE_DIR}/char_conf.txt.template" \
      > /opt/ragnarok/conf/import/char_conf.txt

    envsubst '${SET_INTERSRV_USER} ${SET_INTERSRV_PASSWORD} ${CHAR_SERVER_HOST} ${MAP_SERVER_HOST}' \
      < "${TEMPLATE_DIR}/map_conf.txt.template" \
      > /opt/ragnarok/conf/import/map_conf.txt

    envsubst '${SET_NEW_ACCOUNT}' \
      < "${TEMPLATE_DIR}/login_conf.txt.template" \
      > /opt/ragnarok/conf/import/login_conf.txt

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
