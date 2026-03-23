# syntax=docker/dockerfile:1
FROM powerman/dockerize:0.24.2 AS dockerize

FROM netdata/netdata:v2.9.0 AS netdata
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

COPY --from=dockerize /usr/local/bin/dockerize /usr/local/bin/

ARG UID_POSTFIX
ARG GID_POSTFIX
ARG GID_POSTDROP

ENV DEBIAN_FRONTEND=noninteractive

# - Install sudo for manual debugging.
# - Install postfix and sync it UID/GID with host to enable monitoring.
# - Install docker CLI… probably outdated and not needed anymore.
# - Add CAP_NET_RAW=eip on go.d.plugin to enable ping monitoring.
RUN curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null; \
    apt-get update; \
    apt-get install --no-install-recommends -y \
        sudo=* postfix=* docker-ce-cli=*; \
    find / -mount -not -path '/var/spool/postfix/*' -user postfix -exec chown "$UID_POSTFIX" {} \;; \
    find / -mount -not -path '/var/spool/postfix/*' -group postfix -exec chgrp "$GID_POSTFIX" {} \;; \
    find / -mount -not -path '/var/spool/postfix/*' -group postdrop -exec chgrp "$GID_POSTDROP" {} \;; \
    chmod g+s /usr/sbin/postdrop /usr/sbin/postqueue; \
    usermod -u 60000 "$(getent passwd "$UID_POSTFIX" | cut -d: -f1)" 2>/dev/null || :; \
    groupmod -g 60000 "$(getent group "$GID_POSTFIX" | cut -d: -f1)" 2>/dev/null || :; \
    groupmod -g 60001 "$(getent group "$GID_POSTDROP" | cut -d: -f1)" 2>/dev/null || :; \
    usermod -u "$UID_POSTFIX" postfix; \
    groupmod -g "$GID_POSTFIX" postfix; \
    groupmod -g "$GID_POSTDROP" postdrop; \
    setcap CAP_NET_RAW=eip /usr/libexec/netdata/plugins.d/go.d.plugin; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY etc-netdata /etc/netdata.tmpl

ENTRYPOINT ["dockerize", "-exec", "-template-strict", \
    "-template", "/etc/netdata.tmpl:/etc/netdata", \
    "/usr/sbin/run.sh"]
