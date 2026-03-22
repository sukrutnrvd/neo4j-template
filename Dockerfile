# Use the official Neo4j image for importing data
FROM neo4j:5.25.1 as neo4j-import

# Set environment variables
ARG NODE_CSV_URLS=""
ARG RELATION_CSV_URLS=""

ENV NODE_CSV_URLS=${NODE_CSV_URLS}
ENV RELATION_CSV_URLS=${RELATION_CSV_URLS}



# Create necessary directories for Neo4j
RUN mkdir -p /data /import

# Install curl to download the CSV files
RUN apt-get update && apt-get install -y curl

# Create download and process scripts
COPY <<-'EOF' /download.sh
#!/bin/bash
validate_and_download() {
    url=$1
    output=$2
    description=$3
    
    if [ -z "$url" ]; then
        return 1
    fi
    
    echo "Validating $description URL: $url"
    http_code=$(curl -L --connect-timeout 10 --max-time 30 -s -o /dev/null -w "%{http_code}" "$url")
    
    if [ "$http_code" = "200" ]; then
        echo "URL is valid. Downloading $description..."
        if curl -L --connect-timeout 10 --max-time 30 -f -o "$output" "$url"; then
            if [ -s "$output" ]; then
                echo "$description downloaded successfully"
                return 0
            fi
        fi
    fi
    
    echo "Warning: Failed to download $description from $url"
    rm -f "$output"
    return 1
}

process_urls() {
    urls=$1
    type=$2
    counter=1
    success=false
    
    if [ -n "$urls" ]; then
        echo "Processing URLs for $type: $urls"
        IFS=',' read -ra URL_ARRAY <<< "$urls"
        for url in "${URL_ARRAY[@]}"; do
            url=$(echo "$url" | tr -d '[:space:]')
            if [ -n "$url" ]; then
                output="/import/${type}_${counter}.csv"
                if validate_and_download "$url" "$output" "${type^} CSV $counter"; then
                    success=true
                    ((counter++))
                fi
            fi
        done
    fi
    
    [ "$success" = true ]
}

# Process node URLs
if [ -n "$NODE_CSV_URLS" ]; then
    process_urls "$NODE_CSV_URLS" "node"
fi

# Process relation URLs
if [ -n "$RELATION_CSV_URLS" ]; then
    process_urls "$RELATION_CSV_URLS" "relation"
fi
EOF

RUN chmod +x /download.sh && /download.sh

# Import files based on what's available
RUN files_exist=false && \
    IMPORT_CMD="neo4j-admin database import full neo4j" && \
    for f in /import/node_*.csv; do \
        if [ -f "$f" ]; then \
            IMPORT_CMD="$IMPORT_CMD --nodes=$f"; \
            files_exist=true; \
        fi; \
    done && \
    for f in /import/relation_*.csv; do \
        if [ -f "$f" ]; then \
            IMPORT_CMD="$IMPORT_CMD --relationships=$f"; \
            files_exist=true; \
        fi; \
    done && \
    if [ "$files_exist" = true ]; then \
        eval "$IMPORT_CMD" && \
        echo "Import completed successfully"; \
    else \
        echo "No CSV files available for import"; \
    fi

# Second stage for running Neo4j with the preloaded data

FROM neo4j:5.25.1

ARG DB_PASSWORD=""
ARG HEAP_INITIAL_SIZE="1g"
ARG HEAP_MAX_SIZE="1g"
ARG PAGECACHE_SIZE="4g"

# Set environment variables
ENV NEO4J_AUTH=neo4j/${DB_PASSWORD}
ENV HEAP_INITIAL_SIZE=${HEAP_INITIAL_SIZE}
ENV HEAP_MAX_SIZE=${HEAP_MAX_SIZE}
ENV PAGECACHE_SIZE=${PAGECACHE_SIZE}

RUN echo "NEO4J_AUTH=${DB_PASSWORD}"
RUN echo "HEAP_INITIAL_SIZE=${HEAP_INITIAL_SIZE}"
RUN echo "HEAP_MAX_SIZE=${HEAP_MAX_SIZE}"
RUN echo "PAGECACHE_SIZE=${PAGECACHE_SIZE}"

# Use the preloaded database from the import stage
COPY --from=neo4j-import /data /data



COPY neo4j.conf /var/lib/neo4j/conf/neo4j.conf
COPY server-logs.xml /var/lib/neo4j/conf/server-logs.xml
COPY user-logs.xml /var/lib/neo4j/conf/server-logs.xml

# Create a script to update Neo4j configuration with environment variables
RUN echo '#!/bin/bash\n\
# Remove all existing memory configuration lines (including comments)\n\
sed -i "/server.memory.heap.initial_size/d" /var/lib/neo4j/conf/neo4j.conf\n\
sed -i "/server.memory.heap.max_size/d" /var/lib/neo4j/conf/neo4j.conf\n\
sed -i "/server.memory.pagecache.size/d" /var/lib/neo4j/conf/neo4j.conf\n\
# Add new memory configuration at the end of the file\n\
echo "" >> /var/lib/neo4j/conf/neo4j.conf\n\
echo "# Memory configuration from environment variables" >> /var/lib/neo4j/conf/neo4j.conf\n\
echo "server.memory.heap.initial_size=${HEAP_INITIAL_SIZE}" >> /var/lib/neo4j/conf/neo4j.conf\n\
echo "server.memory.heap.max_size=${HEAP_MAX_SIZE}" >> /var/lib/neo4j/conf/neo4j.conf\n\
echo "server.memory.pagecache.size=${PAGECACHE_SIZE}" >> /var/lib/neo4j/conf/neo4j.conf\n\
echo "Neo4j configuration updated with environment variables"' > /update-config.sh && chmod +x /update-config.sh

# Run the update script before starting Neo4j
RUN /update-config.sh

# Install nginx for reverse proxying (routes WebSocket → Bolt, HTTP → Neo4j Browser)
RUN apt-get update && apt-get install -y nginx gettext-base && rm -rf /var/lib/apt/lists/*

COPY nginx.conf.template /nginx.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose single port (Railway HTTP proxy)
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
