# OpenTelemetry Demo for ITRS Analytics (IAX)

This is a fork of the [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/)
configured to send all telemetry (traces, metrics, logs) to an IAX instance via
OTLP/gRPC. Local observability backends (Jaeger, Prometheus, OpenSearch, Grafana)
are removed — IAX is the sole telemetry destination.

## Prerequisites

- Docker Engine 20.10+
- Docker Compose V2 (the `docker compose` plugin, **not** the standalone `docker-compose` v1)
- Network access to your IAX instance's OTLP ingestion endpoint

Verify Docker Compose V2 is installed:

```bash
docker compose version
# Expected: Docker Compose version v2.x.x or later
```

If `docker compose` is not found, install the plugin:

```bash
sudo apt install docker-compose-plugin   # Debian/Ubuntu with Docker's apt repo
```

---

## Running

Pull pre-built images from Nexus and run the demo. No source checkout required.

### Option 1: Full demo with Docker Compose (recommended)

Download the compose file and environment defaults, then start:

```bash
# 1. Download compose file and env defaults
curl -LO https://raw.githubusercontent.com/ITRS-Group/iax-opentelemetry-demo/main/docker-compose.iax.yml
curl -LO https://raw.githubusercontent.com/ITRS-Group/iax-opentelemetry-demo/main/.env
curl -LO https://raw.githubusercontent.com/ITRS-Group/iax-opentelemetry-demo/main/.env.iax

# 2. Log in to Nexus and pull images
docker login docker.itrsgroup.com
docker compose --env-file .env --env-file .env.iax -f docker-compose.iax.yml pull

# 3. Configure IAX credentials
cat > .env.iax.local <<'EOF'
IAX_OTLP_ENDPOINT=your-iax-host:443
IAX_INGESTION_USERNAME=your-username
IAX_INGESTION_PASSWORD=your-password
EOF

# 4. Start
docker compose --env-file .env --env-file .env.iax --env-file .env.iax.local \
  -f docker-compose.iax.yml up --detach
```

**Verify:**

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | sort
docker logs otel-collector --tail 20
```

All containers should show `Up`. The collector logs should show export activity
without `Unauthenticated` or `connection refused` errors.

**Access the demo:**


| URL                              | Description                                         |
| -------------------------------- | --------------------------------------------------- |
| `http://localhost:8080`          | Storefront — browse products, add to cart, checkout |
| `http://localhost:8080/loadgen/` | Load generator UI — adjust synthetic traffic volume |


The load generator starts automatically, so traces, metrics, and logs flow
to IAX as soon as the services are healthy (~30 seconds after start).

**Stop:**

```bash
docker compose -f docker-compose.iax.yml down --remove-orphans --volumes
```

### Option 2: Run individual services with `docker run`

For a lighter demo or proof-of-concept, run only the services you need. All
images are on Nexus and all configuration is via environment variables — no
files to mount.

**Step 1 — Start the collector** (all services send telemetry here):

```bash
docker login docker.itrsgroup.com

docker run -d --name otel-collector --network host \
  -e IAX_OTLP_ENDPOINT=your-iax-host:443 \
  -e IAX_OTLP_INSECURE=false \
  -e IAX_INGESTION_USERNAME=your-username \
  -e IAX_INGESTION_PASSWORD=your-password \
  docker.itrsgroup.com/iax-otel-demo/otel-collector:1.0.0 \
  --config=/etc/otelcol-config-standalone.yml
```

Verify it started:

```bash
docker logs otel-collector --tail 5
# Look for: "Everything is ready. Begin running and processing data."
```

**Step 2 — Start a demo service** (example: frontend on port 8080):

```bash
docker run -d --name frontend --network host \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
  -e OTEL_SERVICE_NAME=frontend \
  -e OTEL_RESOURCE_ATTRIBUTES=service.namespace=iax-otel-demo \
  -e PORT=8080 \
  docker.itrsgroup.com/iax-otel-demo/frontend:1.0.0
```

**Step 3 — Start the load generator** (drives traffic through the frontend):

```bash
docker run -d --name load-generator --network host \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
  -e OTEL_SERVICE_NAME=load-generator \
  -e OTEL_RESOURCE_ATTRIBUTES=service.namespace=iax-otel-demo \
  -e LOCUST_WEB_HOST=0.0.0.0 \
  -e LOCUST_WEB_PORT=8089 \
  -e LOCUST_AUTOSTART=true \
  -e LOCUST_HOST=http://localhost:8080 \
  docker.itrsgroup.com/iax-otel-demo/load-generator:1.0.0
```

