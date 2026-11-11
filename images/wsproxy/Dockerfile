# alpine:3.24.2 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a AS build

# zlib is upgraded explicitly to pick up the 1.3.2-r1 fix for CVE-2026-85091;
# drop this once alpine:3.24.2 ships zlib >= 1.3.2-r1 by default.
RUN apk add --no-cache nodejs npm \
    && apk upgrade --no-cache zlib

# Install wsProxy as a project so vulnerable transitive dependencies can be
# controlled with npm overrides instead of being hidden in a global install.
COPY package.json package-lock.json compat.js /opt/wsproxy/
RUN npm ci --prefix /opt/wsproxy --omit=dev --ignore-scripts && \
    node /opt/wsproxy/compat.js && \
    npm cache clean --force

FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

RUN apk add --no-cache nodejs && \
    apk upgrade --no-cache zlib && \
    adduser -D -u 1000 node

COPY --from=build --chown=node:node /opt/wsproxy /opt/wsproxy

USER node

EXPOSE 5999

ENTRYPOINT ["/opt/wsproxy/node_modules/.bin/wsproxy"]
