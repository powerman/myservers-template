#!/bin/sh
#shellcheck shell=ash
set -x -e -o pipefail

finish() {
    local code=$(($? == 143 ? 0 : $?)) # 143 == 128 (signal) + 15 (SIGTERM)
    wg-quick down "$INTERFACE"
    exit $code
}
trap finish EXIT
trap 'exit 0' TERM INT QUIT

wg-quick up "$INTERFACE"

sleep inf
