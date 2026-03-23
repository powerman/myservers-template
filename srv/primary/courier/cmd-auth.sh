#!/bin/bash
set -e -o pipefail

set -a
# shellcheck source=srv/primary/courier/authlib/authdaemonrc
source /etc/authlib/authdaemonrc

exec /usr/libexec/courier-authlib/authdaemond
