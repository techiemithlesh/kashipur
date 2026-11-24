FROM nginx:1.29-alpine

RUN rm -f /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/nginx.conf
COPY http-bootstrap.conf.template /etc/nginx/templates/http-bootstrap.conf.template
COPY http-redirect.conf.template /etc/nginx/templates/http-redirect.conf.template
COPY tls.conf.template /etc/nginx/templates/tls.conf.template
COPY proxy-headers.conf /etc/nginx/snippets/proxy-headers.conf
COPY --chmod=0755 nginx-entrypoint.sh /usr/local/bin/swm-nginx-entrypoint

ENTRYPOINT ["/usr/local/bin/swm-nginx-entrypoint"]

