#!/bin/bash
uid() { getent passwd "$1" | cut -d: -f3; }
gid() { getent group "$1" | cut -d: -f3; }
ifip() { ip -j -4 addr show dev "$1" | jq -r '.[0].addr_info[0].local'; }

set -euo pipefail

# shellcheck disable=SC2034  # Assigned here, exported via eval loop below.
if test -z "${DEVEL:-}"; then
    # Use HOST_GATEWAY_IP instead of localhost to bind local docker "network-mode:host" services.
    # Then they can be connected by docker containers in other networks as host.docker.internal.
    HOST_GATEWAY_IP="$(ifip docker0)"
    WAN_IFNAME="ens3"
    WAN_IP="$(ifip "$WAN_IFNAME")"
    UID_POSTFIX="$(uid postfix)"
    GID_POSTFIX="$(gid postfix)"
    GID_POSTDROP="$(gid postdrop)"
    GID_DOCKER="$(gid docker)"
    POSTFIX_MY_ORIGIN="$(hostname -f)"
else
    HOST_GATEWAY_IP=127.0.0.1
    WAN_IFNAME="eth.nosuch"
    WAN_IP=0.0.0.0
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
    UID_POSTFIX \
    GID_POSTFIX \
    GID_POSTDROP \
    GID_DOCKER \
    POSTFIX_MY_ORIGIN; do eval "export $_var=\"\$$_var\""; done
