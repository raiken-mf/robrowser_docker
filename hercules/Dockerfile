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

RUN git clone --depth 1 https://github.com/raiken-mf/Hercules.git /opt/ragnarok

COPY repository_override /opt/ragnarok/

RUN cd /opt/ragnarok && \
    if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then \
        ./configure --enable-packetver="${PACKETVER}" --with-key1="${PACKET_OBFUSCATION_KEY1}" --with-key2="${PACKET_OBFUSCATION_KEY2}" --with-key3="${PACKET_OBFUSCATION_KEY3}" --disable-renewal; \
    else \
        ./configure --enable-packetver="${PACKETVER}" --with-key1="${PACKET_OBFUSCATION_KEY1}" --with-key2="${PACKET_OBFUSCATION_KEY2}" --with-key3="${PACKET_OBFUSCATION_KEY3}"; \
    fi && \
    make clean && \
    make sql && \
    chmod a+x login-server && \
    chmod a+x char-server && \
    chmod a+x map-server

RUN mkdir -p /opt/ragnarok/conf/import/include/login-server/conf/global/
RUN cat <<EOF > /opt/ragnarok/conf/import/include/login-server/conf/global/sql_connection.conf
sql_connection: {
	db_hostname: "${MARIADB_HOST}"
	db_port: 3306
	db_username: "${MARIADB_USER}"
	db_password: "${MARIADB_PASSWORD}"
	db_database: "${MARIADB_DATABASE}"
}
EOF

RUN mkdir -p /opt/ragnarok/conf/import/include/char-server/conf/global/
RUN cat <<EOF > /opt/ragnarok/conf/import/include/char-server/conf/global/sql_connection.conf
sql_connection: {
	db_hostname: "${MARIADB_HOST}"
	db_port: 3306
	db_username: "${MARIADB_USER}"
	db_password: "${MARIADB_PASSWORD}"
	db_database: "${MARIADB_DATABASE}"
}
EOF

RUN mkdir -p /opt/ragnarok/conf/import/include/map-server/conf/global/
RUN cat <<EOF > /opt/ragnarok/conf/import/include/map-server/conf/global/sql_connection.conf
sql_connection: {
	db_hostname: "${MARIADB_HOST}"
	db_port: 3306
	db_username: "${MARIADB_USER}"
	db_password: "${MARIADB_PASSWORD}"
	db_database: "${MARIADB_DATABASE}"
}
EOF

RUN mkdir -p /opt/ragnarok/conf/import/
RUN cat <<EOF > /opt/ragnarok/conf/import/login-server.conf
login_configuration: {
    inter: {
		userid: "${SET_INTERSRV_USER}"
		passwd: "${SET_INTERSRV_PASSWORD}"
    }
	account: {
		new_account: true
	}
}
EOF

RUN mkdir -p /opt/ragnarok/conf/import/
RUN cat <<EOF > /opt/ragnarok/conf/import/char-server.conf
char_configuration: {
    inter: {
		userid: "${SET_INTERSRV_USER}"
		passwd: "${SET_INTERSRV_PASSWORD}"
        login_ip: "ragnarok_login"
    }
	pincode: {
		enabled: false
	}
}
EOF

RUN mkdir -p /opt/ragnarok/conf/import/
RUN cat <<EOF > /opt/ragnarok/conf/import/map-server.conf
map_configuration: {
    inter: {
		userid: "${SET_INTERSRV_USER}"
		passwd: "${SET_INTERSRV_PASSWORD}"
        char_ip: "ragnarok_char"
    }
}
EOF

RUN cat <<EOF > /opt/ragnarok/npc/MOTD.txt
-	script	HerculesMOTD	FAKE_NPC,{
	message strcharinfo(PC_NAME),"${SET_MOTD}";
	end;
}
EOF

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
