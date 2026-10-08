# alpine:3.24.2 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

ARG PACKETVER=20211103
ARG SET_PRERENEWAL=0
ARG RATHENA_REPOSITORY=https://github.com/raiken-mf/rathena.git
ARG RATHENA_REF
ARG PACKET_OBFUSCATION_KEY1=0x6DED6DEE
ARG PACKET_OBFUSCATION_KEY2=0x3DFD6AED
ARG PACKET_OBFUSCATION_KEY3=0x0A3D5C0D

ENV PACKETVER=$PACKETVER
ENV SET_PRERENEWAL=$SET_PRERENEWAL

RUN addgroup -g 1000 ragnarok && adduser -u 1000 -G ragnarok -D ragnarok

# Install build/runtime packages from the pinned Alpine release.
# zlib is upgraded explicitly to pick up the 1.3.2-r1 fix for CVE-2026-85091;
# drop this once alpine:3.24.2 ships zlib >= 1.3.2-r1 by default.
RUN apk add --no-cache \
    patch git make gcc g++ \
    mariadb-dev mariadb-connector-c mariadb-client \
    zlib-dev pcre-dev pcre libstdc++ linux-headers \
    && apk upgrade --no-cache zlib

# Build from an explicit revision so a fork sync cannot silently change an image.
RUN test -n "${RATHENA_REF}" && \
    git clone "${RATHENA_REPOSITORY}" /opt/ragnarok && \
    git -C /opt/ragnarok checkout --detach "${RATHENA_REF}"

RUN patch --ignore-whitespace /opt/ragnarok/src/custom/defines_pre.hpp <<PATCH_EOF
--- defines_post.hpp	2024-01-29 20:25:41.731355800 +0100
+++ defines_post.hpp.patch	2024-01-29 20:13:45.706997100 +0100
@@ -11,4 +11,7 @@



+#define PACKET_OBFUSCATION_KEY1 ${PACKET_OBFUSCATION_KEY1}
+#define PACKET_OBFUSCATION_KEY2 ${PACKET_OBFUSCATION_KEY2}
+#define PACKET_OBFUSCATION_KEY3 ${PACKET_OBFUSCATION_KEY3}
 #endif /* CONFIG_CUSTOM_DEFINES_PRE_HPP */
PATCH_EOF

COPY repository_override /opt/ragnarok/

RUN cd /opt/ragnarok && \
    if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then \
        ./configure --enable-packetver="${PACKETVER}" --enable-prere; \
    else \
        ./configure --enable-packetver="${PACKETVER}"; \
    fi && \
    make clean && \
    make server && \
    chmod a+x login-server char-server map-server

# Remove build-only tooling to save space
RUN apk del linux-headers pcre-dev zlib-dev mariadb-dev g++ gcc make git patch

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    mkdir -p /opt/ragnarok/conf/import && \
    chown -R ragnarok:ragnarok /opt/ragnarok

# Add security hardening
RUN chmod 755 /usr/local/bin/entrypoint.sh

USER ragnarok
WORKDIR /opt/ragnarok

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["./login-server"]
