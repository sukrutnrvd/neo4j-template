#!/bin/bash
set -e

# Railway injects PORT; default to 8080 for local runs
export PORT=${PORT:-8080}

# Render nginx config with the correct port
envsubst '${PORT}' < /nginx.conf.template > /etc/nginx/nginx.conf

# Start Neo4j in the background using its official entrypoint
/startup/docker-entrypoint.sh neo4j &

# Start nginx in the foreground (keeps the container alive)
exec nginx -g "daemon off;"
