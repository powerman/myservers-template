#!/bin/bash
set -e -o pipefail

set -a
# shellcheck source=srv/primary/courier/courier-imap/imapd
. /usr/lib/courier-imap/etc/imapd
# shellcheck source=srv/primary/courier/courier-imap/imapd-ssl
. /usr/lib/courier-imap/etc/imapd-ssl

le_dir=/tls/caddy/certificates/acme-v02.api.letsencrypt.org-directory
cp "$le_dir/imap.example.com/imap.example.com.crt" "$TLS_CERTFILE"
cp "$le_dir/imap.example.com/imap.example.com.key" "$TLS_PRIVATE_KEYFILE"
chown daemon "$TLS_CERTFILE" "$TLS_PRIVATE_KEYFILE"

umask "${IMAP_UMASK:=022}"
if test ! -z "$IMAP_ULIMITD"; then
    ulimit -v $IMAP_ULIMITD
fi

IMAP_TLS=1 \
    exec /usr/lib/courier-imap/libexec/couriertcpd -address=$SSLADDRESS \
    -maxprocs=$MAXDAEMONS -maxperip=$MAXPERIP \
    -access=${IMAPACCESSFILE}.dat \
    "${TCPDOPTS[@]}" \
    $SSLPORT $COURIERTLS -server -tcpd \
    -user=daemon \
    /usr/lib/courier-imap/sbin/imaplogin \
    /usr/lib/courier-imap/bin/imapd ${MAILDIRPATH}
