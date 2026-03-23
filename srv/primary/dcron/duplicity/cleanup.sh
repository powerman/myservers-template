#!/bin/bash
set -eo pipefail
cd /etc/duplicity || exit 1
target="$(<target)"

for backup in $(rclone lsf "${target#rclone://}" --max-depth 1); do
    PASSPHRASE="$(<gpg.pass)" duplicity remove-all-but-n-full 5 --force "$target$backup"
    PASSPHRASE="$(<gpg.pass)" duplicity remove-all-inc-of-but-n-full 3 --force "$target$backup"
done
rclone size "${target#rclone://}"
