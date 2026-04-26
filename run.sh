#!/usr/bin/env bash
# run.sh — Start the Fluent Bit dual-input pipeline
#   INPUT 1: tail /logs/app.log  (file-based, via Docker volume)
#   INPUT 2: Docker socket       (reads ALL container logs automatically)

# Usage:
# bash run.sh
# start everything
# bash run.sh clear
# stop and remove all containers + volume

set -e

NETWORK="log-net"
VOLUME="log-data"
ES_VERSION="8.11.0"
KIBANA_VERSION="8.11.0"
FB_VERSION="3.2"

# clear mode
if [[ "$1" == "clear" ]]; then
  echo "==> Stopping containers..."
  docker stop fluent-bit log-generator kibana elasticsearch 2>/dev/null || true
  docker rm   fluent-bit log-generator kibana elasticsearch 2>/dev/null || true
  docker volume rm "$VOLUME" 2>/dev/null || true
  echo "Done."
  exit 0
fi

# setup
echo "==> Creating network and volume..."
docker network create "$NETWORK" 2>/dev/null || echo "    (network already exists)"
docker volume  create "$VOLUME"  2>/dev/null || echo "    (volume already exists)"

# 1. Elasticsearch
echo ""
echo "==> [1/4] Starting Elasticsearch..."
docker run -d \
  --name elasticsearch \
  --network "$NETWORK" \
  -p 9200:9200 \
  -e discovery.type=single-node \
  -e xpack.security.enabled=false \
  -e ES_JAVA_OPTS="-Xms512m -Xmx512m" \
  docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}

echo "    Waiting for Elasticsearch to be ready..."
until curl -s http://localhost:9200/_cluster/health | grep -q '"status"'; do
  sleep 3
  printf "."
done
echo ""
echo "    Elasticsearch is up."

# 2. Kibana
echo ""
echo "==> [2/4] Starting Kibana..."
docker run -d \
  --name kibana \
  --network "$NETWORK" \
  -p 5601:5601 \
  -e ELASTICSEARCH_HOSTS=http://elasticsearch:9200 \
  docker.elastic.co/kibana/kibana:${KIBANA_VERSION}
echo "    Kibana starting at http://localhost:5601 (takes ~30s)"

# 3. Log generator
echo ""
echo "==> [3/4] Starting log generator..."
docker run -d \
  --name log-generator \
  --network "$NETWORK" \
  -v "$VOLUME":/logs \
  busybox \
  sh -c '
    while true; do
      TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      echo "{\"timestamp\": \"$TS\", \"level\": \"INFO\", \"service\": \"app\", \"message\": \"Request processed\", \"latency_ms\": $((RANDOM % 300 + 10))}" >> /logs/app.log
      echo "{\"timestamp\": \"$TS\", \"level\": \"WARN\", \"service\": \"db\", \"message\": \"Slow query detected\", \"latency_ms\": $((RANDOM % 2000 + 500))}" >> /logs/app.log
      sleep 2
    done
  '
echo "    Log generator writing JSON logs every 2s."

# 4. Fluent Bit
# Key flags:
# -v /var/run/docker.sock
# gives Fluent Bit access to the Docker daemon so the [docker] input reads ALL container logs
# -v log-data:/logs:ro
# file tail input reads app.log from shared volume
# --user root
# required to read the Docker socket
echo ""
echo "==> [4/4] Starting Fluent Bit..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker run -d \
  --name fluent-bit \
  --network "$NETWORK" \
  --user root \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$VOLUME":/logs:ro \
  -v "$SCRIPT_DIR/fluent-bit.conf":/fluent-bit/etc/fluent-bit.conf:ro \
  -v "$SCRIPT_DIR/parsers.conf":/fluent-bit/etc/parsers.conf:ro \
  fluent/fluent-bit:${FB_VERSION}

# TODO: Python verify_logs using docker

# final 
echo ""
echo "============================================="
echo " Pipeline is running!"
echo "============================================="
echo ""
echo " INPUT 1 (file tail) → ES index: fluent-bit-app"
echo " INPUT 2 (docker socket) → ES index: fluent-bit-docker"
echo ""
echo " Elasticsearch : http://localhost:9200"
echo " Kibana        : http://localhost:5601"
echo ""
echo " Verify logs   : python verify_logs.py"
echo " Live FB logs  : docker logs -f fluent-bit"
echo " Stop all      : bash run.sh clear"
echo "============================================="
