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
COPY postfix/* /etc/postfix/

ENTRYPOINT ["/entrypoint.sh"]
CMD ["postfix", "start-fg"]

HEALTHCHECK CMD netstat -ltn | grep -q ':25 '


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
