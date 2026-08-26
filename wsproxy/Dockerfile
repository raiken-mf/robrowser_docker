FROM alpine:3.23.5

RUN apk add --no-cache nodejs=~24.18 npm=~11.11 && \
    npm install -g wsproxy@1.2.32 && \
    npm cache clean --force

RUN adduser -D -u 1000 node

USER node

EXPOSE 5999

ENTRYPOINT ["wsproxy"]
