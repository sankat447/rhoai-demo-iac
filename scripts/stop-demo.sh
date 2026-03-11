#!/bin/bash
# stop-demo.sh — Scale workers to 0 after a demo session (saves ~$100/mo)
# Usage: aws-vault exec rhoai-demo -- ./scripts/stop-demo.sh
set -euo pipefail
CLUSTER="${ROSA_CLUSTER:-rhoai-demo}"
log() { echo "[$(date '+%H:%M:%S')] $*"; }
log "⏹  Stopping demo — scaling workers to 0..."
rosa edit machinepool workers   --cluster="${CLUSTER}" --replicas=0 2>/dev/null || true
rosa edit machinepool gpu-demo  --cluster="${CLUSTER}" --replicas=0 2>/dev/null || true
log "💤 Scaled to 0. ROSA HCP fee continues (~\$0.25/hr)"
log "   Run teardown.sh to fully destroy and reach \$0/hr"
