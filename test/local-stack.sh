#!/bin/bash
# local-stack.sh: run the image the way Cloudron does, with stand-ins for its addons.
#   test/local-stack.sh up [IMAGE]   PostgreSQL 18 + password-protected Redis + the app, in one pod
#   test/local-stack.sh down         remove the pod; KEEP=1 keeps the data directory
#   test/local-stack.sh logs         follow the app's log
# The app container gets what a Cloudron app container gets: a read-only root filesystem, /app/data
# as a volume, writable /run and /tmp, and the addon variables. The app is on http://127.0.0.1:8100.
# No LDAP or mail stand-in: owned-config.py then turns LDAP off and leaves mail alone.
set -euo pipefail
POD=da-local
IMAGE="${2:-localhost/docassemble-cloudron:dev}"
DATA="${DATA:-$(dirname "$0")/../tmp/local-data}"
PGPASS=localpg-not-a-secret
REDISPASS=localredis-not-a-secret
# Local only: create_tables gives the first admin this API key, which test/proofs.sh uses.
APIKEY="${KEY:-localtestapikeylocaltestapikey00}"

case "${1:-}" in
up)
    mkdir -p "${DATA}"
    podman pod create --name "${POD}" -p 127.0.0.1:8100:8000 >/dev/null
    podman run -d --pod "${POD}" --name "${POD}-pg" -e POSTGRES_USER=app -e POSTGRES_PASSWORD="${PGPASS}" \
        -e POSTGRES_DB=app docker.io/library/postgres:18.4 >/dev/null
    podman run -d --pod "${POD}" --name "${POD}-redis" docker.io/library/redis:8-alpine \
        redis-server --requirepass "${REDISPASS}" >/dev/null
    for _ in $(seq 1 60); do podman exec "${POD}-pg" pg_isready -U app -q && break; sleep 1; done
    podman run -d --pod "${POD}" --name "${POD}-app" --read-only \
        --tmpfs /run:rw,exec,mode=755 --tmpfs /tmp:rw,exec,mode=1777 \
        -v "$(realpath "${DATA}")":/app/data:Z \
        -e CLOUDRON_APP_DOMAIN=docassemble.example.com -e CLOUDRON_APP_ORIGIN=https://docassemble.example.com \
        -e CLOUDRON_POSTGRESQL_HOST=127.0.0.1 -e CLOUDRON_POSTGRESQL_PORT=5432 \
        -e CLOUDRON_POSTGRESQL_DATABASE=app -e CLOUDRON_POSTGRESQL_USERNAME=app \
        -e CLOUDRON_POSTGRESQL_PASSWORD="${PGPASS}" \
        -e CLOUDRON_REDIS_HOST=127.0.0.1 -e CLOUDRON_REDIS_PORT=6379 -e CLOUDRON_REDIS_PASSWORD="${REDISPASS}" \
        -e CLOUDRON_REDIS_URL="redis://default:${REDISPASS}@127.0.0.1:6379" \
        -e DA_ADMIN_API_KEY="${APIKEY}" \
        "${IMAGE}" >/dev/null
    echo "up: app on http://127.0.0.1:8100 (health: /healthz); data in ${DATA}"
    ;;
down)
    podman pod rm -f "${POD}" >/dev/null 2>&1 || true
    if [ "${KEEP:-0}" != 1 ]; then podman unshare rm -rf "${DATA}"; fi
    echo "down"
    ;;
logs) podman logs -f "${POD}-app" ;;
*) echo "usage: $0 up [IMAGE] | down | logs" >&2; exit 2 ;;
esac
