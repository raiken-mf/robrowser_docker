# alpine:3.23.5 pinned by immutable multi-architecture manifest digest.
FROM alpine:3.23.5@sha256:fd791d74b68913cbb027c6546007b3f0d3bc45125f797758156952bc2d6daf40

RUN apk add --no-cache nodejs npm && \
    npm install -g wsproxy@1.2.32 && \
    npm cache clean --force

RUN adduser -D -u 1000 node

USER node

EXPOSE 5999

ENTRYPOINT ["wsproxy"]
