# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Docker template for deploying Neo4j 5.25.1 with optional bulk CSV data import at build time and configurable memory settings. The entire project is Docker-based with no application runtime dependencies.

## Build Commands

**Minimal build (no data import):**
```bash
docker build --build-arg DB_PASSWORD=your-password -t my-neo4j .
```

**With custom memory settings:**
```bash
docker build \
  --build-arg HEAP_INITIAL_SIZE=2g \
  --build-arg HEAP_MAX_SIZE=2g \
  --build-arg PAGECACHE_SIZE=8g \
  --build-arg DB_PASSWORD=your-password \
  -t my-neo4j .
```

**With data import:**
```bash
docker build \
  --build-arg NODE_CSV_URLS="https://example.com/nodes.csv" \
  --build-arg RELATION_CSV_URLS="https://example.com/rels.csv" \
  --build-arg DB_PASSWORD=your-password \
  -t my-neo4j .
```

**Run the container:**
```bash
# Port 8080 = nginx (Neo4j Browser UI + Bolt via WebSocket)
# Port 7687 = direct Bolt access for drivers
docker run -p 8080:8080 -p 7687:7687 my-neo4j
```

## Build Arguments

| Argument | Default | Description |
|---|---|---|
| `DB_PASSWORD` | `""` | **Required.** Sets `NEO4J_AUTH=neo4j/<password>` |
| `HEAP_INITIAL_SIZE` | `"1g"` | JVM initial heap (`server.memory.heap.initial_size`) |
| `HEAP_MAX_SIZE` | `"1g"` | JVM max heap (`server.memory.heap.max_size`) |
| `PAGECACHE_SIZE` | `"4g"` | Neo4j page cache (`server.memory.pagecache.size`) |
| `NODE_CSV_URLS` | `""` | Comma-separated URLs for node CSV files |
| `RELATION_CSV_URLS` | `""` | Comma-separated URLs for relationship CSV files |

## Architecture

### Two-Stage Docker Build

**Stage 1 (`neo4j-import`):** Downloads CSV files from URLs, validates HTTP 200 responses, saves them as `/import/node_N.csv` and `/import/relation_N.csv`, then runs `neo4j-admin database import full neo4j` to pre-load the database. If no CSVs are provided, this stage exits cleanly without importing.

**Stage 2 (runtime):** Copies the pre-loaded `/data` directory from stage 1, copies `neo4j.conf`, `server-logs.xml`, and `user-logs.xml` into `/var/lib/neo4j/conf/`, then runs `/update-config.sh` which strips any existing memory settings from `neo4j.conf` and appends them from the build args. Exposes ports 7474 (HTTP/Browser) and 7687 (Bolt).

### Railway Deployment Notes

Railway serves the app over HTTPS but Neo4j Browser (when loaded via HTTPS) cannot make unencrypted WebSocket connections to Bolt due to browser mixed-content rules.

**Solution:** nginx runs as a reverse proxy on port 8080 (Railway's HTTP proxy port). It routes incoming connections based on the `Upgrade` header:
- `Upgrade: websocket` → forwarded to Neo4j Bolt (port 7687)
- regular HTTP → forwarded to Neo4j Browser UI (port 7474)

This way Railway handles TLS (using its own `*.railway.app` certificate), and Neo4j itself needs no SSL configuration.

**Startup flow:** `entrypoint.sh` renders `nginx.conf.template` (substituting `$PORT`), starts Neo4j via `/startup/docker-entrypoint.sh neo4j` in the background, then runs nginx in the foreground.

**To connect from Neo4j Browser on Railway:**
In the connection dialog, enter: `neo4j+s://your-app.railway.app` (no port — Railway uses standard 443)

### Configuration Files

- **`neo4j.conf`** — Main Neo4j config. Memory settings here are always overridden at build time by `/update-config.sh`. `server.default_listen_address=0.0.0.0` is set to accept external connections.
- **`server-logs.xml`** — Log4j2 config for server-side logging (HTTP, query, security logs).
- **`user-logs.xml`** — Log4j2 config for user-facing Neo4j logs. Note: both XML files are copied to the same destination path in the Dockerfile (`/var/lib/neo4j/conf/server-logs.xml`), so `user-logs.xml` overwrites `server-logs.xml` at build time.

### Ports
- `7474` — HTTP (Neo4j Browser UI)
- `7687` — Bolt (database protocol)
