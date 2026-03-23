#!/bin/bash
uid() { getent passwd "$1" | cut -d: -f3; }
gid() { getent group "$1" | cut -d: -f3; }
metadata() { curl -s "http://169.254.169.254/metadata/v1$1"; }
ifip() { ip -j -4 addr show dev "$1" | jq -r '.[0].addr_info[0].local'; }
ifnet() { ip -j -4 route show dev "$1" proto kernel | jq -r '.[0].dst'; }
ifnet_by_ip() {
    ip -j -4 route show dev "$1" proto kernel |
        jq -r --arg ip "$2" '.[] | select(.prefsrc == $ip) | .dst'
}

set -euo pipefail

# shellcheck disable=SC2034  # Assigned here, exported via eval loop below.
if test -z "${DEVEL:-}"; then
    # Use HOST_GATEWAY_IP instead of localhost to bind local docker "network-mode:host" services.
    # Then they can be connected by docker containers in other networks as host.docker.internal.
    HOST_GATEWAY_IP="$(ifip docker0)"
    WAN_IFNAME="eth0"
    WAN_IP="$(metadata /interfaces/public/0/ipv4/address)"
    WAN_RESERVED_IP="$(metadata /reserved_ip/ipv4/ip_address)"
    WAN_ANCHOR_IP="$(metadata /interfaces/public/0/anchor_ipv4/address)"
    WAN_ANCHOR_NET="$(ifnet_by_ip "$WAN_IFNAME" "$WAN_ANCHOR_IP")"
    PRIVATE_IFNAME="eth1"
    PRIVATE_IP="$(ifip "$PRIVATE_IFNAME")"
    PRIVATE_NET="$(ifnet "$PRIVATE_IFNAME")"
    UID_POSTFIX="$(uid postfix)"
    GID_POSTFIX="$(gid postfix)"
    GID_POSTDROP="$(gid postdrop)"
    GID_DOCKER="$(gid docker)"
    POSTFIX_MY_ORIGIN="$(hostname -f)"
else
    HOST_GATEWAY_IP=127.0.0.1
    WAN_IFNAME="eth.nosuch"
    WAN_IP=0.0.0.0
    WAN_RESERVED_IP=0.0.0.0
    WAN_ANCHOR_IP=0.0.0.0
    WAN_ANCHOR_NET=0.0.0.0/32
    PRIVATE_IFNAME="eth.nosuch"
    PRIVATE_IP=0.0.0.0
    PRIVATE_NET=0.0.0.0/32
    UID_POSTFIX=1001
    GID_POSTFIX=1001
    GID_POSTDROP=1002
    GID_DOCKER=999
    POSTFIX_MY_ORIGIN=test.localhost
fi
for _var in \
    HOST_GATEWAY_IP \
    WAN_IFNAME \
    WAN_IP \
    WAN_RESERVED_IP \
    WAN_ANCHOR_IP \
    WAN_ANCHOR_NET \
    PRIVATE_IFNAME \
    PRIVATE_IP \
    PRIVATE_NET \
    UID_POSTFIX \
    GID_POSTFIX \
    GID_POSTDROP \
    GID_DOCKER \
    POSTFIX_MY_ORIGIN; do eval "export $_var=\"\$$_var\""; done
