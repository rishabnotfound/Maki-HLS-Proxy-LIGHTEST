#!/bin/sh

# Set defaults
export CACHE_SIZE="${CACHE_SIZE:-5g}"
export CACHE_EXPIRY="${CACHE_EXPIRY:-12h}"

# Disable cache if size is 0
if [ "$CACHE_SIZE" = "0" ]; then
    export CACHE_SIZE="1m"
    export CACHE_EXPIRY="1s"
    echo "Caching disabled"
fi

mkdir -p /var/www/certbot /etc/letsencrypt

CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

# Issue cert on first boot (if DOMAIN set and cert missing)
if [ -n "$DOMAIN" ] && [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    echo "No cert for $DOMAIN — issuing via Let's Encrypt..."
    # Start a bare http server just for the challenge
    cat > /tmp/acme.conf <<EOF
events { worker_connections 128; }
http {
    server {
        listen 80;
        location ^~ /.well-known/acme-challenge/ { root /var/www/certbot; default_type "text/plain"; }
        location / { return 404; }
    }
}
EOF
    openresty -c /tmp/acme.conf
    sleep 1

    EMAIL_ARG="--register-unsafely-without-email"
    [ -n "$LETSENCRYPT_EMAIL" ] && EMAIL_ARG="--email $LETSENCRYPT_EMAIL"

    if certbot certonly --webroot -w /var/www/certbot \
         -d "$DOMAIN" --agree-tos --non-interactive $EMAIL_ARG; then
        echo "Cert issued for $DOMAIN"
    else
        echo "WARNING: certbot failed, continuing HTTP-only"
    fi
    openresty -c /tmp/acme.conf -s stop 2>/dev/null || true
    sleep 1
fi

# Build SSL config snippet if cert exists
if [ -n "$DOMAIN" ] && [ -f "$CERT_DIR/fullchain.pem" ]; then
    export LISTEN_443="listen 443 ssl http2;"
    export SSL_CONFIG="ssl_certificate $CERT_DIR/fullchain.pem;
        ssl_certificate_key $CERT_DIR/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_session_cache shared:SSL:10m;"
    echo "TLS: ENABLED for $DOMAIN"
else
    export LISTEN_443=""
    export SSL_CONFIG=""
    echo "TLS: disabled (set DOMAIN to enable)"
fi

envsubst '${CACHE_SIZE} ${CACHE_EXPIRY} ${LISTEN_443} ${SSL_CONFIG}' \
    < /usr/local/openresty/nginx/conf/nginx.conf.template \
    > /usr/local/openresty/nginx/conf/nginx.conf

mkdir -p /cache
chown -R nobody:nobody /cache
chmod -R 755 /cache

if [ -n "$ENCRYPTION_KEY" ]; then
    KEY_LEN=$(printf %s "$ENCRYPTION_KEY" | wc -c | tr -d ' ')
    if [ "$KEY_LEN" = "64" ]; then
        echo "Encryption: ENABLED (AES-256-CBC)"
    else
        echo "WARNING: ENCRYPTION_KEY must be 64 hex chars, got $KEY_LEN. Encryption will be disabled."
    fi
else
    echo "Encryption: disabled (set ENCRYPTION_KEY to enable)"
fi

echo "Starting with CACHE_SIZE=$CACHE_SIZE, CACHE_EXPIRY=$CACHE_EXPIRY"

# Renewal loop in background (checks every 12h, certbot internally no-ops if >30d left)
(
    while true; do
        sleep 43200
        if [ -n "$DOMAIN" ] && [ -f "$CERT_DIR/fullchain.pem" ]; then
            certbot renew --webroot -w /var/www/certbot --quiet \
                --deploy-hook "openresty -s reload" || true
        fi
    done
) &

exec openresty -g "daemon off;"
