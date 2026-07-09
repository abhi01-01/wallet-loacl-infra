# Wallet Local Infra

`wallet-local-infra` is the local orchestration repository for the Wallet Platform.

It does not own the business code for `wallet-service`, `api-gateway`, or `wallet-web`. Those services live in separate repositories. This repository exists to run the whole platform together on a local machine using Docker Compose.

The main purpose of this repo is simple:

```text
Build each service from its own repository
Run shared infrastructure locally
Wire services together using Docker networking
Give developers one command to test the full platform
```

## Platform Components

The local platform consists of:

```text
wallet-service        Java Spring Boot backend for wallets, ledger, payments, Kafka outbox, and audit APIs
api-gateway           Spring Cloud Gateway edge service for routing, authentication, rate limiting, and Swagger aggregation
wallet-web            Next.js frontend dashboard; usually run separately during development
postgres              Local PostgreSQL database for wallet-service
redis                 Local Redis instance for gateway rate limiting and service features
kafka                 Local Kafka broker for wallet transaction events
prometheus            Metrics scraping
tracing / tempo       Distributed tracing backend
Grafana               Dashboards for metrics and traces
```

## Why This Repo Exists

The platform is intentionally multi-repo:

```text
wallet-service      -> owns wallet backend code and Dockerfile
api-gateway         -> owns gateway code and Dockerfile
wallet-web          -> owns frontend code and Dockerfile/package setup
wallet-local-infra  -> owns local orchestration only
```
## Expected Directory Layout

Clone all related repositories as siblings under one parent directory.

Recommended layout:

```text
wallet-platform/
  wallet-service/
  api-gateway/
  wallet-web/
  wallet-local-infra/
    docker-compose.yml
    prometheus.yml
    tempo.yml
    grafana/
    README.md
    .env.example
```

From this repo, Docker Compose can build sibling services using paths like:

```yaml
wallet-service:
  build:
    context: ../wallet-service
    dockerfile: Dockerfile

api-gateway:
  build:
    context: ../api-gateway
    dockerfile: Dockerfile
```

## Local Network Model

Inside Docker, services talk to each other using Compose service names:

```text
Gateway API           http://localhost:8080
Gateway Swagger       http://localhost:8080/swagger-ui.html
Gateway Actuator      http://localhost:8082/actuator/health
Wallet Service        http://localhost:8081
Kafka from host       localhost:29092
Prometheus            http://localhost:9090
Tempo                 http://localhost:3200
Grafana               http://localhost:3000
Wallet Web            http://localhost:3001
```

Important:

```text
Inside Docker, use service names like kafka:9092 and wallet-service:8081.
From your host machine, use localhost ports like localhost:8080 and localhost:29092.
```

Do not configure `wallet-service` inside Docker to use `localhost:9092` for Kafka. Inside a container, `localhost` means the same container, not your laptop and not the Kafka container.

## Prerequisites

Install:

```text
Docker Desktop or Docker Engine
Docker Compose v2
Git
Java 21, only needed if running services manually outside Docker
Node.js, only needed if running wallet-web manually outside Docker
```

Verify Docker Compose:

```bash
docker compose version
```

## Environment Setup

Create a local `.env` file from the example file:

```bash
cp .env.example .env
```

The `.env` file should contain local-only secrets and configuration values. Keep production secrets in your cloud provider or deployment platform, not in this repo.

Typical local variables:

```env
POSTGRES_DB=wallet_db
POSTGRES_USER=wallet_user
POSTGRES_PASSWORD=wallet_password

JWT_SECRET=replace-with-local-dev-secret
GATEWAY_INTERNAL_SECRET=replace-with-local-gateway-secret

WALLET_SERVICE_URL=http://wallet-service:8081
KAFKA_BOOTSTRAP_SERVERS=kafka:9092

WALLET_KAFKA_ENABLED=true
WALLET_OUTBOX_PUBLISHER_ENABLED=true
WALLET_KAFKA_AUDIT_CONSUMER_ENABLED=true
WALLET_KAFKA_CONSUMER_GROUP_ID=wallet-service-audit-consumer-docker
```

