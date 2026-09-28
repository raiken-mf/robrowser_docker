# alpine:3.23.6 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.23.6@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0

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
