#!/bin/bash
# gpu-off.sh — Remove GPU node (saves ~$0.37/hr spot)
CLUSTER="${ROSA_CLUSTER:-rhoai-demo}"
log() { echo "[$(date '+%H:%M:%S')] $*"; }
oc patch inferenceservice llama-3-1-8b -n rhoai-demo \
  --type merge -p '{"spec":{"predictor":{"minReplicas":0}}}' 2>/dev/null || true
rosa edit machinepool gpu-demo --cluster="${CLUSTER}" --replicas=0
log "✅ GPU node removed."
