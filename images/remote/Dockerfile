# alpine:3.24.3 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a AS sources

ARG REMOTECLIENT_REPOSITORY=https://github.com/raiken-mf/roBrowserLegacy-RemoteClient-PHP.git
ARG REMOTECLIENT_REF
ARG ROENGLISH_REPOSITORY=https://github.com/raiken-mf/ROenglishRE.git
ARG ROENGLISH_REF

RUN apk add --no-cache git && \
    test -n "${REMOTECLIENT_REF}" && test -n "${ROENGLISH_REF}" && \
    git clone "${REMOTECLIENT_REPOSITORY}" /remote && \
    git -C /remote checkout --detach "${REMOTECLIENT_REF}" && \
    rm -rf /remote/.git && \
    git clone "${ROENGLISH_REPOSITORY}" /translation && \
    git -C /translation checkout --detach "${ROENGLISH_REF}" && \
    test -d /translation/Translation && \
    rm -rf /translation/.git

FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

# Install runtime packages from the pinned Alpine release.
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
    && apk upgrade --no-cache zlib \
    && test -x /usr/bin/php84 \
    && ln -sf /usr/bin/php84 /usr/bin/php \
    && rm -rf /var/www/localhost/htdocs/*

# Stay on PHP 8.4 while accepting patched releases from Alpine. Reject old
# packages even if the package selection or repository configuration changes.
COPY images/remote/security.ini /etc/php84/conf.d/99-robrowser-security.ini
RUN php -r '$ini = parse_ini_file("/etc/php84/conf.d/99-robrowser-security.ini"); if (PHP_VERSION_ID < 80427 || PHP_VERSION_ID >= 80500) { fwrite(STDERR, "PHP 8.4.27 or newer in the 8.4 branch is required\n"); exit(1); } if (get_cfg_var("session.upload_progress.enabled") !== "0" || (extension_loaded("session") && ini_get("session.upload_progress.enabled") !== "0")) { fwrite(STDERR, "Session upload progress must be disabled\n"); exit(1); } if (ini_get("memory_limit") !== "1024M" || ($ini["max_execution_time"] ?? null) !== "600") { fwrite(STDERR, "PHP runtime limits were not applied\n"); exit(1); }'

# Declarative Apache server and access configuration on unprivileged port 8080.
COPY images/remote/httpd.conf /etc/apache2/httpd.conf
COPY images/remote/apache-access.conf /etc/apache2/conf.d/robrowser-access.conf

# The Apache image has no dependency on roBrowserLegacy frontend sources.
COPY --from=sources /remote /var/www/localhost/htdocs/remote

# Keep the complete pinned source tree for runtime selection.
COPY --from=sources /translation /opt/translation

# Prepare symlinks for optional external mounts (GRFs, BGM, AI)
RUN mkdir -p /opt/client_files/resources /opt/client_files/BGM /opt/client_files/AI /opt/client_files/System && \
    rm -rf /var/www/localhost/htdocs/remote/resources /var/www/localhost/htdocs/remote/BGM /var/www/localhost/htdocs/remote/System /var/www/localhost/htdocs/remote/AI && \
    ln -s /opt/client_files/System /var/www/localhost/htdocs/remote/System && \
    ln -s /opt/client_files/resources /var/www/localhost/htdocs/remote/resources && \
    ln -s /opt/client_files/BGM /var/www/localhost/htdocs/remote/BGM && \
    ln -s /opt/client_files/AI /var/www/localhost/htdocs/AI && \
    ln -s /opt/client_files/AI /var/www/localhost/htdocs/remote/AI

# Static service status, custom overrides, and startup entrypoint
COPY images/remote/index.html /var/www/localhost/htdocs/index.html
COPY images/remote/repository_override/ /var/www/localhost/htdocs/
COPY images/remote/roenglish-generate.php /usr/local/bin/roenglish-generate.php
COPY images/remote/roenglish-startup.php /usr/local/bin/roenglish-startup.php
COPY --chmod=755 images/remote/entrypoint.sh /entrypoint.sh

# Keep the existing image files once, outside the document root. Public paths
# follow the one atomically selected runtime generation.
RUN set -eu; \
    root=/var/www/localhost/htdocs/remote; \
    mkdir -p /opt/remote-base /opt/remote-runtime; \
    for name in data SystemEN; do \
        test ! -L "$root/$name"; \
        mkdir -p "$root/$name"; \
        mv "$root/$name" /opt/remote-base/; \
        ln -s "/opt/remote-runtime/current/$name" "$root/$name"; \
    done && \
    rm -rf /var/www/localhost/htdocs/.git /var/www/localhost/htdocs/remote/.git && \
    addgroup -g 1000 robrowser && \
    adduser -u 1000 -G robrowser -D robrowser && \
    mkdir -p /run/apache2 /var/log/apache2 && \
    chown -R robrowser:robrowser /var/www/localhost/htdocs /opt/client_files /opt/remote-runtime /run/apache2 /var/log/apache2 && \
    httpd -t

USER robrowser
WORKDIR /var/www/localhost/htdocs

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
