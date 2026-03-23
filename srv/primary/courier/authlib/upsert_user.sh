#!/bin/bash
die() {
    echo "$@"
    exit 1
}

login="$1"
user="${login%@*}"
host="${login#*@}"
test $# -eq 1 -a "$1" != "-h" -a "$1" != "--help" \
    -a -n "$user" -a -n "$host" || die "Usage: $0 USER@DOMAIN.TLD"

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

# Load current userdb from fnox, modify, and save back
fnox get COURIER_USERDB >"$tmpfile"
userdbpw | userdb -f "$tmpfile" "$login" set systempw \
    uid=5000 gid=5000 \
    home="/var/mail/vhosts/$host/$user" \
    mail="/var/mail/vhosts/$host/$user"
fnox set COURIER_USERDB -- "$(cat "$tmpfile")"
