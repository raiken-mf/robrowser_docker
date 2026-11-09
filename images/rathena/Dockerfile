# alpine:3.24.3 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

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
# drop this once alpine:3.24.3 ships zlib >= 1.3.2-r1 by default.
RUN apk add --no-cache \
    gettext-envsubst git make gcc g++ \
    mariadb-dev mariadb-connector-c mariadb-client \
    zlib-dev pcre-dev pcre libstdc++ linux-headers \
    && apk upgrade --no-cache zlib

# Validate build arguments and clone the explicit pinned upstream revision.
RUN set -eu; \
    test -n "${RATHENA_REF}"; \
    case "${PACKETVER}" in *[!0-9]*) exit 1 ;; esac; \
    printf '%s' "${PACKETVER}" | grep -Eq '^[0-9]{8}$'; \
    if [ -n "${SET_PRERENEWAL}" ]; then [ "${SET_PRERENEWAL}" -eq 0 ] || [ "${SET_PRERENEWAL}" -ne 0 ]; fi; \
    for key in "${PACKET_OBFUSCATION_KEY1}" "${PACKET_OBFUSCATION_KEY2}" "${PACKET_OBFUSCATION_KEY3}"; do \
        case "$key" in *[!0-9a-fA-FxX]*) exit 1 ;; esac; \
        printf '%s' "$key" | grep -Eq '^0[xX][0-9a-fA-F]{1,8}$' || exit 1; \
    done && \
    git clone "${RATHENA_REPOSITORY}" /opt/ragnarok && \
    git -C /opt/ragnarok checkout --detach "${RATHENA_REF}"

COPY templates/ /usr/local/share/rathena/templates/
COPY repository_override /opt/ragnarok/

RUN test -f /opt/ragnarok/src/custom/defines_pre.hpp && \
    mv /opt/ragnarok/src/custom/defines_pre.hpp /opt/ragnarok/src/custom/defines_pre_upstream.hpp && \
    PACKET_OBFUSCATION_KEY1="${PACKET_OBFUSCATION_KEY1}" \
    PACKET_OBFUSCATION_KEY2="${PACKET_OBFUSCATION_KEY2}" \
    PACKET_OBFUSCATION_KEY3="${PACKET_OBFUSCATION_KEY3}" \
    envsubst '${PACKET_OBFUSCATION_KEY1} ${PACKET_OBFUSCATION_KEY2} ${PACKET_OBFUSCATION_KEY3}' \
      < /usr/local/share/rathena/templates/defines_pre.hpp.template \
      > /opt/ragnarok/src/custom/defines_pre.hpp

RUN cd /opt/ragnarok && \
    if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then \
        ./configure --enable-packetver="${PACKETVER}" --enable-prere; \
    else \
        ./configure --enable-packetver="${PACKETVER}"; \
    fi && \
    make clean && \
    make server && \
    chmod a+x login-server char-server map-server && \
    rm -rf /opt/ragnarok/.git && \
    apk del linux-headers pcre-dev zlib-dev mariadb-dev g++ gcc make git

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
RUN mkdir -p /opt/ragnarok/conf/import && \
    chown -R ragnarok:ragnarok /opt/ragnarok

USER ragnarok
WORKDIR /opt/ragnarok

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["./login-server"]
