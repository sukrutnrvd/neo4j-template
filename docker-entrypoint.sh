#!/bin/bash
set -e

# Update memory configuration from environment variables
sed -i "/server.memory.heap.initial_size/d" /var/lib/neo4j/conf/neo4j.conf
sed -i "/server.memory.heap.max_size/d" /var/lib/neo4j/conf/neo4j.conf
sed -i "/server.memory.pagecache.size/d" /var/lib/neo4j/conf/neo4j.conf

echo "" >> /var/lib/neo4j/conf/neo4j.conf
echo "# Memory configuration from environment variables" >> /var/lib/neo4j/conf/neo4j.conf
echo "server.memory.heap.initial_size=${HEAP_INITIAL_SIZE}" >> /var/lib/neo4j/conf/neo4j.conf
echo "server.memory.heap.max_size=${HEAP_MAX_SIZE}" >> /var/lib/neo4j/conf/neo4j.conf
echo "server.memory.pagecache.size=${PAGECACHE_SIZE}" >> /var/lib/neo4j/conf/neo4j.conf
echo "Neo4j configuration updated with environment variables"

# TLS Setup (opt-in via ENABLE_TLS=true)
if [ "${ENABLE_TLS}" = "true" ]; then
    echo "TLS is enabled. Setting up certificates..."

    BOLT_CERT_DIR=/var/lib/neo4j/certificates/bolt
    HTTPS_CERT_DIR=/var/lib/neo4j/certificates/https

    mkdir -p "$BOLT_CERT_DIR/trusted" "$BOLT_CERT_DIR/revoked"
    mkdir -p "$HTTPS_CERT_DIR/trusted" "$HTTPS_CERT_DIR/revoked"

    # Generate self-signed certificate if not already present
    if [ ! -f "$BOLT_CERT_DIR/private.key" ]; then
        echo "Generating self-signed TLS certificate..."
        openssl req -x509 -newkey rsa:4096 -keyout "$BOLT_CERT_DIR/private.key" \
            -out "$BOLT_CERT_DIR/public.crt" -days 3650 -nodes \
            -subj "/CN=${TLS_HOSTNAME:-localhost}" \
            -addext "subjectAltName=DNS:${TLS_HOSTNAME:-localhost},DNS:localhost"

        # Copy the same cert for HTTPS
        cp "$BOLT_CERT_DIR/private.key" "$HTTPS_CERT_DIR/private.key"
        cp "$BOLT_CERT_DIR/public.crt" "$HTTPS_CERT_DIR/public.crt"

        # Also place public cert in trusted dirs
        cp "$BOLT_CERT_DIR/public.crt" "$BOLT_CERT_DIR/trusted/"
        cp "$HTTPS_CERT_DIR/public.crt" "$HTTPS_CERT_DIR/trusted/"

        echo "TLS certificate generated successfully."
    else
        echo "TLS certificates already exist, skipping generation."
    fi

    # Set correct permissions
    chown -R neo4j:neo4j /var/lib/neo4j/certificates
    chmod 600 "$BOLT_CERT_DIR/private.key" "$HTTPS_CERT_DIR/private.key"

    # Enable SSL policies in neo4j.conf
    cat >> /var/lib/neo4j/conf/neo4j.conf <<SSLEOF

# TLS configuration (auto-generated)
dbms.ssl.policy.bolt.enabled=true
dbms.ssl.policy.bolt.base_directory=certificates/bolt
dbms.ssl.policy.bolt.private_key=private.key
dbms.ssl.policy.bolt.public_certificate=public.crt
dbms.ssl.policy.bolt.client_auth=NONE
server.bolt.tls_level=OPTIONAL

dbms.ssl.policy.https.enabled=true
dbms.ssl.policy.https.base_directory=certificates/https
dbms.ssl.policy.https.private_key=private.key
dbms.ssl.policy.https.public_certificate=public.crt
dbms.ssl.policy.https.client_auth=NONE
server.https.enabled=true
SSLEOF

    echo "TLS configuration applied to neo4j.conf"
fi

# Configure Bolt advertised address for Railway (required for Neo4j Browser to connect)
# BOLT_ADVERTISED_ADDRESS should be set to your Railway public domain + mapped Bolt port
# e.g. "your-app.up.railway.app:12345" (Railway assigns a random public TCP port)
if [ -n "${BOLT_ADVERTISED_ADDRESS}" ]; then
    sed -i "/server.bolt.advertised_address/d" /var/lib/neo4j/conf/neo4j.conf
    echo "server.bolt.advertised_address=${BOLT_ADVERTISED_ADDRESS}" >> /var/lib/neo4j/conf/neo4j.conf
    echo "Bolt advertised address set to: ${BOLT_ADVERTISED_ADDRESS}"
fi

# Configure HTTP advertised address if provided
if [ -n "${HTTP_ADVERTISED_ADDRESS}" ]; then
    sed -i "/server.http.advertised_address/d" /var/lib/neo4j/conf/neo4j.conf
    echo "server.http.advertised_address=${HTTP_ADVERTISED_ADDRESS}" >> /var/lib/neo4j/conf/neo4j.conf
    echo "HTTP advertised address set to: ${HTTP_ADVERTISED_ADDRESS}"
fi

# Start Neo4j
exec neo4j console
