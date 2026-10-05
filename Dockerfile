FROM openresty/openresty:alpine

# Install dependencies
RUN apk add --no-cache perl curl gettext certbot openssl

# Install lua-resty-http via opm
RUN opm get ledgetech/lua-resty-http

# Copy nginx configuration as template (envsubst replaces vars at runtime)
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf.template
COPY lua/ /usr/local/openresty/nginx/lua/
COPY allowed_origins.txt /usr/local/openresty/nginx/allowed_origins.txt
COPY index.html /usr/local/openresty/nginx/html/index.html
COPY public/ /usr/local/openresty/nginx/html/public/

# Copy and setup entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
