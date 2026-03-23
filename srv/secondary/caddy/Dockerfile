# syntax=docker/dockerfile:1
FROM powerman/dockerize:0.24.2 AS dockerize


FROM caddy:2.11.2
SHELL ["/bin/ash", "-e", "-o", "pipefail", "-c"]

RUN apk --no-cache add nss-tools=~3

COPY --from=dockerize /usr/local/bin/dockerize /usr/local/bin/

COPY Caddyfile.tmpl /

ENTRYPOINT ["dockerize", "-exec", "-template-strict", "-template", "/Caddyfile.tmpl:/etc/caddy/Caddyfile"]
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

HEALTHCHECK CMD wget -q -O - 127.0.0.1:2019/config | grep -q '^{'
