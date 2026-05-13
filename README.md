# OpenTelemetry Demo for ITRS Analytics (IAX)

This is a fork of the [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/)
configured to send all telemetry (traces, metrics, logs) to an IAX instance via
OTLP/gRPC. Local observability backends (Jaeger, Prometheus, OpenSearch, Grafana)
are removed — IAX is the sole telemetry destination.

## Prerequisites

**Docker Compose (Options 1–3):**

- Docker Engine 20.10+
- Docker Compose V2 (the `docker compose` plugin, **not** the standalone `docker-compose` v1)
- Network access to your IAX instance's OTLP ingestion endpoint

**Kubernetes / Helm (Option 4):**

- Kubernetes 1.24+
- Helm 3.10+
- `kubectl` configured for your cluster
- Network access from the cluster to your IAX instance's OTLP ingestion endpoint

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
  -e IAX_OTLP_INSECURE_SKIP_VERIFY=false \
  -e IAX_INGESTION_USERNAME=your-username \
  -e IAX_INGESTION_PASSWORD=your-password \
  docker.itrsgroup.com/iax-otel-demo/otel-collector:1.0.3 \
  --config=/etc/otelcol-config-standalone.yml
```

Verify it started:

```bash
docker logs otel-collector --tail 5
# Look for: "Everything is ready. Begin running and processing data."
```

**Step 2 — Start a demo service** (example: trader-order-entry on port 8080):

```bash
docker run -d --name trader-order-entry --network host \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
  -e OTEL_SERVICE_NAME=trader-order-entry \
  -e OTEL_RESOURCE_ATTRIBUTES=service.namespace=iax-otel-demo \
  -e PORT=8080 \
  docker.itrsgroup.com/iax-otel-demo/trader-order-entry:1.0.3
```

**Step 3 — Start the load generator** (drives traffic through the trader-order-entry):

```bash
docker run -d --name simulated-fix-order-flow --network host \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
  -e OTEL_SERVICE_NAME=simulated-fix-order-flow \
  -e OTEL_RESOURCE_ATTRIBUTES=service.namespace=iax-otel-demo \
  -e LOCUST_WEB_HOST=0.0.0.0 \
  -e LOCUST_WEB_PORT=8089 \
  -e LOCUST_AUTOSTART=true \
  -e LOCUST_HOST=http://localhost:8080 \
  docker.itrsgroup.com/iax-otel-demo/simulated-fix-order-flow:1.0.3
```

The load generator UI is at `http://localhost:8089`.

**Step 4 — Verify:**

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
docker logs otel-collector --tail 10
```

**Step 5 — Clean up:**

```bash
docker rm -f otel-collector trader-order-entry simulated-fix-order-flow
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
  -e IAX_OTLP_INSECURE_SKIP_VERIFY=false \
  -e IAX_INGESTION_USERNAME=your-username \
  -e IAX_INGESTION_PASSWORD=your-password \
  docker.itrsgroup.com/iax-otel-demo/otel-collector:1.0.3 \
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

### Option 4: Deploy to Kubernetes with Helm

A standalone Helm chart is included at `charts/iax-otel-demo/`. It deploys
all demo microservices, infrastructure (PostgreSQL, Valkey, Kafka, flagd),
and an OTel Collector pre-configured to export to IAX.

**Install:**

```bash
helm install iax-demo ./charts/iax-otel-demo/ \
  --set iax.otlpEndpoint=your-iax-host:443 \
  --set iax.ingestionUsername=your-username \
  --set iax.ingestionPassword=your-password
```

**With a private registry (pull secret):**

```bash
kubectl create secret docker-registry nexus-pull \
  --docker-server=docker.itrsgroup.com \
  --docker-username=your-user \
  --docker-password=your-pass

helm install iax-demo ./charts/iax-otel-demo/ \
  --set iax.otlpEndpoint=your-iax-host:443 \
  --set iax.ingestionUsername=your-username \
  --set iax.ingestionPassword=your-password \
  --set 'global.imagePullSecrets[0].name=nexus-pull'
```

**With an existing Secret for IAX credentials:**

```bash
kubectl create secret generic my-iax-creds \
  --from-literal=IAX_OTLP_ENDPOINT=your-iax-host:443 \
  --from-literal=IAX_OTLP_INSECURE=false \
  --from-literal=IAX_OTLP_INSECURE_SKIP_VERIFY=false \
  --from-literal=IAX_INGESTION_USERNAME=your-username \
  --from-literal=IAX_INGESTION_PASSWORD=your-password

helm install iax-demo ./charts/iax-otel-demo/ \
  --set iax.existingSecret=my-iax-creds
```

**Enable Ingress:**

```bash
helm install iax-demo ./charts/iax-otel-demo/ \
  --set iax.otlpEndpoint=your-iax-host:443 \
  --set iax.ingestionUsername=your-username \
  --set iax.ingestionPassword=your-password \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set 'ingress.hosts[0].host=demo.example.com' \
  --set 'ingress.hosts[0].paths[0].path=/' \
  --set 'ingress.hosts[0].paths[0].pathType=Prefix' \
  --set 'ingress.hosts[0].paths[0].port=8080'
```

