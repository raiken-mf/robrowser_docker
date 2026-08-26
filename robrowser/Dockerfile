FROM alpine:3.23.5

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

# Apache & PHP Setup
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

# Repositories klonen & Dependencies bauen
RUN git clone --depth=1 https://github.com/raiken-mf/roBrowserLegacy.git /var/www/localhost/htdocs && \
    git clone --depth=1 https://github.com/raiken-mf/roBrowserLegacy-RemoteClient-PHP.git /var/www/localhost/htdocs/client && \
    npm install --prefix /var/www/localhost/htdocs && \
    npm cache clean --force

RUN sed -i '/server: {/a \ \ \ \ host: "0.0.0.0",\n    allowedHosts: true,' /var/www/localhost/htdocs/vite.config.js

# Translations laden
RUN git clone -n --depth=1 --filter=tree:0 https://github.com/raiken-mf/ROenglishRE.git /opt/translation && \
    cd /opt/translation && \
    git sparse-checkout set --no-cone Translation/Renewal && \
    git checkout && \
    cp -rs /opt/translation/Translation/Renewal/data/* /var/www/localhost/htdocs/client/data/ 2>/dev/null || true && \
    cp -rs /opt/translation/Translation/Renewal/System/* /var/www/localhost/htdocs/client/System/ 2>/dev/null || true && \
    sed -i 's/itemInfo.lub/itemInfo_EN.lua/g' /var/www/localhost/htdocs/src/DB/DBManager.js && \
    rm -rf /opt/translation && \
    apk del git

# Bereite Verzeichnisse für optionale Mounts vor (GRFs, BGM)
RUN mkdir -p /opt/client_files/resources /opt/client_files/BGM /opt/client_files/AI && \
    rm -rf /var/www/localhost/htdocs/client/resources /var/www/localhost/htdocs/client/BGM && \
    ln -s /opt/client_files/resources /var/www/localhost/htdocs/client/resources && \
    ln -s /opt/client_files/BGM /var/www/localhost/htdocs/client/BGM && \
    ln -s /opt/client_files/AI /var/www/localhost/htdocs/AI

# .htaccess erstellen
RUN cat <<EOF > /var/www/localhost/htdocs/.htaccess
ErrorDocument 404 /client/index.php
RedirectMatch 404 /\.git
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{REQUEST_METHOD} ^TRACE
    RewriteRule .* - [F]
</IfModule>
EOF

COPY robrowser/index.html.template /var/www/localhost/htdocs/index.html.template
COPY robrowser/repository_override/ /var/www/localhost/htdocs/
COPY robrowser/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

WORKDIR /var/www/localhost/htdocs

EXPOSE 80 3000

ENTRYPOINT ["/entrypoint.sh"]
