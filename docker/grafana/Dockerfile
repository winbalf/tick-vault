FROM grafana/grafana:11.6.2

USER root
RUN apk add --no-cache jq

COPY docker/grafana/tickvault-entrypoint.sh /etc/grafana/tickvault-entrypoint.sh
RUN chmod +x /etc/grafana/tickvault-entrypoint.sh

USER grafana
ENTRYPOINT ["/etc/grafana/tickvault-entrypoint.sh"]
