#!/bin/sh
check_database_exist () {
    TABLE_COUNT=$(mariadb -u "${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -s -N -e "SELECT COUNT(DISTINCT table_name) FROM information_schema.columns WHERE table_schema = '${MARIADB_DATABASE}'")
    if [ ! "$TABLE_COUNT" -gt 0 ]; then
        return 1
    fi
}

setup_database () {
    if ! check_database_exist; then
         # Main
        mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/main.sql
        mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/logs.sql

        if [ ! -z ${SET_PRERENEWAL} ] && [ ${SET_PRERENEWAL} -ne 0 ]; then
            # Main Pre-Renewal
            mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/item_db.sql
            mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/mob_db.sql
            mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/mob_skill_db.sql
        else
            # Main Renewal
            mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/item_db_re.sql
            mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/mob_db_re.sql
            mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/mob_skill_db_re.sql
        fi
        
        # Custom
        mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/item_db2.sql
        mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/mob_db2.sql
        mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /opt/ragnarok/sql-files/mob_skill_db2.sql   
        
        mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} -e "UPDATE login SET userid = \"${SET_INTERSRV_USER}\", user_pass = \"${SET_INTERSRV_PASSWORD}\" WHERE account_id = 1;"
    fi
}