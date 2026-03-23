#!/bin/bash
uid() { getent passwd "$1" | cut -d: -f3; }
gid() { getent group "$1" | cut -d: -f3; }

set -euo pipefail

# shellcheck disable=SC2034  # Assigned here, exported via eval loop below.
if test -z "${DEVEL:-}"; then
    UID_POSTFIX="$(uid postfix)"
    GID_POSTFIX="$(gid postfix)"
    GID_POSTDROP="$(gid postdrop)"
    GID_DOCKER="$(gid docker)"
    GID_SHOWPID="$(mount | grep ' on /proc .*\bhidepid=' | sed 's/.*\bgid=\([0-9]\+\).*/\1/' || :)"
else
    UID_POSTFIX=1001
    GID_POSTFIX=1001
    GID_POSTDROP=1002
    GID_DOCKER=999
    GID_SHOWPID=
fi
for _var in \
    UID_POSTFIX \
    GID_POSTFIX \
    GID_POSTDROP \
    GID_DOCKER \
    GID_SHOWPID; do eval "export $_var=\"\$$_var\""; done
