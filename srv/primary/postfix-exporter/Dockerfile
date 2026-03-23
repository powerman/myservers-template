# Re-package scratch-based exporter into Alpine for healthcheck support.
FROM ghcr.io/hsn723/postfix_exporter:0.19.0 AS exporter

FROM alpine:3.21

COPY --from=exporter /postfix_exporter /postfix_exporter

HEALTHCHECK CMD wget -q -O - http://127.0.0.1:9154/metrics | grep -q postfix_up

ENTRYPOINT ["/postfix_exporter"]
