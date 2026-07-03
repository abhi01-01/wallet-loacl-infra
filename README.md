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

If your local folder names are different, update the `build.context` paths in `docker-compose.yml`.

## Local Network Model

Inside Docker, services talk to each other using Compose service names:

```text
api-gateway    -> wallet-service:8081
wallet-service -> postgres:5432
wallet-service -> redis:6379
wallet-service -> kafka:9092
```

From your browser or host machine, use exposed localhost ports:

```text
Gateway API           http://localhost:8080
Gateway Swagger       http://localhost:8080/swagger-ui.html
Gateway Actuator      http://localhost:8082/actuator/health
Kafka from host       localhost:29092
Grafana               http://localhost:3000
Wallet Web            http://localhost:3000 or http://localhost:3001 depending on your setup
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

Run `wallet-web` inside Docker, and expose it on port `3001:3001`.

## Important Ports

| Component              | Container Port |                 Host Port | Usage                              |
|------------------------|---------------:|--------------------------:|------------------------------------|
| api-gateway            |           8080 |                      8080 | Public API entrypoint              |
| api-gateway management |           8082 |                      8082 | Actuator/management, if configured |
| wallet-service         |           8081 |               not exposed | Internal service behind gateway    |
| postgres               |           5432 |                      5432 | Local DB access                    |
| redis                  |           6379 |                      6379 | Local Redis access                 |
| kafka internal         |           9092 | not used directly by host | Container-to-container Kafka       |
| kafka host listener    |          29092 |                     29092 | Host-to-Kafka CLI/debugging        |
| grafana                |           3000 |                      3000 | Observability UI                   |
| wallet-web             |           3001 |                      3001 | Frontend app                       |

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

If management port is not configured separately, actuator may be available at:

```text
http://localhost:8080/actuator/health
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

## End-to-End Verification

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


### Swagger opens but APIs return 401/403

Routing is working. Your token/security is the issue.

Admin messaging APIs require SYSTEM role unless changed in wallet-service security config.

Use a valid SYSTEM token.

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

Do not copy local `.env` values to production.

Do not expose internal service ports publicly in production unless there is a specific reason.

The production public entrypoint should be the API gateway.

## Ownership Rules

Keep responsibilities clean:

```text
wallet-service repo      -> wallet backend source code, Dockerfile, service README
api-gateway repo         -> gateway source code, Dockerfile, gateway README
wallet-web repo          -> frontend source code, frontend README
wallet-local-infra repo  -> local docker-compose orchestration and observability config
```

Do not let service repos own the full local platform compose file.

Do not let the infra repo own service source code.

This separation keeps local development reproducible without turning the project into a monorepo.
