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
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/main.sql
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/logs.sql
        
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/roulette_default_data.sql
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/web.sql

        if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then
            # Main Pre-Renewal
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_db.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_skill_db.sql

            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_equip.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_etc.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_usable.sql

            # Custom Renewal Hercules
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db2.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_db2.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_skill_db2.sql
        else
            # Main Renewal
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_re.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_db_re.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_skill_db_re.sql

            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_re_equip.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_re_etc.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db_re_usable.sql
            # Custom Renewal rAthena
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/item_db2_re.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_db2_re.sql
            mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" < /opt/ragnarok/sql-files/mob_skill_db2_re.sql          
        fi
        
        mariadb -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" -h "${MARIADB_HOST}" -D"${MARIADB_DATABASE}" -e "UPDATE login SET userid = \"${SET_INTERSRV_USER}\", user_pass = \"${SET_INTERSRV_PASSWORD}\" WHERE account_id = 1;"
        
    #       if ! [ -z ${DB_ACCOUNTSANDCHARS} ]; then
    #           if [ ${DB_ACCOUNTSANDCHARS} -ne 0 ]; then
    #               mariadb -u${MARIADB_USER} -p${MARIADB_PASSWORD} -h ${MARIADB_HOST} -D${MARIADB_DATABASE} < /root/accountsandchars.sql
    #           fi
    #       fi
    fi
}

#enable_custom_npc () {
#    echo -e "npc: npc/custom/gab_npc.txt" >> /opt/ragnarok/npc/scripts_custom.conf
#}
  
## if ! [ -z "${ADD_SUBNET_MAP1}" ]; then echo -e "subnet: ${ADD_SUBNET_MAP1}" >> /opt/ragnarok/conf/subnet_athena.conf; fi
## if ! [ -z "${ADD_SUBNET_MAP2}" ]; then echo -e "subnet: ${ADD_SUBNET_MAP2}" >> /opt/ragnarok/conf/subnet_athena.conf; fi
## if ! [ -z "${ADD_SUBNET_MAP3}" ]; then echo -e "subnet: ${ADD_SUBNET_MAP3}" >> /opt/ragnarok/conf/subnet_athena.conf; fi
## if ! [ -z "${ADD_SUBNET_MAP4}" ]; then echo -e "subnet: ${ADD_SUBNET_MAP4}" >> /opt/ragnarok/conf/subnet_athena.conf; fi
## if ! [ -z "${ADD_SUBNET_MAP5}" ]; then echo -e "subnet: ${ADD_SUBNET_MAP5}" >> /opt/ragnarok/conf/subnet_athena.conf; fi

#if [ -n "${SET_SERVER_NAME}" ]; then printf "server_name: %s" "${SET_SERVER_NAME}" >> /opt/ragnarok/conf/import/char_conf.txt; fi
#if [ -n "${SET_MAX_CONNECT_USER}" ]; then printf "max_connect_user: %s" "${SET_MAX_CONNECT_USER}" >> /opt/ragnarok/conf/import/char_conf.txt; fi
#if [ -n "${SET_START_ZENNY}" ]; then printf "start_zenny: %s" "${SET_START_ZENNY}" >> /opt/ragnarok/conf/import/char_conf.txt; fi
#if [ -n "${SET_START_POINT}" ]; then printf "start_point: %s" "${SET_START_POINT}" >> /opt/ragnarok/conf/import/char_conf.txt; fi
#if [ -n "${SET_START_POINT_PRE}" ]; then printf "start_point_pre: %s" "${SET_START_POINT_PRE}" >> /opt/ragnarok/conf/import/char_conf.txt; fi
#if [ -n "${SET_START_POINT_DORAM}" ]; then printf "start_point_doram: %s" "${SET_START_POINT_DORAM}" >> /opt/ragnarok/conf/import/char_conf.txt; fi
#if [ -n "${SET_START_ITEMS}" ]; then printf "start_items: %s" "${SET_START_ITEMS}" >> /opt/ragnarok/conf/import/char_conf.txt; fi
#if [ -n "${SET_START_ITEMS_DORAM}" ]; then printf "start_items_doram: %s" "${SET_START_ITEMS_DORAM}" >> /opt/ragnarok/conf/import/char_conf.txt; fi
#if [ -n "${SET_PINCODE_ENABLED}" ]; then printf "pincode_enabled: %s" "${SET_PINCODE_ENABLED}" >> /opt/ragnarok/conf/import/char_conf.txt; fi

#if [ -n "${SET_ALLOWED_REGS}" ]; then printf "allowed_regs: %s" "${SET_ALLOWED_REGS}" >> /opt/ragnarok/conf/import/login_conf.txt; fi
#if [ -n "${SET_TIME_ALLOWED}" ]; then printf "time_allowed: %s" "${SET_TIME_ALLOWED}" >> /opt/ragnarok/conf/import/login_conf.txt; fi

#if [ -n "${SET_ARROW_DECREMENT}" ]; then printf "arrow_decrement: %s" "${SET_ARROW_DECREMENT}" >> /opt/ragnarok/conf/import/battle_conf.txt; fi

#sed -i "s|MARIADB_HOST|${MARIADB_HOST}|g" /opt/ragnarok/conf/import/inter_conf.txt
#sed -i "s|MARIADB_DATABASE|${MARIADB_DATABASE}|g" /opt/ragnarok/conf/import/inter_conf.txt
#sed -i "s|MARIADB_USER|${MARIADB_USER}|g" /opt/ragnarok/conf/import/inter_conf.txt
#sed -i "s|MARIADB_PASSWORD|${MARIADB_PASSWORD}|g" /opt/ragnarok/conf/import/inter_conf.txt

#enable_custom_npc () {
#    echo -e "npc: npc/custom/gab_npc.txt" >> /opt/ragnarok/npc/scripts_custom.conf
#}