The load generator UI is at `http://localhost:8089`.

**Step 4 — Verify:**

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
docker logs otel-collector --tail 10
```

**Step 5 — Clean up:**

```bash
docker rm -f otel-collector frontend load-generator
```

> **Note:** In this mode, only the services you start will generate telemetry.
> The full distributed-tracing experience (cross-service traces) requires all
> services running together — use Option 1 for that.

### Option 3: Point your own app at the collector

If you have your own OpenTelemetry-instrumented application, run just the
collector and configure your app to export to it.

**Step 1 — Start the collector:**

```bash
docker run -d --name otel-collector --network host \
  -e IAX_OTLP_ENDPOINT=your-iax-host:443 \
  -e IAX_OTLP_INSECURE=false \
  -e IAX_INGESTION_USERNAME=your-username \
  -e IAX_INGESTION_PASSWORD=your-password \
  docker.itrsgroup.com/iax-otel-demo/otel-collector:1.0.0 \
  --config=/etc/otelcol-config-standalone.yml
```

**Step 2 — Configure your app's OTLP exporter** to point at the collector:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_RESOURCE_ATTRIBUTES=service.namespace=my-app
```

Or, if your app runs in Docker:

```bash
docker run -d --network host \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
  -e OTEL_RESOURCE_ATTRIBUTES=service.namespace=my-app \
  your-app-image
```

The collector receives OTLP on ports 4317 (gRPC) and 4318 (HTTP), then
forwards everything to IAX.

---

## Building/Testing/Publishing

Build, test, and push images to Nexus. Requires a checkout of this repository.

### Build and test locally

```bash
git clone https://github.com/ITRS-Group/iax-opentelemetry-demo.git
cd iax-opentelemetry-demo

# Build all images (first build takes ~15 minutes)
make iax-build

# Configure credentials and start locally to verify
cat > .env.iax.local <<'EOF'
IAX_OTLP_ENDPOINT=your-iax-host:443
IAX_INGESTION_USERNAME=your-username
IAX_INGESTION_PASSWORD=your-password
EOF

make iax-start

# Verify: http://localhost:8080 for the storefront
# Stop when done
make iax-stop
```

### Push to Nexus

```bash
docker login docker.itrsgroup.com
make iax-push
```

Each service is a separate image under `docker.itrsgroup.com/iax-otel-demo/`,
for example:

- `docker.itrsgroup.com/iax-otel-demo/frontend:1.0.0`
- `docker.itrsgroup.com/iax-otel-demo/checkout:1.0.0`
- `docker.itrsgroup.com/iax-otel-demo/otel-collector:1.0.0`
- `docker.itrsgroup.com/iax-otel-demo/load-generator:1.0.0`

### Makefile targets


| Target           | Description                             |
| ---------------- | --------------------------------------- |
| `make iax-build` | Build all demo images tagged for Nexus  |
| `make iax-push`  | Build and push all images to Nexus      |
| `make iax-pull`  | Pull pre-built images from Nexus        |
| `make iax-start` | Start the demo (telemetry flows to IAX) |
| `make iax-stop`  | Stop the demo and clean up              |


### Configuration

Defaults live in `.env.iax` (tracked in git, no secrets). Per-user overrides
and credentials go in `.env.iax.local` (gitignored). The Makefile loads both
— `.env.iax.local` values override `.env.iax`.


| Variable                 | Default                              | Description                                            |
| ------------------------ | ------------------------------------ | ------------------------------------------------------ |
| `IAX_OTLP_ENDPOINT`      | `iax-ingestion.example.com:443`      | IAX Ingestion Service OTLP/gRPC address (host:port)    |
| `IAX_OTLP_INSECURE`      | `false`                              | Set to `true` only for non-TLS dev endpoints           |
| `IAX_INGESTION_USERNAME` | *(empty)*                            | IAX ingestion credential username (gRPC metadata auth) |
| `IAX_INGESTION_PASSWORD` | *(empty)*                            | IAX ingestion credential password                      |
| `IMAGE_REGISTRY`         | `docker.itrsgroup.com/iax-otel-demo` | Nexus registry path (each service is a separate image) |
| `VERSION`                | `1.0.0`                              | Image version tag (e.g. `frontend:1.0.0`)              |