## Running the Full Backend Platform

From this repo:

```bash
docker compose up --build
```

For a cleaner staged startup:

```bash
docker compose up -d postgres redis kafka
```

Check health:

```bash
docker compose ps
```

Then start application services:

```bash
docker compose up --build wallet-service api-gateway
```

To start the backend request path with its required dependencies in one command:

```bash
docker compose up --build postgres redis kafka wallet-service api-gateway
```

To start the full platform including frontend and observability:

```bash
docker compose up --build
```

### To run wallet-service locally from IntelliJ or Maven while keeping infra and gateway in Docker:

```bash
docker compose up -d postgres redis kafka
WALLET_SERVICE_URL=http://host.docker.internal:8081 docker compose up --no-deps api-gateway
```

Use `host.docker.internal` because `api-gateway` is inside Docker and `localhost` from inside that container points to the gateway container itself, not your laptop.

To run everything in detached mode:

```bash
docker compose up --build -d
```

To stop everything:

```bash
docker compose down
```

To remove local volumes and reset PostgreSQL/Kafka/Redis data:

```bash
docker compose down -v
```

Use `down -v` carefully. It deletes local database and Kafka data.

## Running Wallet Web

`wallet-web` is a separate Next.js repository. During development, it is usually better to run it directly on the host machine instead of inside Docker.

From the `wallet-web` repo:

```bash
npm install
npm run dev
```

Set frontend env:

```env
NEXT_PUBLIC_API_BASE_URL=http://localhost:8080
```

The frontend should call the gateway, not wallet-service directly.

Correct:

```text
wallet-web -> http://localhost:8080 -> api-gateway -> wallet-service
```

Wrong:

```text
wallet-web -> http://localhost:8081
```
wallet service is designed to prevent direct access.

Run Next.js on port `3001`:

```bash
npm run dev -- -p 3001
```

Then open:

```text
http://localhost:3001
```

Run `wallet-web` inside Docker, and expose host port `3001` to container port `3000`.

Current compose already enables `wallet-web`:

```yaml
wallet-web:
  ports:
    - "3001:3000"
  environment:
    NEXT_PUBLIC_API_BASE_URL: ${NEXT_PUBLIC_API_BASE_URL:-http://localhost:8080}
```

## Important Ports

| Component              | Container Port |                 Host Port | Usage                              |
|------------------------|---------------:|--------------------------:|------------------------------------|
| api-gateway            |           8080 |                      8080 | Public API entrypoint              |
| api-gateway management |           8082 |                      8082 | Actuator/management, if configured |
| wallet-service         |           8081 |                      8081 | Internal service behind gateway; exposed locally for debugging |
| postgres               |           5432 |                      5432 | Local DB access                    |
| redis                  |           6379 |                      6379 | Local Redis access                 |
| kafka internal         |           9092 | not used directly by host | Container-to-container Kafka       |
| kafka host listener    |          29092 |                     29092 | Host-to-Kafka CLI/debugging        |
| grafana                |           3000 |                      3000 | Observability UI                   |
| wallet-web             |           3001 |                      3001 | Frontend app                       |

Current compose exposes `wallet-service` on host port `8081`:

```yaml
wallet-service:
  ports:
    - "8081:8081"
```

It is still intended to be accessed through `api-gateway` for normal application traffic. The direct host port is useful for local debugging, health checks, and service-level troubleshooting.

Current compose also exposes:

| Component  | Container Port | Host Port | Usage                     |
|------------|---------------:|----------:|---------------------------|
| prometheus |           9090 |      9090 | Metrics backend           |
| tempo      |           3200 |      3200 | Tempo API                 |
| tempo      |           4317 |      4317 | OTLP gRPC ingest          |
| tempo      |           4318 |      4318 | OTLP HTTP ingest          |

## Gateway Access

