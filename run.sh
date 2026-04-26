#!/usr/bin/env bash
set -euo pipefail

NETWORK="log-net"
VOLUME="log-data"

ES_VERSION="8.11.0"
KIBANA_VERSION="8.11.0"
FB_VERSION="3.2"

# -----------------------------
# helpers
# -----------------------------

log() {
  echo -e "\n==> $1"
}

wait_for() {
  local url=$1
  local name=$2
  local timeout=${3:-60}

  log "Waiting for $name..."

  for i in $(seq 1 $timeout); do
    if curl -s "$url" >/dev/null 2>&1; then
      echo "    $name is ready."
      return 0
    fi
    sleep 2
    printf "."
  done

  echo ""
  echo "ERROR: $name failed to start within ${timeout}s"
  exit 1
}

cleanup_containers() {
  docker update --restart=no elasticsearch kibana fluent-bit log-generator log-generator-stdout 2>/dev/null || true
  docker rm -f elasticsearch kibana fluent-bit log-generator log-generator-stdout 2>/dev/null || true
}

ensure_infra() {
  docker network create "$NETWORK" 2>/dev/null || true
  docker volume create "$VOLUME" 2>/dev/null || true
}

# -----------------------------
# START PIPELINE
# -----------------------------
start() {
  log "Starting pipeline (clean state)..."

  ensure_infra
  cleanup_containers

  # ---------------- ES ----------------
  log "Starting Elasticsearch"
  docker run -d \
    --name elasticsearch \
    --network "$NETWORK" \
    -p 9200:9200 \
    -e discovery.type=single-node \
    -e xpack.security.enabled=false \
    -e ES_JAVA_OPTS="-Xms512m -Xmx512m" \
    --restart unless-stopped \
    docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}

  wait_for "http://localhost:9200/_cluster/health" "Elasticsearch" 40

  # ---------------- KIBANA ----------------
  log "Starting Kibana"
  docker run -d \
    --name kibana \
    --network "$NETWORK" \
    -p 5601:5601 \
    -e ELASTICSEARCH_HOSTS=http://elasticsearch:9200 \
    --restart unless-stopped \
    docker.elastic.co/kibana/kibana:${KIBANA_VERSION}

  wait_for "http://localhost:5601/api/status" "Kibana" 60

    # ---------------- FLUENT BIT ----------------
  log "Starting Fluent Bit"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  docker run -d \
    --name fluent-bit \
    --network "$NETWORK" \
    --user root \
    --privileged \
    -p 24224:24224 \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    -v "$VOLUME":/logs:ro \
    -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
    -v "$SCRIPT_DIR/fluent-bit.conf":/fluent-bit/etc/fluent-bit.conf:ro \
    -v "$SCRIPT_DIR/parsers.conf":/fluent-bit/etc/parsers.conf:ro \
    --restart unless-stopped \
    fluent/fluent-bit:${FB_VERSION}

  log "Pipeline started successfully"

  # ---------------- LOG GENERATOR ----------------
  log "Starting log generator"
  docker run -d \
    --name log-generator \
    --network "$NETWORK" \
    -v "$VOLUME":/logs \
    --restart unless-stopped \
    busybox \
    sh -c '
      while true; do
        TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        LEVEL=$((RANDOM % 3))

        if [ $LEVEL -eq 0 ]; then
          echo "{\"timestamp\":\"$TS\",\"level\":\"INFO\",\"service\":\"app\",\"message\":\"OK\",\"latency_ms\":$((RANDOM % 300 + 10))}" >> /logs/app.log
        elif [ $LEVEL -eq 1 ]; then
          echo "{\"timestamp\":\"$TS\",\"level\":\"WARN\",\"service\":\"db\",\"message\":\"Slow query\",\"latency_ms\":$((RANDOM % 2000 + 500))}" >> /logs/app.log
        else
          echo "{\"timestamp\":\"$TS\",\"level\":\"ERROR\",\"service\":\"api\",\"message\":\"Failure\",\"latency_ms\":$((RANDOM % 5000 + 1000))}" >> /logs/app.log
        fi

        sleep 1
      done
    '

  # ---------------- LOG GENERATOR (DOCKER)----------------
  log "Starting docker log generator"
  docker run -d \
    --name log-generator-stdout \
    --log-driver=fluentd \
    --log-opt fluentd-address=localhost:24224 \
    --network "$NETWORK" \
    --restart unless-stopped \
    busybox \
    sh -c '
      i=0
      while true; do
        LEVEL=$((RANDOM % 3))

        if [ $LEVEL -eq 0 ]; then
          echo "{\"service\":\"app\",\"level\":\"INFO\",\"message\":\"stdout OK $i\",\"latency_ms\":$((RANDOM % 300))}"
        elif [ $LEVEL -eq 1 ]; then
          echo "{\"service\":\"db\",\"level\":\"WARN\",\"message\":\"slow stdout query\",\"latency_ms\":$((RANDOM % 2000))}"
        else
          echo "{\"service\":\"api\",\"level\":\"ERROR\",\"message\":\"stdout failure\",\"latency_ms\":$((RANDOM % 5000))}"
        fi

        i=$((i+1))
        sleep 1
      done
    '
}

# -----------------------------
# STOP
# -----------------------------
stop() {
  log "Stopping pipeline..."
  docker stop elasticsearch kibana fluent-bit log-generator log-generator-stdout 2>/dev/null || true
}

# -----------------------------
# RESET (FULL CLEAN)
# -----------------------------
reset() {
  log "Resetting system..."
  cleanup_containers
  docker volume rm "$VOLUME" 2>/dev/null || true
  docker network rm "$NETWORK" 2>/dev/null || true
  echo "Done."
}

# -----------------------------
# LOGS
# -----------------------------
logs() {
  docker logs -f fluent-bit
}

# -----------------------------
# STATUS
# -----------------------------
status() {
  echo "Containers:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# -----------------------------
# CLI ROUTER
# -----------------------------
case "${1:-}" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  reset)
    reset
    ;;
  logs)
    logs
    ;;
  status)
    status
    ;;
  *)
    echo "Usage:"
    echo "  ./run.sh start   - start pipeline"
    echo "  ./run.sh stop    - stop containers"
    echo "  ./run.sh reset   - full cleanup"
    echo "  ./run.sh logs    - fluent-bit logs"
    echo "  ./run.sh status  - show containers"
    exit 1
    ;;
esac
