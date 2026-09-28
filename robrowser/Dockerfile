# alpine:3.23.6 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.23.6@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0

ARG ROBROWSER_REPOSITORY=https://github.com/raiken-mf/roBrowserLegacy.git
ARG ROBROWSER_REF
ARG ROENGLISH_REPOSITORY=https://github.com/raiken-mf/ROenglishRE.git
ARG ROENGLISH_REF

# Install runtime/build packages from the pinned Alpine release.
RUN apk add --no-cache \
    apache2 \
    php \
    php-apache2 \
    php-mbstring \
    php-iconv \
    php-gd \
    php-zlib \
    nodejs \
    npm \
    git \
    gettext \
    && rm -rf /var/www/localhost/htdocs/*

# Configure Apache to unprivileged port 8080 & PHP runtime settings
RUN sed -i 's/Listen 80/Listen 8080/g' /etc/apache2/httpd.conf && \
    sed -i 's/:80/:8080/g' /etc/apache2/httpd.conf && \
    echo "LoadModule rewrite_module modules/mod_rewrite.so" >> /etc/apache2/httpd.conf && \
    echo "LoadModule headers_module modules/mod_headers.so" >> /etc/apache2/httpd.conf && \
    sed -i "s|AllowOverride None|AllowOverride All|g" /etc/apache2/httpd.conf && \
    echo "TraceEnable Off" >> /etc/apache2/httpd.conf && \
    echo "ServerName localhost" >> /etc/apache2/httpd.conf && \
    echo 'Header unset Access-Control-Allow-Origin' >> /etc/apache2/httpd.conf && \
    echo 'Header always set Access-Control-Allow-Origin "*"' >> /etc/apache2/httpd.conf && \
    echo 'Header always set Access-Control-Allow-Methods "GET, POST, OPTIONS"' >> /etc/apache2/httpd.conf && \
    echo 'Header always set Access-Control-Allow-Headers "*"' >> /etc/apache2/httpd.conf && \
    PHP_INI="$(php --ini | sed -n 's/^Loaded Configuration File: *//p')" && \
    test -f "$PHP_INI" && \
    sed -i "s/memory_limit = .*/memory_limit = 1024M/g" "$PHP_INI" && \
    sed -i "s/max_execution_time = .*/max_execution_time = 600/g" "$PHP_INI" && \
    sed -i 's/^User .*/User robrowser/' /etc/apache2/httpd.conf && \
    sed -i 's/^Group .*/Group robrowser/' /etc/apache2/httpd.conf

# The package manifest and lockfile were generated for the pinned roBrowser
# source revision. Keep them here because the upstream commit has no lockfile.
COPY robrowser/package.json /tmp/robrowser-package.json
COPY robrowser/package-lock.json /tmp/robrowser-package-lock.json

# Clone pinned client sources and install reproducible frontend dependencies.
# Revisions are supplied by CI or docker compose; never build implicitly from a moving branch.
RUN test -n "${ROBROWSER_REF}" && test -n "${ROENGLISH_REF}" && \
    git clone "${ROBROWSER_REPOSITORY}" /var/www/localhost/htdocs && \
    git -C /var/www/localhost/htdocs checkout --detach "${ROBROWSER_REF}" && \
    cp /tmp/robrowser-package.json /var/www/localhost/htdocs/package.json && \
    cp /tmp/robrowser-package-lock.json /var/www/localhost/htdocs/package-lock.json && \
    git clone --depth=1 https://github.com/raiken-mf/roBrowserLegacy-RemoteClient-PHP.git /var/www/localhost/htdocs/client && \
    npm ci --prefix /var/www/localhost/htdocs && \
    npm cache clean --force

# Adjust Vite dev server configuration for container environments
RUN sed -i '/server: {/a \ \ \ \ host: "0.0.0.0",\n    allowedHosts: true,' /var/www/localhost/htdocs/vite.config.js

# Fetch translation files and extract client data/System folders
ARG SET_PRERENEWAL
RUN git clone "${ROENGLISH_REPOSITORY}" /opt/translation && \
    git -C /opt/translation checkout --detach "${ROENGLISH_REF}" && \
    test -d /opt/translation/Translation && \
    mkdir -p /var/www/localhost/htdocs/client/data /var/www/localhost/htdocs/client/System && \
    if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then \
        if [ -d "/opt/translation/Translation/Pre-Renewal/data" ]; then \
            cp -rf /opt/translation/Translation/Pre-Renewal/data/* /var/www/localhost/htdocs/client/data/; \
        fi; \
        if [ -d "/opt/translation/Translation/Pre-Renewal/SystemEN" ]; then \
            cp -rf /opt/translation/Translation/Pre-Renewal/SystemEN/* /var/www/localhost/htdocs/client/System/; \
        fi; \
    else \
        if [ -d "/opt/translation/Translation/Renewal/data" ]; then \
            cp -rf /opt/translation/Translation/Renewal/data/* /var/www/localhost/htdocs/client/data/; \
        fi; \
        if [ -d "/opt/translation/Translation/Renewal/SystemEN" ]; then \
            cp -rf /opt/translation/Translation/Renewal/SystemEN/* /var/www/localhost/htdocs/client/System/; \
        fi; \
        sed -i 's/itemInfo.lub/itemInfo_EN.lua/g' /var/www/localhost/htdocs/src/DB/DBManager.js; \
    fi && \
    rm -rf /opt/translation

# Prepare symlinks for optional external mounts (GRFs, BGM, AI)
RUN mkdir -p /opt/client_files/resources /opt/client_files/BGM /opt/client_files/AI && \
    rm -rf /var/www/localhost/htdocs/client/resources /var/www/localhost/htdocs/client/BGM && \
    ln -s /opt/client_files/resources /var/www/localhost/htdocs/client/resources && \
    ln -s /opt/client_files/BGM /var/www/localhost/htdocs/client/BGM && \
    ln -s /opt/client_files/AI /var/www/localhost/htdocs/AI

# Create Apache routing configuration
RUN cat <<EOT > /var/www/localhost/htdocs/.htaccess
ErrorDocument 404 /client/index.php
RedirectMatch 404 /\.git
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{REQUEST_METHOD} ^TRACE
    RewriteRule .* - [F]
</IfModule>
EOT

# Copy templates, custom overrides, and startup entrypoint
COPY robrowser/index.html.template /var/www/localhost/htdocs/index.html.template
COPY robrowser/repository_override/ /var/www/localhost/htdocs/
COPY robrowser/entrypoint.sh /entrypoint.sh

# Create non-root user and set permissions for runtime directories
RUN addgroup -g 1000 robrowser && \
    adduser -u 1000 -G robrowser -D robrowser && \
    mkdir -p /run/apache2 /var/log/apache2 && \
    chown -R robrowser:robrowser /var/www/localhost/htdocs /opt/client_files /run/apache2 /var/log/apache2 && \
    chmod 755 /entrypoint.sh

# Add security hardening
RUN chmod 755 /var/www/localhost/htdocs/index.html.template

USER robrowser
WORKDIR /var/www/localhost/htdocs

EXPOSE 8080 3000

ENTRYPOINT ["/entrypoint.sh"]
