#!/bin/bash
profile="$1"
target="$(</etc/duplicity/target)$1"
PASSPHRASE="$(</etc/duplicity/gpg.pass)" \
    exec duplicity restore \
    --name "$profile" \
    "$target" "./$1"
