FROM alpine:3.23.5

# Install system dependencies and web server packages
RUN apk add --no-cache \
    apache2 \
    php84 \
    php84-apache2 \
    php84-mbstring \
    php84-iconv \
    nodejs \
    npm \
    git \
    gettext \
    && rm -rf /var/www/localhost/htdocs/*

# Configure Apache & PHP runtime settings
RUN echo "LoadModule rewrite_module modules/mod_rewrite.so" >> /etc/apache2/httpd.conf && \
    echo "LoadModule headers_module modules/mod_headers.so" >> /etc/apache2/httpd.conf && \
    sed -i "s|AllowOverride None|AllowOverride All|g" /etc/apache2/httpd.conf && \
    echo "TraceEnable Off" >> /etc/apache2/httpd.conf && \
    echo "ServerName localhost" >> /etc/apache2/httpd.conf && \
    echo 'Header unset Access-Control-Allow-Origin' >> /etc/apache2/httpd.conf && \
    echo 'Header always set Access-Control-Allow-Origin "*"' >> /etc/apache2/httpd.conf && \
    echo 'Header always set Access-Control-Allow-Methods "GET, POST, OPTIONS"' >> /etc/apache2/httpd.conf && \
    echo 'Header always set Access-Control-Allow-Headers "*"' >> /etc/apache2/httpd.conf && \
    sed -i "s/memory_limit = .*/memory_limit = 1024M/g" /etc/php84/php.ini && \
    sed -i "s/max_execution_time = .*/max_execution_time = 600/g" /etc/php84/php.ini

# Clone client repositories and install frontend dependencies
RUN git clone --depth=1 https://github.com/raiken-mf/roBrowserLegacy.git /var/www/localhost/htdocs && \
    git clone --depth=1 https://github.com/raiken-mf/roBrowserLegacy-RemoteClient-PHP.git /var/www/localhost/htdocs/client && \
    npm install --prefix /var/www/localhost/htdocs && \
    npm cache clean --force

# Adjust Vite dev server configuration for container environments
RUN sed -i '/server: {/a \ \ \ \ host: "0.0.0.0",\n    allowedHosts: true,' /var/www/localhost/htdocs/vite.config.js

# Fetch translation files and extract client data/System folders
ARG SET_PRERENEWAL
RUN git clone --depth=1 https://github.com/raiken-mf/ROenglishRE.git /opt/translation && \
    mkdir -p /var/www/localhost/htdocs/client/data /var/www/localhost/htdocs/client/System && \
    if [ -n "${SET_PRERENEWAL}" ] && [ "${SET_PRERENEWAL}" -ne 0 ]; then \
        if [ -d "/opt/translation/Translation/Pre-Renewal/data" ]; then \
            cp -rf /opt/translation/Translation/Pre-Renewal/data/* /var/www/localhost/htdocs/client/data/; \
        fi; \
        if [ -d "/opt/translation/Translation/Pre-Renewal/System" ]; then \
            cp -rf /opt/translation/Translation/Pre-Renewal/System/* /var/www/localhost/htdocs/client/System/; \
        fi; \
    else \
        if [ -d "/opt/translation/Translation/Renewal/data" ]; then \
            cp -rf /opt/translation/Translation/Renewal/data/* /var/www/localhost/htdocs/client/data/; \
        fi; \
        if [ -d "/opt/translation/Translation/Renewal/System" ]; then \
            cp -rf /opt/translation/Translation/Renewal/System/* /var/www/localhost/htdocs/client/System/; \
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

RUN chmod +x /entrypoint.sh

WORKDIR /var/www/localhost/htdocs

EXPOSE 80 3000

ENTRYPOINT ["/entrypoint.sh"]
