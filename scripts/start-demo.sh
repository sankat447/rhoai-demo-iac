#!/bin/bash
# start-demo.sh — Scale workers up for an active demo session
# Usage: aws-vault exec rhoai-demo -- ./scripts/start-demo.sh
set -euo pipefail
CLUSTER="${ROSA_CLUSTER:-rhoai-demo}"
log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "▶️  Starting demo — scaling workers to 2..."
rosa edit machinepool workers --cluster="${CLUSTER}" --replicas=2
log "⏳ Waiting for nodes to be Ready (~8 min)..."
until oc get nodes --no-headers 2>/dev/null | grep -c " Ready" | grep -q "^[2-9]"; do
  sleep 30; echo -n "."
done
echo ""
log "✅ Workers ready!"
log "💡 To start GPU pool for vLLM: ./scripts/gpu-on.sh"
oc get nodes -o wide
