# alpine:3.24.3 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

ARG REMOTECLIENT_REPOSITORY=https://github.com/raiken-mf/roBrowserLegacy-RemoteClient-PHP.git
ARG REMOTECLIENT_REF
ARG ROENGLISH_REPOSITORY=https://github.com/raiken-mf/ROenglishRE.git
ARG ROENGLISH_REF

# Install runtime/build packages from the pinned Alpine release.
# Bind the generic CLI explicitly to PHP 8.4; Alpine 3.24 does not provide
# the unversioned php executable when installing the non-default PHP branch.
# zlib is upgraded explicitly to pick up the 1.3.2-r1 fix for CVE-2026-85091;
# drop this once alpine:3.24.3 ships zlib >= 1.3.2-r1 by default.
RUN apk add --no-cache \
    apache2 \
    'php84>=8.4.27' \
    php84-apache2 \
    php84-mbstring \
    php84-iconv \
    php84-gd \
    php84-zlib \
    git \
    && apk upgrade --no-cache zlib \
    && test -x /usr/bin/php84 \
    && ln -sf /usr/bin/php84 /usr/bin/php \
    && rm -rf /var/www/localhost/htdocs/*

# Stay on PHP 8.4 while accepting patched releases from Alpine. Reject old
# packages even if the package selection or repository configuration changes.
RUN php -r 'if (PHP_VERSION_ID < 80427 || PHP_VERSION_ID >= 80500) { fwrite(STDERR, "PHP 8.4.27 or newer in the 8.4 branch is required\n"); exit(1); }'
COPY images/remote/security.ini /etc/php84/conf.d/99-robrowser-security.ini
# Alpine packages the session extension separately; also check the configured
# value when the extension is absent so installing it later remains safe.
RUN php -r 'if (get_cfg_var("session.upload_progress.enabled") !== "0" || (extension_loaded("session") && ini_get("session.upload_progress.enabled") !== "0")) { fwrite(STDERR, "Session upload progress must be disabled\n"); exit(1); }'

# Configure Apache to unprivileged port 8080 & PHP runtime settings
RUN sed -i 's/Listen 80/Listen 8080/g' /etc/apache2/httpd.conf && \
    sed -i 's/:80/:8080/g' /etc/apache2/httpd.conf && \
    echo "LoadModule rewrite_module modules/mod_rewrite.so" >> /etc/apache2/httpd.conf && \
    echo "LoadModule headers_module modules/mod_headers.so" >> /etc/apache2/httpd.conf && \
    sed -i "s|AllowOverride None|AllowOverride All|g" /etc/apache2/httpd.conf && \
    echo "TraceEnable Off" >> /etc/apache2/httpd.conf && \
    echo "ServerName localhost" >> /etc/apache2/httpd.conf && \
    echo 'Header onsuccess unset Access-Control-Allow-Origin' >> /etc/apache2/httpd.conf && \
    echo 'Header always unset Access-Control-Allow-Origin' >> /etc/apache2/httpd.conf && \
    echo 'Header set Access-Control-Allow-Origin "*"' >> /etc/apache2/httpd.conf && \
    echo 'Header set Access-Control-Allow-Methods "GET, POST, OPTIONS"' >> /etc/apache2/httpd.conf && \
    echo 'Header set Access-Control-Allow-Headers "*"' >> /etc/apache2/httpd.conf && \
    PHP_INI="$(php --ini | sed -n 's/^Loaded Configuration File: *//p')" && \
    test -f "$PHP_INI" && \
    sed -i "s/memory_limit = .*/memory_limit = 1024M/g" "$PHP_INI" && \
    sed -i "s/max_execution_time = .*/max_execution_time = 600/g" "$PHP_INI" && \
    sed -i 's/^User .*/User robrowser/' /etc/apache2/httpd.conf && \
    sed -i 's/^Group .*/Group robrowser/' /etc/apache2/httpd.conf

# The Apache image has no dependency on roBrowserLegacy frontend sources.
RUN test -n "${REMOTECLIENT_REF}" && test -n "${ROENGLISH_REF}" && \
    git clone "${REMOTECLIENT_REPOSITORY}" /var/www/localhost/htdocs/remote && \
    git -C /var/www/localhost/htdocs/remote checkout --detach "${REMOTECLIENT_REF}"

