# syntax=docker/dockerfile:1
FROM powerman/dockerize:0.24.2 AS dockerize

FROM alpine:3.23.3
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

COPY --from=dockerize /usr/local/bin/dockerize /usr/local/bin/

RUN apk add --no-cache dcron=~4.6 msmtp=~1 mailx=~8 bash=~5 pflogsumm=~1.1.8 docker-cli=~29; \
    ln -sf /usr/bin/msmtp /usr/bin/sendmail; \
    ln -sf /usr/bin/msmtp /usr/sbin/sendmail

COPY .msmtprc /root/
COPY cron.d /etc/cron.d/

CMD ["crond", "-f"]

HEALTHCHECK --interval=1m CMD find /health-check -mmin -2 | grep -q .
