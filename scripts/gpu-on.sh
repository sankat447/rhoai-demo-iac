#!/bin/bash
# gpu-on.sh — Start GPU node for vLLM demo
CLUSTER="${ROSA_CLUSTER:-rhoai-demo}"
log() { echo "[$(date '+%H:%M:%S')] $*"; }
log "🔋 Starting GPU node..."
rosa edit machinepool gpu-demo --cluster="${CLUSTER}" --replicas=1
log "⏳ Waiting for GPU node (~10 min)..."
until oc get nodes -l nvidia.com/gpu=true --no-headers 2>/dev/null | grep -q "Ready"; do
  sleep 30; echo -n "."
done
echo ""
# Scale up vLLM InferenceService
oc patch inferenceservice llama-3-1-8b -n rhoai-demo \
  --type merge -p '{"spec":{"predictor":{"minReplicas":1}}}' 2>/dev/null || \
  log "⚠️  InferenceService not found — deploy from GitOps repo first"
log "✅ GPU node ready. vLLM loading model... (~3 min)"
