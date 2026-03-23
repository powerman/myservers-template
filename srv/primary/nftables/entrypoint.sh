#!/bin/sh
#shellcheck shell=ash
set -x -e -o pipefail

dockerize -template-strict -template /migrate.nft.tmpl:/migrate.nft

nft -f /migrate.nft

exec sleep inf