**Verify:**

```bash
kubectl get pods -l app.kubernetes.io/part-of=iax-otel-demo
kubectl logs deploy/iax-demo-otel-collector --tail 20
```

**Access the demo** (without Ingress):

```bash
kubectl port-forward svc/fix-api-gateway 8080:8080
# Open http://localhost:8080
```

**Uninstall:**

```bash
helm uninstall iax-demo
```

**Helm values reference:**

| Value | Default | Description |
| ----- | ------- | ----------- |
| `global.imageRegistry` | `docker.itrsgroup.com/iax-otel-demo` | Container image registry |
| `global.imageTag` | `1.0.3` | Image tag for all demo services |
| `global.imagePullSecrets` | `[]` | Pull secrets for private registries |
| `iax.otlpEndpoint` | `iax-ingestion.example.com:443` | IAX OTLP/gRPC endpoint |
| `iax.otlpInsecure` | `false` | Disable TLS (dev only) |
| `iax.otlpInsecureSkipVerify` | `false` | Skip TLS cert verification |
| `iax.ingestionUsername` | `""` | IAX ingestion username |
| `iax.ingestionPassword` | `""` | IAX ingestion password |
| `iax.existingSecret` | `""` | Use a pre-existing Secret |
| `ingress.enabled` | `false` | Enable Ingress for the API gateway |
| `components.<name>.enabled` | `true` | Enable/disable individual services |

See [`charts/iax-otel-demo/values.yaml`](charts/iax-otel-demo/values.yaml)
for the full list of configurable values.

---

## Building/Testing/Publishing

Requires a checkout of this repository.

```bash
git clone https://github.com/ITRS-Group/iax-opentelemetry-demo.git
cd iax-opentelemetry-demo
```

### Build and test images locally

```bash
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

- `docker.itrsgroup.com/iax-otel-demo/trader-order-entry:1.0.3`
- `docker.itrsgroup.com/iax-otel-demo/order-routing:1.0.3`
- `docker.itrsgroup.com/iax-otel-demo/otel-collector:1.0.3`
- `docker.itrsgroup.com/iax-otel-demo/simulated-fix-order-flow:1.0.3`

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
| `IAX_OTLP_INSECURE_SKIP_VERIFY` | `false`                       | Set to `true` to skip TLS certificate verification (self-signed certs) |
| `IAX_INGESTION_USERNAME` | *(empty)*                            | IAX ingestion credential username (gRPC metadata auth) |
| `IAX_INGESTION_PASSWORD` | *(empty)*                            | IAX ingestion credential password                      |
| `IMAGE_REGISTRY`         | `docker.itrsgroup.com/iax-otel-demo` | Nexus registry path (each service is a separate image) |
| `VERSION`                | `1.0.3`                              | Image version tag (e.g. `trader-order-entry:1.0.3`)              |


### Helm chart

The Helm chart lives at `charts/iax-otel-demo/`. It does not need to be
built — Helm renders it directly from source. The workflows below cover
linting, testing, packaging, and publishing.

**Lint:**

```bash
helm lint ./charts/iax-otel-demo/
```

**Render templates locally** (dry-run without a cluster):

```bash
helm template iax-demo ./charts/iax-otel-demo/ \
  --set iax.otlpEndpoint=test-host:443 \
  --set iax.ingestionUsername=test-user \
  --set iax.ingestionPassword=test-pass
```

Pipe through `kubectl apply --dry-run=client -f -` to validate against the
Kubernetes API schema:

```bash
helm template iax-demo ./charts/iax-otel-demo/ \
  --set iax.otlpEndpoint=test-host:443 \
  --set iax.ingestionUsername=test-user \
  --set iax.ingestionPassword=test-pass \
  | kubectl apply --dry-run=client -f -
```

**Test with custom values:**

Create a `values-dev.yaml` override file for your environment:

```yaml
iax:
  otlpEndpoint: "your-iax-host:443"
  ingestionUsername: "your-username"
  ingestionPassword: "your-password"

global:
  imageTag: "1.0.3"

components:
  simulated-fix-order-flow:
    enabled: false   # disable load generator during testing
```

Then install or upgrade:

```bash
helm upgrade --install iax-demo ./charts/iax-otel-demo/ -f values-dev.yaml
```

**Package the chart** (produces a `.tgz` archive):

```bash
helm package ./charts/iax-otel-demo/
# Output: iax-otel-demo-0.1.0.tgz
```

**Publish to a Helm repository:**

```bash
# OCI registry (e.g. Nexus, Harbor, GitHub Container Registry)
helm push iax-otel-demo-0.1.0.tgz oci://docker.itrsgroup.com/helm-charts

# Install from the OCI registry
helm install iax-demo oci://docker.itrsgroup.com/helm-charts/iax-otel-demo \
  --version 0.1.0 \
  --set iax.otlpEndpoint=your-iax-host:443 \
  --set iax.ingestionUsername=your-username \
  --set iax.ingestionPassword=your-password