# Fetch ROEnglishRE translations.
# Renewal is the base; Pre-Renewal overrides it when enabled.
ARG SET_PRERENEWAL=0
RUN set -eu; \
    git clone "${ROENGLISH_REPOSITORY}" /opt/translation; \
    git -C /opt/translation checkout --detach "${ROENGLISH_REF}"; \
    test -d /opt/translation/Translation; \
    mkdir -p /var/www/localhost/htdocs/remote/data \
             /var/www/localhost/htdocs/remote/SystemEN; \
    case "${SET_PRERENEWAL}" in 0|1) ;; *) echo "SET_PRERENEWAL must be 0 or 1" >&2; exit 1 ;; esac; \
    layers="Renewal"; \
    if [ "${SET_PRERENEWAL}" = "1" ]; then \
        layers="$layers Pre-Renewal"; \
    fi; \
    for layer in $layers; do \
        src="/opt/translation/Translation/$layer"; \
        test -d "$src/data"; \
        test -d "$src/SystemEN"; \
        if [ -d "$src/data" ]; then \
            cp -a "$src/data/." /var/www/localhost/htdocs/remote/data/; \
        fi; \
        if [ -d "$src/SystemEN" ]; then \
            cp -a "$src/SystemEN/." /var/www/localhost/htdocs/remote/SystemEN/; \
        elif [ -d "$src/system" ]; then \
            cp -a "$src/system/." /var/www/localhost/htdocs/remote/SystemEN/; \
        fi; \
    done; \
    rm -rf /opt/translation

# The shared policy blocks direct access and routes resources before Apache
# normalizes requests. It does not depend on per-directory .htaccess rules.
RUN cp /var/www/localhost/htdocs/remote/apache/remote-security.conf /etc/apache2/remote-security.conf \
    && printf 'Define RC_BASE /remote/\nDefine RC_DIR /var/www/localhost/htdocs/remote\nInclude /etc/apache2/remote-security.conf\n' >> /etc/apache2/httpd.conf

# A real System file wins; SystemEN is a virtual fallback for missing System files.
ENV DATA_OVERRIDE_PATH=/opt/client_files/data SYSTEM_PATH=/opt/client_files/System \
    SYSTEMEN_PATH=/opt/client_files/SystemEN AI_PATH=/opt/client_files/AI \
    BGM_PATH=/opt/client_files/BGM SYSTEM_ALIAS_SYSTEMEN=true

# Prepare symlinks for optional external mounts (GRFs, BGM, AI)
RUN mkdir -p /opt/client_files/resources /opt/client_files/BGM /opt/client_files/AI && \
    rm -rf /var/www/localhost/htdocs/remote/resources /var/www/localhost/htdocs/remote/BGM && \
    ln -s /opt/client_files/resources /var/www/localhost/htdocs/remote/resources && \
    ln -s /opt/client_files/BGM /var/www/localhost/htdocs/remote/BGM && \
    ln -s /opt/client_files/AI /var/www/localhost/htdocs/AI && \
    ln -s /opt/client_files/AI /var/www/localhost/htdocs/remote/AI


# Static service status, custom overrides, and startup entrypoint
COPY images/remote/index.html /var/www/localhost/htdocs/index.html
COPY images/remote/repository_override/ /var/www/localhost/htdocs/
COPY images/remote/entrypoint.sh /entrypoint.sh

# Create non-root user and set permissions for runtime directories
RUN addgroup -g 1000 robrowser && \
    adduser -u 1000 -G robrowser -D robrowser && \
    mkdir -p /run/apache2 /var/log/apache2 && \
    chown -R robrowser:robrowser /var/www/localhost/htdocs /opt/client_files /run/apache2 /var/log/apache2 && \
    chmod 755 /entrypoint.sh

RUN rm -rf /var/www/localhost/htdocs/.git /var/www/localhost/htdocs/remote/.git \
    && echo 'RedirectMatch 404 /\.git' >> /etc/apache2/httpd.conf

USER robrowser
WORKDIR /var/www/localhost/htdocs

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
