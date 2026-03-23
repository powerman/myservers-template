# syntax=docker/dockerfile:1
FROM ubuntu:24.04 AS courier
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update; \
    apt-get install --no-install-recommends -y \
        apt-utils=* ca-certificates=* wget=* lsb-release=* gnupg=* net-tools=*; \
    wget -q -O - http://powerman.github.io/courier-imap/public.key | \
        gpg --dearmor >/etc/apt/keyrings/courier-imap.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/courier-imap.gpg]" \
        "https://powerman.github.io/courier-imap/apt/$(lsb_release -cs)" \
        "$(lsb_release -cs) main" >/etc/apt/sources.list.d/courier-imap.list; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
        courier-imap=5.2.10-* libcourier-auth=0.72.3-* \
        gnutls-bin=* libcourier-auth-userdb=*; \
    /usr/lib/courier-imap/share/mkdhparams; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*


FROM courier AS courier-auth

COPY cmd-auth.sh /cmd.sh
CMD ["/cmd.sh"]

COPY authlib/* /etc/authlib/
RUN --mount=type=secret,id=courier_userdb \
    install -m 0700 /run/secrets/courier_userdb /etc/authlib/userdb && \
    makeuserdb

HEALTHCHECK CMD authtest -s imap root bad 2>&1 | grep -q not.permitted


FROM courier AS courier-imap-ssl

COPY cmd-imap-ssl.sh /cmd.sh
CMD ["/cmd.sh"]

COPY courier-imap/imapd* /usr/lib/courier-imap/etc/
# hadolint ignore=SC3046 # False positive https://github.com/hadolint/hadolint/issues/1174.
RUN set -a; \
    source /usr/lib/courier-imap/etc/imapd; \
    source /usr/lib/courier-imap/etc/imapd-ssl; \
    test -z "$TLS_CACHEFILE" || install -m 0600 -o daemon -g daemon /dev/null "$TLS_CACHEFILE"; \
    umask "$IMAP_UMASK"; \
    test -f "${IMAPACCESSFILE}.dat" || /usr/lib/courier-imap/bin/makeimapaccess

HEALTHCHECK CMD netstat -ltn | grep -q ':993 '


FROM courier AS courier-pop3-ssl

COPY cmd-pop3-ssl.sh /cmd.sh
CMD ["/cmd.sh"]

COPY courier-imap/pop3d* /usr/lib/courier-imap/etc/
# hadolint ignore=SC3046 # False positive https://github.com/hadolint/hadolint/issues/1174.
RUN set -a; \
    source /usr/lib/courier-imap/etc/pop3d; \
    source /usr/lib/courier-imap/etc/pop3d-ssl; \
    test -z "$TLS_CACHEFILE" || install -m 0600 -o daemon -g daemon /dev/null "$TLS_CACHEFILE"

HEALTHCHECK CMD netstat -ltn | grep -q ':995 '
