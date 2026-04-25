#!/usr/bin/env bash
# run.sh — Start the Fluent Bit → Elasticsearch → Kibana pipeline
# using plain docker run commands (no Docker Compose required).
#
# Usage:
#   bash run.sh          # start everything
#   bash run.sh stop     # stop and remove all containers + volume

set -e

NETWORK="log-net"
VOLUME="log-data"
ES_VERSION="8.11.0"
KIBANA_VERSION="8.11.0"
FB_VERSION="3.2"

# ── stop mode ────────────────────────────────────────────────────────────────
if [[ "$1" == "clear" ]]; then
  echo "----- Clearing containers -----"
  docker stop fluent-bit log-generator kibana elasticsearch 2>/dev/null || true
  docker rm   fluent-bit log-generator kibana elasticsearch 2>/dev/null || true
  docker volume rm "$VOLUME" 2>/dev/null || true
  echo "Done."
  exit 0
fi

# ── setup ────────────────────────────────────────────────────────────────────
echo "----- Creating network and volume -----"
docker network create "$NETWORK" 2>/dev/null || echo "(network already exists)"
docker volume  create "$VOLUME"  2>/dev/null || echo "(volume already exists)"

# ── 1. Elasticsearch ──────────────────────────────────────────────────────────
echo ""
echo "----- 1) Starting Elasticsearch -----"
docker run -d \
  --name elasticsearch \
  --network "$NETWORK" \
  -p 9200:9200 \
  -e discovery.type=single-node \
  -e xpack.security.enabled=false \
  -e ES_JAVA_OPTS="-Xms512m -Xmx512m" \
  docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}

echo "Waiting for Elasticsearch to be ready..."
until curl -s http://localhost:9200/_cluster/health | grep -q '"status"'; do
  sleep 3
  printf "."
done
echo ""
echo "Elasticsearch is up."

# ── 2. Kibana ────────────────────────────────────────────────────────────────
echo ""
echo "----- 2) Starting Kibana -----"
docker run -d \
  --name kibana \
  --network "$NETWORK" \
  -p 5601:5601 \
  -e ELASTICSEARCH_HOSTS=http://elasticsearch:9200 \
  docker.elastic.co/kibana/kibana:${KIBANA_VERSION}
echo "Kibana starting at http://localhost:5601 (takes ~30s)"

# ── 3. Log generator ─────────────────────────────────────────────────────────
echo ""
echo "----- 3) Starting log generator -----"
docker run -d \
  --name log-generator \
  --network "$NETWORK" \
  -v "$VOLUME":/logs \
  busybox \
  sh -c '
    while true; do
      TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      LEVEL="INFO"
      SERVICE="app"
      MSG="Request processed"
      LAT=$((RANDOM % 300 + 10))
      echo "{\"timestamp\": \"$TS\", \"level\": \"$LEVEL\", \"service\": \"$SERVICE\", \"message\": \"$MSG\", \"latency_ms\": $LAT}" >> /logs/app.log
      TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      echo "{\"timestamp\": \"$TS\", \"level\": \"WARN\", \"service\": \"db\", \"message\": \"Slow query detected\", \"latency_ms\": $((RANDOM % 2000 + 500))}" >> /logs/app.log
      sleep 2
    done
  '
echo "Log generator is writing to the volume every 2s."

# ── 4. Fluent Bit ────────────────────────────────────────────────────────────
echo ""
echo "---------------------------------------"
echo "----- 4) Starting Fluent Bit -----"
echo "---------------------------------------"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker run -d \
  --name fluent-bit \
  --network "$NETWORK" \
  -v "$VOLUME":/logs:ro \
  -v "$SCRIPT_DIR/fluent-bit.conf":/fluent-bit/etc/fluent-bit.conf:ro \
  -v "$SCRIPT_DIR/parsers.conf":/fluent-bit/etc/parsers.conf:ro \
  fluent/fluent-bit:${FB_VERSION}

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo ""
echo "============================================="
echo " Pipeline is running"
echo "============================================="
echo " Elasticsearch : http://localhost:9200"
echo " Kibana        : http://localhost:5601"
echo ""
echo " Verify logs   : python verify_logs.py"
echo " Live FB logs  : docker logs -f fluent-bit"
echo " Stop all      : bash run.sh clear"
echo "============================================="
echo ""
echo ""
