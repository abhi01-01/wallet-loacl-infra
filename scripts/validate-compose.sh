#!/usr/bin/env sh
set -eu

docker compose config --quiet
docker compose --env-file .env.prod.example -f docker-compose.prod.yml config --quiet

if rg -n '^[[:space:]]+build:' docker-compose.prod.yml >/dev/null; then
  echo "docker-compose.prod.yml must not use local build contexts." >&2
  exit 1
fi

if rg -n '^[[:space:]]+container_name:' docker-compose.prod.yml >/dev/null; then
  echo "docker-compose.prod.yml must not pin container_name." >&2
  exit 1
fi

published_services="$(docker compose --env-file .env.prod.example -f docker-compose.prod.yml config | awk '
  /^  [a-z0-9-]+:$/ {
    service=$1
    sub(":", "", service)
  }
  /^    ports:$/ {
    print service
  }
' | sort -u)"

expected_published_services="$(printf '%s\n' api-gateway caddy grafana prometheus)"

if [ "$published_services" != "$expected_published_services" ]; then
  echo "Unexpected published-port services in docker-compose.prod.yml. Found: ${published_services:-none}" >&2
  exit 1
fi

for binding in \
  '      - "80:80"' \
  '      - "443:443"' \
  '      - "127.0.0.1:8082:8082"' \
  '      - "127.0.0.1:9090:9090"' \
  '      - "127.0.0.1:3000:3000"'
do
  if ! rg -n --fixed-strings "$binding" docker-compose.prod.yml >/dev/null; then
    echo "Missing required production port binding: $binding" >&2
    exit 1
  fi
done
