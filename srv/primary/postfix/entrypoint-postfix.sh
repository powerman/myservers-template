#!/bin/sh
#shellcheck shell=ash
set -x -e -o pipefail

eval "$(ipcalc -n -p "$(ip addr show dev eth0 | awk '/inet/{print $2}' | head -n 1)")"
export MAIL_NETWORK="$NETWORK/$PREFIX"

dockerize -template-strict \
    -template /etc/postfix/main.cf.tmpl:/etc/postfix/main.cf

newaliases

exec "$@"
