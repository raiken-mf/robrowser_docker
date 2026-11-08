# Pinned Alpine base, matching the roBrowser image.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

ARG ROBROWSER_REPOSITORY=https://github.com/raiken-mf/roBrowserLegacy.git
ARG ROBROWSER_REF

# Vite requires Node.js, not Apache or PHP.
# Upgrade zlib and libexpat in the base package layer while keeping runtime non-root.
RUN apk add --no-cache \
      nodejs \
      npm \
      git \
      gettext \
    && apk upgrade --no-cache zlib libexpat \
    && addgroup -g 1000 vite \
    && adduser -u 1000 -G vite -D vite \
    && mkdir -p /app \
    && chown vite:vite /app

USER vite
WORKDIR /app

# Fetch the exact pinned upstream revision and preserve its Vite configuration.
RUN test -n "${ROBROWSER_REF}" \
    && git clone "${ROBROWSER_REPOSITORY}" /app \
    && git checkout --detach "${ROBROWSER_REF}" \
    && mv /app/vite.config.js /app/vite.upstream.config.js \
    && rm -rf .git

# Reproducible npm dependencies.
COPY --chown=vite:vite images/robrowser/package.json /app/package.json
COPY --chown=vite:vite images/robrowser/package-lock.json /app/package-lock.json

RUN npm ci && npm cache clean --force

# Extend the pinned upstream Vite configuration declaratively.
COPY --chown=vite:vite images/robrowser/vite.config.js /app/vite.config.js
RUN node --input-type=module -e 'import c from "./vite.config.js"; const cfg = typeof c === "function" ? c({ command: "serve", mode: "development" }) : c; if (cfg.server?.allowedHosts !== true || cfg.server?.proxy?.["/remote/"]?.target !== "http://remote:8080" || !cfg.server?.proxy?.["/get"] || !cfg.resolve?.alias?.Core || !cfg.plugins?.length) process.exit(1);'

# The frontend configuration template belongs only to Vite.
COPY --chown=vite:vite images/robrowser/index.html.template /app/index.html.template

# Optional Vite-specific file overrides.
COPY --chown=vite:vite images/robrowser/repository_override/ /app/

COPY --chown=vite:vite --chmod=755 images/robrowser/entrypoint.sh /entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
