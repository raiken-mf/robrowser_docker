FROM alpine:latest

ARG PACKETVER
ARG SET_PRERENEWAL
ARG PACKET_OBFUSCATION_KEY1
ARG PACKET_OBFUSCATION_KEY2
ARG PACKET_OBFUSCATION_KEY3
ARG MARIADB_HOST
ARG MARIADB_DATABASE
ARG MARIADB_USER
ARG MARIADB_PASSWORD
ARG SET_INTERSRV_USER
ARG SET_INTERSRV_PASSWORD
ARG SET_MOTD

ENV PACKETVER=$PACKETVER
ENV SET_PRERENEWAL=$SET_PRERENEWAL
ENV PACKET_OBFUSCATION_KEY1=$PACKET_OBFUSCATION_KEY1
ENV PACKET_OBFUSCATION_KEY2=$PACKET_OBFUSCATION_KEY2
ENV PACKET_OBFUSCATION_KEY3=$PACKET_OBFUSCATION_KEY3
ENV MARIADB_HOST=$MARIADB_HOST
ENV MARIADB_DATABASE=$MARIADB_DATABASE
ENV MARIADB_USER=$MARIADB_USER
ENV MARIADB_PASSWORD=$MARIADB_PASSWORD
ENV SET_INTERSRV_USER=$SET_INTERSRV_USER
ENV SET_INTERSRV_PASSWORD=$SET_INTERSRV_PASSWORD
ENV SET_MOTD=$SET_MOTD

RUN addgroup -S ragnarok && adduser -S ragnarok -G ragnarok

RUN apk update
RUN apk add --no-cache patch
RUN apk add --no-cache git
RUN apk add --no-cache make
RUN apk add --no-cache gcc
RUN apk add --no-cache g++
RUN apk add --no-cache mariadb-dev
RUN apk add --no-cache mariadb-connector-c
RUN apk add --no-cache mariadb-client
RUN apk add --no-cache zlib-dev
RUN apk add --no-cache pcre-dev
RUN apk add --no-cache pcre
RUN apk add --no-cache libstdc++
RUN apk add --no-cache linux-headers

RUN git clone https://github.com/rathena/rathena.git /opt/ragnarok

RUN patch --ignore-whitespace /opt/ragnarok/src/custom/defines_pre.hpp <<EOF
--- defines_post.hpp	2024-01-29 20:25:41.731355800 +0100
+++ defines_post.hpp.patch	2024-01-29 20:13:45.706997100 +0100
@@ -11,4 +11,7 @@



+#define PACKET_OBFUSCATION_KEY1 ${PACKET_OBFUSCATION_KEY1}
+#define PACKET_OBFUSCATION_KEY2 ${PACKET_OBFUSCATION_KEY2}
+#define PACKET_OBFUSCATION_KEY3 ${PACKET_OBFUSCATION_KEY3}
 #endif /* CONFIG_CUSTOM_DEFINES_PRE_HPP */
\ No newline at end of file

EOF

COPY repository_override /opt/ragnarok/

RUN cd /opt/ragnarok && \
    if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then \
        ./configure --enable-packetver="${PACKETVER}" --enable-prere; \
    else \
        ./configure --enable-packetver="${PACKETVER}"; \
    fi && \
    make clean && \
    make server && \
    chmod a+x login-server && \
    chmod a+x char-server && \
    chmod a+x map-server

RUN mkdir -p /opt/ragnarok/conf/import

RUN cat <<EOF > /opt/ragnarok/conf/import/login_conf.txt
new_account: yes
EOF

RUN cat <<EOF > /opt/ragnarok/conf/import/inter_conf.txt
use_sql_db: yes

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
EOF

RUN cat <<EOF > /opt/ragnarok/conf/import/char_conf.txt
userid: ${SET_INTERSRV_USER}
passwd: ${SET_INTERSRV_PASSWORD}

login_ip: ragnarok_login
char_ip: ragnarok_char

pincode_enabled: no
EOF

RUN cat <<EOF > /opt/ragnarok/conf/import/map_conf.txt
userid: ${SET_INTERSRV_USER}
passwd: ${SET_INTERSRV_PASSWORD}

char_ip: ragnarok_char
map_ip: ragnarok_map
EOF

RUN printf "%s" "${SET_MOTD}" > /opt/ragnarok/conf/motd.txt

RUN apk del linux-headers
RUN apk del pcre-dev 
RUN apk del zlib-dev 
RUN apk del mariadb-dev 
RUN apk del g++
RUN apk del gcc
RUN apk del make
RUN apk del git
RUN apk del patch

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /opt/ragnarok