```

**Bump the chart version:**

Edit `charts/iax-otel-demo/Chart.yaml` — update `version` (chart version)
and `appVersion` (image tag) as needed.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Docker Compose / Kubernetes                                  │
│                                                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│  │ trader-  │ │ order-   │ │ execution│ │ order-   │        │
│  │ order-   │ │ routing  │ │ -venue-  │ │ staging  │  ...   │
│  │ entry    │ │          │ │ adapter  │ │          │        │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘        │
│       │             │            │             │              │
│       └─────────────┴────────────┴─────────────┘              │
│                          │                                    │
│                ┌─────────▼──────────┐                         │
│                │   OTel Collector   │                         │
│                │  (otelcol-contrib)  │                         │
│                └─────────┬──────────┘                         │
│                          │ OTLP/gRPC                          │
└──────────────────────────┼────────────────────────────────────┘
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


| Service                    | Language      | Telemetry             |
| -------------------------- | ------------- | --------------------- |
| trade-capture              | .NET          | Traces, Metrics       |
| market-news                | Java          | Traces, Metrics, Logs |
| order-staging              | .NET          | Traces, Metrics       |
| order-routing              | Go            | Traces, Metrics       |
| fx-rates                   | C++           | Traces, Metrics       |
| trade-notifications        | Ruby          | Traces, Metrics       |
| pre-trade-risk             | Java/Kotlin   | Traces, Metrics       |
| trader-order-entry         | Node.js       | Traces, Metrics       |
| fix-api-gateway            | Envoy         | Traces, Metrics       |
| trade-documents            | Nginx         | Metrics               |
| simulated-fix-order-flow   | Python/Locust | Traces, Metrics       |
| execution-venue-adapter    | Node.js       | Traces, Metrics       |
| instrument-reference-data  | Go            | Traces, Metrics, Logs |
| trade-audit                | Python        | Traces, Metrics, Logs |
| market-data-quotes         | PHP           | Traces, Metrics       |
| smart-order-recommendation | Python        | Traces, Metrics, Logs |
| settlement-instructions    | Rust          | Traces, Metrics       |


## What to Expect in IAX

Once the demo is running and the collector is exporting successfully, data
appears in IAX within 1–2 minutes:

- **Traces** — distributed traces spanning multiple services (e.g., a checkout
request touches `trader-order-entry` → `order-routing` → `execution-venue-adapter` → `settlement-instructions` → `trade-notifications`).
Filter by `service.namespace = iax-otel-demo` to isolate demo traffic.
- **Metrics** — application-level metrics (request counts, latencies, error
rates) plus infrastructure metrics (host, Docker stats, Kafka, PostgreSQL,
Valkey). Span metrics are auto-generated from traces.
- **Logs** — application logs from services that emit them (`market-news`,
`instrument-reference-data`, `trade-audit`, `smart-order-recommendation`).

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
If the collector logs show `x509: certificate signed by unknown authority`, set
`IAX_OTLP_INSECURE_SKIP_VERIFY=true` to skip certificate verification (e.g.,
for endpoints using self-signed certificates). Set `IAX_OTLP_INSECURE=true`
only if your IAX endpoint does not use TLS at all (e.g., a local dev instance).
Production endpoints should always use TLS with `IAX_OTLP_INSECURE=false`.

`**docker compose` not found:**
You need Docker Compose V2 (the `docker compose` plugin), not the standalone
`docker-compose` v1. Install it:

```bash
sudo apt install docker-compose-plugin   # Debian/Ubuntu with Docker's apt repo
```

Verify with `docker compose version` — it should report v2.x.x or later.

**Container name conflicts:**
If you see `The container name "/trader-order-entry" is already in use`, remove the
stale container first:

```bash
docker rm -f trader-order-entry
```

To remove all demo containers at once (Docker Compose):

```bash
docker compose -f docker-compose.iax.yml down --remove-orphans --volumes
```

**Clean up images:**

```bash
docker images --format "{{.Repository}}:{{.Tag}}" | grep "iax-otel-demo/" | xargs docker rmi
```

### Kubernetes / Helm

**Pods stuck in `ImagePullBackOff`:**
The cluster cannot pull images from Nexus. Create a pull secret and pass it
to the chart:

```bash
kubectl create secret docker-registry nexus-pull \
  --docker-server=docker.itrsgroup.com \
  --docker-username=your-user \
  --docker-password=your-pass

helm upgrade iax-demo ./charts/iax-otel-demo/ \
  --set 'global.imagePullSecrets[0].name=nexus-pull'
```

**Collector pod `CrashLoopBackOff`:**
Check the logs for IAX connectivity issues:

```bash
kubectl logs deploy/iax-demo-otel-collector --tail 30
```

Common causes: wrong `iax.otlpEndpoint`, missing credentials, or network
policy blocking egress. The same `Unauthenticated`, `connection refused`, and
TLS error patterns from the Docker section apply here.

**Disable a service:**
To disable a specific component (e.g., `simulated-fix-order-flow`):

```bash
helm upgrade iax-demo ./charts/iax-otel-demo/ \
  --set components.simulated-fix-order-flow.enabled=false
```