Use the gateway as the only backend entrypoint from browser, Postman, curl, or frontend:

```text
http://localhost:8080
```

Swagger UI:

```text
http://localhost:8080/swagger-ui.html
```

Wallet-service OpenAPI through gateway:

```text
http://localhost:8080/wallet-service/v3/api-docs
```

Gateway health:

```text
http://localhost:8082/actuator/health
```

When wallet-service runs locally outside Docker, override this value with:

```bash
WALLET_SERVICE_URL=http://host.docker.internal:8081 docker compose up --no-deps api-gateway
```

## Kafka Local Usage

Inside Docker, wallet-service uses:

```text
kafka:9092
```

From host machine, use:

```text
localhost:29092
```

List topics:

```bash
docker exec -it wallet-kafka-d /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:29092 \
  --list
```

Describe wallet transaction topic:

```bash
docker exec -it wallet-kafka-d /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:29092 \
  --describe \
  --topic wallet.transaction.events.v1
```

Consume wallet transaction events:

```bash
docker exec -it wallet-kafka-d /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:29092 \
  --topic wallet.transaction.events.v1 \
  --from-beginning \
  --property print.key=true \
  --property print.headers=true \
  --property key.separator=" | "
```

Expected Kafka value should be raw JSON, not escaped JSON:

```json
{"this": "is wrong if the whole value is quoted and escaped"}
```

Correct shape:

```json
{
  "eventId": "...",
  "eventType": "wallet.transaction.posted.v1",
  "schemaVersion": 1,
  "source": "wallet-service",
  "aggregateType": "TRANSACTION",
  "aggregateId": "...",
  "data": {
    "transactionType": "BONUS",
    "entries": [
      { "entryType": "DEBIT" },
      { "entryType": "CREDIT" }
    ]
  }
}
```

## End-to-End Verification for Kafka

After starting the platform:

1. Open gateway Swagger:

```text
http://localhost:8080/swagger-ui.html
```

2. Create or use a SYSTEM token.

3. Call a wallet operation that creates a transaction, such as bonus/top-up/spend.

4. Verify outbox status through gateway:

```bash
curl -H "Authorization: Bearer <SYSTEM_TOKEN>" \
  "http://localhost:8080/api/v1/admin/messaging/outbox-events?page=0&size=10"
```

Expected:

```text
status = PUBLISHED
```

5. Verify Kafka audit:

```bash
curl -H "Authorization: Bearer <SYSTEM_TOKEN>" \
  "http://localhost:8080/api/v1/admin/messaging/kafka-audit-events?page=0&size=10"
```

Expected:

```text
A consumed audit row exists for wallet.transaction.posted.v1
```

6. Verify summary:

```bash
curl -H "Authorization: Bearer <SYSTEM_TOKEN>" \
  "http://localhost:8080/api/v1/admin/messaging/summary"
```

Expected:

```text
outbox.PUBLISHED count increases
kafkaAudit.totalConsumed increases
```

## Observability

Grafana:

```text
http://localhost:3000
```

Prometheus config is owned by this repo through `prometheus.yml`.

Tempo config is owned by this repo through `tempo.yml`.

Current compose mounts these files from subdirectories:

```text
./prometheus/prometheus.yml -> /etc/prometheus/prometheus.yml
./tempo/tempo.yaml          -> /etc/tempo.yaml
./grafana/grafana.yml       -> /etc/grafana/provisioning/datasources/datasources.yml
```

Prometheus:

```text
http://localhost:9090
```

Tempo:

```text
http://localhost:3200
```


## Swagger opens but APIs return 401/403

Routing is working. Your token/security is the issue. Use a valid SYSTEM token.

Admin messaging APIs require `SYSTEM` role unless changed in wallet-service security config.


## Production Compose

This repository now has a separate production-style Compose file:

```text
docker-compose.prod.yml
.env.prod.example
Caddyfile
prometheus/prometheus.prod.yml
tempo/tempo.prod.yaml
grafana/grafana.yml
```

The production Compose file is intentionally different from the local development file:

