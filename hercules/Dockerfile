FROM alpine:3.23.3

ARG PACKETVER=20211103
ARG SET_PRERENEWAL=0
ARG HERCULES_REPOSITORY=https://github.com/raiken-mf/Hercules.git
ARG HERCULES_REF
ARG PACKET_OBFUSCATION_KEY1=0x6DED6DEE
ARG PACKET_OBFUSCATION_KEY2=0x3DFD6AED
ARG PACKET_OBFUSCATION_KEY3=0x0A3D5C0D

ENV PACKETVER=$PACKETVER
ENV SET_PRERENEWAL=$SET_PRERENEWAL

RUN addgroup -S ragnarok && adduser -S ragnarok -G ragnarok && \
    apk add --no-cache \
      patch git make gcc g++ \
      mariadb-dev mariadb-connector-c mariadb-client \
      zlib-dev pcre-dev pcre libstdc++ linux-headers

# Build from an explicit revision so a fork sync cannot silently change an image.
RUN test -n "${HERCULES_REF}" && \
    git clone "${HERCULES_REPOSITORY}" /opt/ragnarok && \
    git -C /opt/ragnarok checkout --detach "${HERCULES_REF}"

COPY repository_override /opt/ragnarok/

RUN cd /opt/ragnarok && \
    if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then \
        ./configure --enable-packetver="${PACKETVER}" --with-key1="${PACKET_OBFUSCATION_KEY1}" --with-key2="${PACKET_OBFUSCATION_KEY2}" --with-key3="${PACKET_OBFUSCATION_KEY3}" --disable-renewal; \
    else \
        ./configure --enable-packetver="${PACKETVER}" --with-key1="${PACKET_OBFUSCATION_KEY1}" --with-key2="${PACKET_OBFUSCATION_KEY2}" --with-key3="${PACKET_OBFUSCATION_KEY3}"; \
    fi && \
    make clean && make sql && \
    chmod a+x login-server char-server map-server && \
    apk del linux-headers pcre-dev zlib-dev mariadb-dev g++ gcc make git patch

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh && \
    mkdir -p /opt/ragnarok/conf/import && \
    chown -R ragnarok:ragnarok /opt/ragnarok

USER ragnarok
WORKDIR /opt/ragnarok
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["./login-server"]
