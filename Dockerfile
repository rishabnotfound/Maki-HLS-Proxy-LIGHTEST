FROM openresty/openresty:alpine

# Install dependencies for opm
RUN apk add --no-cache perl curl

# Install lua-resty-http via opm
RUN opm get ledgetech/lua-resty-http

# Copy nginx configuration
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY allowed_origins.txt /usr/local/openresty/nginx/allowed_origins.txt
COPY index.html /usr/local/openresty/nginx/html/index.html

EXPOSE 80

CMD ["openresty", "-g", "daemon off;"]
