# syntax=docker/dockerfile:1
FROM powerman/dockerize:0.24.2 AS dockerize

FROM alpine:3.23.3
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

COPY --from=dockerize /usr/local/bin/dockerize /usr/local/bin/

RUN apk add --no-cache dcron=~4.6 msmtp=~1 mailx=~8 bash=~5 \
        duplicity=~3.0.6 rclone=~1.72.1 pflogsumm=~1.1.8 \
        sqlite=~3 docker-cli=~29; \
    ln -sf /usr/bin/msmtp /usr/bin/sendmail; \
    ln -sf /usr/bin/msmtp /usr/sbin/sendmail; \
    mkdir -p ~/.config/rclone

COPY .msmtprc /root/
COPY cron.d /etc/cron.d/
COPY rclone.conf.tmpl /
COPY duplicity /etc/duplicity/
RUN --mount=type=secret,id=dcron_duplicity_gpg_pass \
    install -m 0400 /run/secrets/dcron_duplicity_gpg_pass /etc/duplicity/gpg.pass
COPY bin /usr/local/bin/

ENTRYPOINT ["dockerize", "-exec", "-template-strict", \
    "-template", "/rclone.conf.tmpl:/root/.config/rclone/rclone.conf"]
CMD ["crond", "-f"]

HEALTHCHECK --interval=1m CMD find /health-check -mmin -2 | grep -q .
