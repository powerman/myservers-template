#!/bin/bash
set -eo pipefail
cd /etc/duplicity || exit 1

profile="$1"
shift
target="$(<target)$profile"
test -x "$profile.pre.sh" && pre="./$profile.pre.sh"

PASSPHRASE="$(<gpg.pass)" duplicity cleanup --force "$target"
PASSPHRASE="$(<gpg.pass)" \
    exec $pre duplicity "$@" \
    --name "$profile" \
    --full-if-older-than 1M \
    --include-filelist "$profile.filelist" \
    --exclude / \
    / "$target"
