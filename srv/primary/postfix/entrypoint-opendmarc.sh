#!/bin/sh
#shellcheck shell=ash
set -x -e -o pipefail

eval "$(ipcalc -n -p "$(ip addr show dev eth1 | awk '/inet/{print $2}' | head -n 1)")"
export MAIL_NETWORK="$NETWORK/$PREFIX"

exec dockerize -exec -template-strict \
    -template /etc/opendmarc/ignore.hosts.tmpl:/etc/opendmarc/ignore.hosts \
    "$@"
