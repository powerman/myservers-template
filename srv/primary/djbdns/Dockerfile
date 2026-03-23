# syntax=docker/dockerfile:1
FROM alpine:3.23.3 AS djbdns
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

RUN echo '@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories; \
    apk add --no-cache djbdns=~1.05 tinydns=~1.05 dnscache=~1.05 \
        ucspi-tcp6=~1.13 daemontools@testing=~0.76 rsync=~3 bind-tools=~9; \
    adduser -S -u 500 djbdns; \
    install -d -o djbdns -g nogroup /home/djbdns/root

ENV UID=djbdns
ENV GID=nogroup
ENV ROOT=/home/djbdns/root/

WORKDIR /home/djbdns/root/


FROM djbdns AS tinydns-wan

VOLUME /home/djbdns/root/

ENV IP=0.0.0.0

COPY --chown=djbdns:nogroup wan/data /data

ENTRYPOINT ["sh", "-c", "rsync /data data && tinydns-data && exec \"$0\" \"$@\""]
CMD ["softlimit", "-d400000", \
    "tinydns"]

HEALTHCHECK CMD host -U -r -W 1 -t soa example.com 127.0.0.1 | grep -qw SOA


FROM djbdns AS axfrdns-wan

VOLUME /home/djbdns/root/

COPY wan/tcp.axfrdns /
RUN tcprules /tcp.axfrdns.cdb /tcp.axfrdns.cdb.tmp < /tcp.axfrdns

CMD ["softlimit", "-d4000000", \
    "tcpserver", "-vDRHl0", "-x", "/tcp.axfrdns.cdb", "--", "0.0.0.0", "53", \
    "axfrdns"]

HEALTHCHECK CMD host -T -r -W 1 -t soa example.com 127.0.0.1 | grep -qw SOA