```text
local docker-compose.yml      -> builds sibling repos and runs local Postgres/Redis/Kafka
docker-compose.prod.yml       -> uses prebuilt registry images and managed backing services
```

Create a production env file from the example:

```bash
cp .env.prod.example .env.prod
```

Edit `.env.prod` with real production values from your secret manager or deployment platform. Do not commit `.env.prod`.

Validate production Compose rendering:

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml config --quiet
```

Validate both local and production Compose definitions for CI:

```bash
sh scripts/validate-compose.sh
```

Start the production-style stack:

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d
```

Stop it:

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml down
```

Production Compose expects these services to be managed outside this repo:

```text
PostgreSQL
Redis
Kafka
container image registry
secret management
DNS for WEB_DOMAIN and API_DOMAIN
```

Public ingress is only through Caddy:

```text
HTTP  -> 0.0.0.0:80
HTTPS -> 0.0.0.0:443
```

Admin surfaces are loopback-only on the Docker host:

```text
API gateway management -> 127.0.0.1:8082
Prometheus             -> 127.0.0.1:9090
Grafana                -> 127.0.0.1:3000
```

These bindings are not public internet exposure. They are only reachable from the Docker host itself, or through an explicit SSH/VPN tunnel.

Caddy routes production traffic by hostname:

```text
WEB_DOMAIN     -> wallet-web:3000
API_DOMAIN     -> api-gateway:8080
```

Grafana datasource provisioning is configured in:

```text
grafana/grafana.yml
```

It creates:

```text
Prometheus -> http://prometheus:9090
Tempo      -> http://tempo:3200
```

Production hardening included in `docker-compose.prod.yml`:

```text
prebuilt versioned images instead of local build contexts
prod Spring profiles
no local Postgres/Redis/Kafka containers
managed Redis and Kafka TLS/auth env wiring
Kafka client-side auto topic creation disabled
no public wallet-service port
no public Prometheus or Tempo ports
no public wallet-web or wallet-service container ports
public ingress only through Caddy
loopback-only admin access for api-gateway management, Prometheus, and Grafana
Grafana anonymous admin disabled
memory limits through Compose deploy resources
log rotation
no-new-privileges
capability drops
no container_name pinning in production
private service-to-service networking without host-published ports
health checks for Caddy, wallet-web, api-gateway, wallet-service, Prometheus, Tempo, and Grafana
persistent Prometheus, Tempo, and Grafana volumes
production Prometheus targets using service DNS instead of host.docker.internal
Grafana datasource provisioning for Prometheus and Tempo
```

The production Compose file is suitable as a hardened Compose baseline. For high-availability production, prefer a real orchestrator and managed backing services.

## Production Note

This repo is for local orchestration, not production infrastructure.

Production should use:

```text
managed PostgreSQL
managed Redis
managed Kafka or cloud Kafka provider
cloud deployment platform environment variables
cloud Prometheus/Grafana/Tempo or equivalent observability stack
secure secret management
```

## Don'ts

* Do not copy local `.env` values to production.
* Do not expose internal service ports publicly in production unless there is a specific reason.
* The only public network entrypoint should be Caddy; API traffic should still terminate at the API gateway behind it.
* Do not let service repos own the full local platform compose file.
* Do not let the infra repo own service source code.
* This separation keeps local development reproducible without turning the project into a monorepo.

## Grafana Config Split

`grafana/grafana.ini` is used only by the local development Compose file for convenience.

`docker-compose.prod.yml` does not mount `grafana/grafana.ini`; it uses explicit production-safe Grafana environment settings plus datasource provisioning from `grafana/grafana.yml`.

## Ownership Rules

Keep responsibilities clean:

```text
wallet-service repo      -> wallet backend source code, Dockerfile, service README
api-gateway repo         -> gateway source code, Dockerfile, gateway README
wallet-web repo          -> frontend source code, frontend README
wallet-local-infra repo  -> local docker-compose orchestration and observability config
```
