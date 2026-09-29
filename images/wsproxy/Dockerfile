# alpine:3.24.2 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN apk add --no-cache nodejs npm

# Install wsProxy as a project so vulnerable transitive dependencies can be
# controlled with npm overrides instead of being hidden in a global install.
COPY package.json package-lock.json /opt/wsproxy/
RUN npm ci --prefix /opt/wsproxy --omit=dev --ignore-scripts && \
    npm cache clean --force

RUN adduser -D -u 1000 node && \
    chown -R node:node /opt/wsproxy

USER node

EXPOSE 5999

ENTRYPOINT ["/opt/wsproxy/node_modules/.bin/wsproxy"]
