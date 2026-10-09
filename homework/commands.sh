#!/usr/bin/env sh

set -eu

NETWORK_NAME="app-net"
VOLUME_NAME="db-data"
DB_CONTAINER="db-server"
APP_CONTAINER="app-container"
DB_IMAGE="postgres:15-alpine"
APP_IMAGE="python:3.12-alpine"
DB_NAME="appdb"
DB_USER="appuser"
DB_PASSWORD="app-password"
PERSISTENCE_MARKER="persistence-$(date +%s)-$$"

create_resources() {
  if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    docker network create --driver bridge "$NETWORK_NAME"
  fi

  if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    docker volume create "$VOLUME_NAME"
  fi
}

remove_container_if_present() {
  container_name="$1"
  if docker container inspect "$container_name" >/dev/null 2>&1; then
    docker rm -f "$container_name" >/dev/null
  fi
}

start_database() {
  docker run -d \
    --name "$DB_CONTAINER" \
    --network "$NETWORK_NAME" \
    -e POSTGRES_DB="$DB_NAME" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -v "$VOLUME_NAME:/var/lib/postgresql/data" \
    "$DB_IMAGE" >/dev/null
}

wait_for_database() {
  attempts=0
  max_attempts=30

  until docker exec "$DB_CONTAINER" \
    pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
      echo "PostgreSQL did not become ready in time." >&2
      docker logs "$DB_CONTAINER" >&2
      exit 1
    fi
    sleep 2
  done
}

echo "==> Creating custom network and named volume"
create_resources

# Remove old containers so the script can be run again without deleting db-data.
remove_container_if_present "$APP_CONTAINER"
remove_container_if_present "$DB_CONTAINER"

echo "==> Starting PostgreSQL"
start_database
wait_for_database

echo "==> Starting backend container"
docker run -d \
  --name "$APP_CONTAINER" \
  --network "$NETWORK_NAME" \
  -e DB_HOST="$DB_CONTAINER" \
  -e DB_PORT="5432" \
  -e DB_NAME="$DB_NAME" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@$DB_CONTAINER:5432/$DB_NAME" \
  "$APP_IMAGE" \
  python -m http.server 8080 >/dev/null

echo "==> Checking Docker DNS from the backend"
docker exec "$APP_CONTAINER" ping -c 2 "$DB_CONTAINER"

echo "==> Inserting persistence test data: $PERSISTENCE_MARKER"
docker exec "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" \
  -c "CREATE TABLE IF NOT EXISTS persistence_test (marker TEXT PRIMARY KEY, created_at TIMESTAMPTZ DEFAULT NOW());" \
  -c "INSERT INTO persistence_test (marker) VALUES ('$PERSISTENCE_MARKER');" >/dev/null

echo "==> Removing and recreating the database container"
docker rm -f "$DB_CONTAINER" >/dev/null
start_database
wait_for_database

echo "==> Verifying data from the reused named volume"
saved_marker="$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc \
  "SELECT marker FROM persistence_test WHERE marker = '$PERSISTENCE_MARKER';")"

if [ "$saved_marker" != "$PERSISTENCE_MARKER" ]; then
  echo "Persistence test failed: saved data was not found." >&2
  exit 1
fi

echo "Persistence test passed: $saved_marker"

echo "==> Final resource checks"
docker network ls | grep "$NETWORK_NAME"
docker volume ls | grep "$VOLUME_NAME"
docker network inspect "$NETWORK_NAME"
docker exec "$APP_CONTAINER" ping -c 2 "$DB_CONTAINER"

echo "Done. Both containers are left running for manual inspection."