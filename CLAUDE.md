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
docker run -p 7474:7474 -p 7687:7687 my-neo4j
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

Railway serves the Neo4j Browser (port 7474) over HTTPS. Because of browser mixed-content rules, an HTTPS page cannot make unencrypted WebSocket connections, so the Bolt connector must also use TLS.

The Dockerfile generates a self-signed certificate at build time under `/var/lib/neo4j/certificates/bolt/`. The `neo4j.conf` sets `server.bolt.tls_level=OPTIONAL` so local (non-TLS) connections still work.

**To connect from Neo4j Browser on Railway:**
1. In Railway, add a TCP proxy for port 7687 to get a public `hostname:port`
2. In the Neo4j Browser connection screen, enter: `neo4j+ssc://hostname:port`
   - `neo4j+ssc://` = secure Bolt but skips certificate validation (needed for self-signed certs)

### Configuration Files

- **`neo4j.conf`** — Main Neo4j config. Memory settings here are always overridden at build time by `/update-config.sh`. `server.default_listen_address=0.0.0.0` is set to accept external connections.
- **`server-logs.xml`** — Log4j2 config for server-side logging (HTTP, query, security logs).
- **`user-logs.xml`** — Log4j2 config for user-facing Neo4j logs. Note: both XML files are copied to the same destination path in the Dockerfile (`/var/lib/neo4j/conf/server-logs.xml`), so `user-logs.xml` overwrites `server-logs.xml` at build time.

### Ports
- `7474` — HTTP (Neo4j Browser UI)
- `7687` — Bolt (database protocol)