---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Docker Compose (otel-demo-iax network)                     │
│                                                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       │
│  │ frontend │ │ checkout │ │ payment  │ │   cart   │  ...   │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘       │
│       │             │            │             │             │
│       └─────────────┴────────────┴─────────────┘             │
│                          │                                   │
│                ┌─────────▼──────────┐                        │
│                │   OTel Collector   │                        │
│                │  (otelcol-contrib)  │                        │
│                └─────────┬──────────┘                        │
│                          │ OTLP/gRPC                         │
└──────────────────────────┼───────────────────────────────────┘
                           │
                           ▼
                ┌─────────────────────┐
                │   IAX Instance      │
                │  (Ingestion Service │
                │   OTLP endpoint)    │
                └─────────────────────┘
```

## What Gets Sent to IAX

The OTel Collector forwards all three signal types:

- **Traces** — distributed traces across all 15+ microservices (Go, Java, .NET,
Python, Rust, Node.js, C++, PHP, Ruby)
- **Metrics** — application metrics, host metrics, Docker stats, Kafka metrics,
PostgreSQL metrics, Redis/Valkey metrics, HTTP checks, span metrics
- **Logs** — application logs from all services

All data is tagged with `service.namespace=iax-otel-demo` for easy filtering in IAX.

## Services


| Service         | Language      | Telemetry             |
| --------------- | ------------- | --------------------- |
| accounting      | .NET          | Traces, Metrics       |
| ad              | Java          | Traces, Metrics, Logs |
| cart            | .NET          | Traces, Metrics       |
| checkout        | Go            | Traces, Metrics       |
| currency        | C++           | Traces, Metrics       |
| email           | Ruby          | Traces, Metrics       |
| fraud-detection | Java/Kotlin   | Traces, Metrics       |
| frontend        | Node.js       | Traces, Metrics       |
| frontend-proxy  | Envoy         | Traces, Metrics       |
| image-provider  | Nginx         | Metrics               |
| load-generator  | Python/Locust | Traces, Metrics       |
| payment         | Node.js       | Traces, Metrics       |
| product-catalog | Go            | Traces, Metrics, Logs |
| product-reviews | Python        | Traces, Metrics, Logs |
| quote           | PHP           | Traces, Metrics       |
| recommendation  | Python        | Traces, Metrics, Logs |
| shipping        | Rust          | Traces, Metrics       |


## What to Expect in IAX

Once the demo is running and the collector is exporting successfully, data
appears in IAX within 1–2 minutes:

- **Traces** — distributed traces spanning multiple services (e.g., a checkout
request touches `frontend` → `checkout` → `payment` → `shipping` → `email`).
Filter by `service.namespace = iax-otel-demo` to isolate demo traffic.
- **Metrics** — application-level metrics (request counts, latencies, error
rates) plus infrastructure metrics (host, Docker stats, Kafka, PostgreSQL,
Valkey). Span metrics are auto-generated from traces.
- **Logs** — application logs from services that emit them (`ad`,
`product-catalog`, `product-reviews`, `recommendation`).

If you don't see data after 2 minutes, check the collector logs and refer to
the Troubleshooting section below.

## Troubleshooting

**View collector logs:**

```bash
docker logs otel-collector -f
```

`**Unauthenticated` errors:**
The collector logs show `rpc error: code = Unauthenticated`. Check that
`IAX_INGESTION_USERNAME` and `IAX_INGESTION_PASSWORD` are set correctly. For
Docker Compose, verify they are in `.env.iax.local`. For `docker run`, check
the `-e` flags.

`**connection refused` errors:**
The IAX endpoint is unreachable. Verify the hostname and port in
`IAX_OTLP_ENDPOINT`. If IAX is on a remote Kubernetes cluster, you may need
a port-forward:

```bash
kubectl port-forward svc/iax-ingestion 443:443 -n iax
# Then set IAX_OTLP_ENDPOINT=host.docker.internal:443
```

**TLS / certificate errors:**
Set `IAX_OTLP_INSECURE=true` if your IAX endpoint does not use TLS (e.g., a
local dev instance). Production endpoints should always use TLS (`false`).

`**docker compose` not found:**
You need Docker Compose V2 (the `docker compose` plugin), not the standalone
`docker-compose` v1. Install it:

```bash
sudo apt install docker-compose-plugin   # Debian/Ubuntu with Docker's apt repo
```

Verify with `docker compose version` — it should report v2.x.x or later.

**Container name conflicts:**
If you see `The container name "/frontend" is already in use`, remove the
stale container first:

```bash
docker rm -f frontend
```

To remove all demo containers at once (Docker Compose):

```bash
docker compose -f docker-compose.iax.yml down --remove-orphans --volumes
```

**Clean up images:**

```bash
docker images --format "{{.Repository}}:{{.Tag}}" | grep "iax-otel-demo/" | xargs docker rmi
```

