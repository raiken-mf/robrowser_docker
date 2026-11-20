# alpine:3.24.2 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS build

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

FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

RUN apk add --no-cache nodejs && \
    apk upgrade --no-cache zlib && \
    adduser -D -u 1000 node

COPY --from=build --chown=node:node /opt/wsproxy /opt/wsproxy

USER node

EXPOSE 5999

ENTRYPOINT ["/opt/wsproxy/node_modules/.bin/wsproxy"]
