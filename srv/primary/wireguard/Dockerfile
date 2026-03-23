# syntax=docker/dockerfile:1
FROM alpine:3.23.3
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

RUN apk add --no-cache tini=~0.19.0 wireguard-tools=~1.0.20250521; \
    ln -nsf iptables-nft /sbin/iptables; \
    ln -nsf iptables-nft-save /sbin/iptables-save; \
    ln -nsf iptables-nft-restore /sbin/iptables-restore

COPY entrypoint.sh /

ARG INTERFACE
ENV INTERFACE=$INTERFACE

COPY $INTERFACE /etc/wireguard
RUN --mount=type=secret,id=private_key \
    install -m 0400 /run/secrets/private_key /etc/wireguard/private-key

ENTRYPOINT ["/sbin/tini", "-g", "--", "/entrypoint.sh"]

HEALTHCHECK CMD ip link show dev $INTERFACE
