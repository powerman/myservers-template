# syntax=docker/dockerfile:1
FROM powerman/dockerize:0.24.2 AS dockerize

FROM alpine:3.23.3 AS postfix
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

COPY --from=dockerize /usr/local/bin/dockerize /usr/local/bin/

VOLUME /var/spool/postfix

ARG UID_POSTFIX
ARG GID_POSTFIX
ARG GID_POSTDROP

RUN apk add --no-cache postfix=~3.10.8 shadow=~4; \
    find / -xdev -not -path '/var/spool/postfix/*' -user postfix -exec chown "$UID_POSTFIX" {} \;; \
    find / -xdev -not -path '/var/spool/postfix/*' -group postfix -exec chgrp "$GID_POSTFIX" {} \;; \
    find / -xdev -not -path '/var/spool/postfix/*' -group postdrop -exec chgrp "$GID_POSTDROP" {} \;; \
    chmod g+s /usr/sbin/postdrop /usr/sbin/postqueue; \
    usermod -u 60000 "$(getent passwd "$UID_POSTFIX" | cut -d: -f1)" 2>/dev/null || :; \
    groupmod -g 60000 "$(getent group "$GID_POSTFIX" | cut -d: -f1)" 2>/dev/null || :; \
    groupmod -g 60001 "$(getent group "$GID_POSTDROP" | cut -d: -f1)" 2>/dev/null || :; \
    usermod -u "$UID_POSTFIX" postfix; \
    groupmod -g "$GID_POSTFIX" postfix; \
    groupmod -g "$GID_POSTDROP" postdrop

COPY entrypoint-postfix.sh /entrypoint.sh
COPY sasl2/* /etc/sasl2/
COPY postfix/* /etc/postfix/
RUN postmap lmdb:/etc/postfix/virtual_mailbox; \
    postmap lmdb:/etc/postfix/virtual_alias; \
    postmap lmdb:/etc/postfix/controlled_envelope_senders; \
    install -d -o 5000 -g 5000 /var/mail/vhosts

ENTRYPOINT ["/entrypoint.sh"]
CMD ["postfix", "start-fg"]

HEALTHCHECK CMD netstat -ltn | grep -q ':25 ' && netstat -ltn | grep -q ':587 ' && netstat -ltn | grep -q ':465 '


FROM powerman/dockerize:0.24.2 AS opendkim
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

RUN apk add --no-cache opendkim=~2.11.0; \
    install -d -o opendkim -g opendkim /run/opendkim

COPY entrypoint-opendkim.sh /entrypoint.sh
RUN --mount=type=secret,id=postfix_dkim_key \
    install -m 0400 /run/secrets/postfix_dkim_key /var/db/dkim/example.com.private
COPY opendkim/opendkim.conf.tmpl /etc/opendkim/

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/opendkim", "-f"]

HEALTHCHECK CMD netstat -ltn | grep -q ':8891 '


FROM powerman/dockerize:0.24.2 AS opendmarc
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

RUN apk add --no-cache opendmarc=~1.4.2

COPY entrypoint-opendmarc.sh /entrypoint.sh
COPY opendmarc/* /etc/opendmarc/

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/opendmarc", "-f", "-c", "/etc/opendmarc/opendmarc.conf"]

HEALTHCHECK CMD netstat -ltn | grep -q ':8893 '


FROM alpine:3.23.3 AS postsrsd
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

VOLUME /data

RUN apk add --no-cache postsrsd=~2.0.11; \
    mkdir -p /data; \
    dd if=/dev/urandom bs=18 count=1 status=none | base64 > /data/secret; \
    sed -i \
        -e 's,^secrets-file = .*,secrets-file = "/data/secret",' \
        -e 's,^socketmap = .*,socketmap = inet:0.0.0.0:10003,' \
        -e 's,^domains =,#domains =,' \
        -e 's,^#domains-file =.*,domains-file = "/etc/postsrsd/domains",' \
        /etc/postsrsd/postsrsd.conf;

COPY postsrsd/* /etc/postsrsd/

CMD ["/usr/sbin/postsrsd"]

HEALTHCHECK CMD netstat -ltn | grep -q ':10003 '


FROM alpine:3.23.3 AS postgrey
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

RUN apk add --no-cache \
        perl-net-server=~2 perl-io-multiplex=~1 perl-digest-sha1=~2 perl-netaddr-ip=~4 \
        perl-app-cpanminus=~1 make=~4 gcc=~15 musl-dev=~1 db-dev=~5 perl-dev=~5; \
    cpanm --quiet --notest BerkeleyDB; \
    mkdir -p /etc/postfix; \
    mkdir -p /var/spool/postfix; \
    adduser -S -h /var/spool/postfix/postgrey postgrey; \
    v_postgrey="version-1.37"; \
    wget -q -O - https://github.com/schweikert/postgrey/archive/refs/tags/$v_postgrey.tar.gz | \
        tar xzf - -C /tmp/; \
    cp -a /tmp/postgrey-$v_postgrey/policy-test            /usr/local/bin/; \
    cp -a /tmp/postgrey-$v_postgrey/postgrey               /usr/local/bin/; \
    cp -a /tmp/postgrey-$v_postgrey/postgrey-search        /usr/local/bin/; \
    cp -a /tmp/postgrey-$v_postgrey/postgrey_clients_dump  /usr/local/bin/; \
    cp -a /tmp/postgrey-$v_postgrey/postgrey_whitelist_*   /etc/postfix/; \
    rm -rf /tmp/postgrey-$v_postgrey; \
    wget -q -O /etc/postfix/postgrey_whitelist_clients \
        https://postgrey.schweikert.ch/pub/postgrey_whitelist_clients

CMD ["postgrey", "--inet=0.0.0.0:10023", "--delay=150", "--greylist-text=Greylisted for %s seconds"]

HEALTHCHECK CMD netstat -ltn | grep -q ':10023 '
