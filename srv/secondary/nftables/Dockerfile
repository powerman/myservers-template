# syntax=docker/dockerfile:1
FROM powerman/dockerize:0.24.2 AS dockerize

FROM alpine:3.23.3
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

COPY --from=dockerize /usr/local/bin/dockerize /usr/local/bin/

RUN apk add --no-cache nftables=~1.1.5

COPY entrypoint.sh /
COPY migrate.nft.tmpl /

ENTRYPOINT ["/entrypoint.sh"]

HEALTHCHECK CMD nft -c -f /migrate.nft
