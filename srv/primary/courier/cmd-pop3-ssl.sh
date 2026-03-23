#!/bin/bash
set -e -o pipefail

set -a
# shellcheck source=srv/primary/courier/courier-imap/pop3d
. /usr/lib/courier-imap/etc/pop3d
# shellcheck source=srv/primary/courier/courier-imap/pop3d-ssl
. /usr/lib/courier-imap/etc/pop3d-ssl

le_dir=/tls/caddy/certificates/acme-v02.api.letsencrypt.org-directory
cp "$le_dir/pop3.example.com/pop3.example.com.crt" "$TLS_CERTFILE"
cp "$le_dir/pop3.example.com/pop3.example.com.key" "$TLS_PRIVATE_KEYFILE"
chown daemon "$TLS_CERTFILE" "$TLS_PRIVATE_KEYFILE"

POP3_TLS=1 POP3_STARTTLS=NO POP3_TLS_REQUIRED=0 \
    exec /usr/lib/courier-imap/libexec/couriertcpd -address=$SSLADDRESS \
    -maxprocs=$MAXDAEMONS -maxperip=$MAXPERIP \
    "${TCPDOPTS[@]}" \
    $SSLPORT $COURIERTLS -server -tcpd \
    -user=daemon \
    /usr/lib/courier-imap/sbin/pop3login \
    /usr/lib/courier-imap/bin/pop3d ${MAILDIRPATH}
