# Pinned Alpine base, matching the roBrowser image.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

ARG ROBROWSER_REPOSITORY=https://github.com/raiken-mf/roBrowserLegacy.git
ARG ROBROWSER_REF

# Vite requires Node.js, not Apache or PHP.
RUN apk add --no-cache \
      nodejs \
      npm \
      git \
      gettext \
    && addgroup -g 1000 vite \
    && adduser -u 1000 -G vite -D vite \
    && mkdir -p /app \
    && chown vite:vite /app

USER vite
WORKDIR /app

# Fetch the exact pinned upstream revision.
RUN test -n "${ROBROWSER_REF}" \
    && git clone "${ROBROWSER_REPOSITORY}" /app \
    && git checkout --detach "${ROBROWSER_REF}" \
    && rm -rf .git

# Reproducible npm dependencies.
COPY --chown=vite:vite images/vite/package.json /app/package.json
COPY --chown=vite:vite images/vite/package-lock.json /app/package-lock.json

RUN npm ci && npm cache clean --force

# Preserve current development-server behaviour.
RUN grep -q 'server: {' vite.config.js \
    && sed -i '/server: {/a\    allowedHosts: true,' vite.config.js

# The frontend configuration template belongs only to Vite.
COPY --chown=vite:vite images/vite/index.html.template /app/index.html.template

# Optional Vite-specific file overrides.
COPY --chown=vite:vite images/vite/repository_override/ /app/

COPY --chown=vite:vite --chmod=755 images/vite/entrypoint.sh /entrypoint.sh

# Match the Apache image's explicit zlib security update. Keep runtime non-root.
USER root
RUN apk upgrade --no-cache zlib
USER vite

EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
