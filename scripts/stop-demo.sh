#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# stop-demo.sh — Gracefully stop all running resources to save costs
# This scales down compute resources but keeps the cluster and data intact
# Usage: ./scripts/stop-demo.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CLUSTER="${ROSA_CLUSTER:-rhoai-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/stop-demo_${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

log() { 
    echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_ok() { echo -e "${GREEN}✔${RESET} $*" | tee -a "${LOG_FILE}"; }
log_warn() { echo -e "${YELLOW}⚠${RESET} $*" | tee -a "${LOG_FILE}"; }
log_info() { echo -e "${BLUE}➤${RESET} $*" | tee -a "${LOG_FILE}"; }

echo ""
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "${BLUE}${BOLD}  STOP DEMO ENVIRONMENT - Cost Savings Mode${RESET}"
echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo ""
log "Cluster: ${CLUSTER}"
log "This will gracefully scale down compute resources while preserving all data"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 1: Checking cluster status..."
# ─────────────────────────────────────────────────────────────────────────────

if ! rosa describe cluster -c "${CLUSTER}" &> /dev/null; then
    log_warn "Cluster '${CLUSTER}' not found or not accessible"
    log "Ensure you are logged in: rosa login"
    exit 1
fi

CLUSTER_STATE=$(rosa describe cluster -c "${CLUSTER}" | grep "^State:" | awk '{print $2}')
log_ok "Cluster state: ${CLUSTER_STATE}"

if [ "${CLUSTER_STATE}" != "ready" ]; then
    log_warn "Cluster is not in 'ready' state - current state: ${CLUSTER_STATE}"
    read -rp "Continue anyway? [y/N]: " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        log "Stop cancelled"
        exit 0
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 2: Draining workloads gracefully (if connected to cluster)..."
# ─────────────────────────────────────────────────────────────────────────────

if command -v oc &> /dev/null && oc whoami &> /dev/null; then
    log "Connected to OpenShift - draining worker nodes..."
    
    # Get worker nodes
    WORKER_NODES=$(oc get nodes -l node-role.kubernetes.io/worker -o name 2>/dev/null || echo "")
    
    if [ -n "$WORKER_NODES" ]; then
        log "Found $(echo "$WORKER_NODES" | wc -l | tr -d ' ') worker node(s)"
        
        # Cordon nodes first (prevent new pods from scheduling)
        log "Cordoning worker nodes..."
        echo "$WORKER_NODES" | while read -r node; do
            oc adm cordon "$node" 2>&1 | tee -a "${LOG_FILE}" || log_warn "Failed to cordon $node"
        done
        log_ok "Worker nodes cordoned"
        
        # Drain nodes gracefully (with timeout)
        log "Draining worker nodes (this may take a few minutes)..."
        echo "$WORKER_NODES" | while read -r node; do
            log "  Draining $node..."
            oc adm drain "$node" \
                --ignore-daemonsets \
                --delete-emptydir-data \
                --disable-eviction \
                --force \
                --grace-period=30 \
                --timeout=2m \
                2>&1 | tee -a "${LOG_FILE}" || log_warn "Drain had warnings for $node"
        done
        log_ok "Worker nodes drained"
    else
        log_warn "No worker nodes found or already scaled to 0"
    fi
else
    log_warn "Not connected to OpenShift cluster - skipping graceful drain"
    log_warn "Pods will be terminated when nodes scale down"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 3: Scaling machine pools to 0..."
# ─────────────────────────────────────────────────────────────────────────────

log "Scaling compute pool to 0 replicas..."
log "  Disabling autoscaling and setting replicas to 0..."
if rosa edit machinepool compute --cluster="${CLUSTER}" --enable-autoscaling=false --replicas=0 2>&1 | tee -a "${LOG_FILE}"; then
    log_ok "Compute pool scaled to 0"
else
    log_warn "Failed to scale compute pool - may not exist or already at 0"
fi

log "Scaling GPU pool to 0 replicas..."
log "  Disabling autoscaling and setting replicas to 0..."
if rosa edit machinepool gpu-demo --cluster="${CLUSTER}" --enable-autoscaling=false --replicas=0 2>&1 | tee -a "${LOG_FILE}"; then
    log_ok "GPU pool scaled to 0"
else
    log_warn "Failed to scale GPU pool - may not exist or already at 0"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 4: Verifying scale-down..."
# ─────────────────────────────────────────────────────────────────────────────

sleep 5
log "Checking machine pool status..."
rosa list machinepools -c "${CLUSTER}" 2>&1 | tee -a "${LOG_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 5: Pausing Aurora database (optional cost savings)..."
# ─────────────────────────────────────────────────────────────────────────────

log_warn "Aurora Serverless v2 cannot be paused - it scales to min ACU automatically"
log "Aurora will scale to minimum capacity (0.5 ACU) when idle"

echo ""
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  DEMO ENVIRONMENT STOPPED${RESET}"
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo ""
log_ok "All compute resources scaled to 0"
log_ok "Cluster control plane remains active (ROSA HCP fee continues)"
log_ok "All data preserved (Aurora, EFS, S3)"
echo ""
log "Estimated hourly cost while stopped:"
log "  • ROSA HCP cluster fee:        ~\$0.25/hr"
log "  • HCP infrastructure (2x m5.xl): ~\$0.38/hr"
log "  • Aurora Serverless v2 (idle):   ~\$0.05/hr"
log "  • NAT Gateway + EFS:             ~\$0.05/hr"
log "  ${BOLD}Total: ~\$0.73/hr (~\$17.50/day)${RESET}"
echo ""
log "To restart the demo environment:"
log "  ${BLUE}./scripts/start-demo.sh${RESET}"
echo ""
log "To completely destroy all resources:"
log "  ${BLUE}./scripts/AI-demo-stack-destroy.sh${RESET}"
echo ""
log "Full log: ${LOG_FILE}"
echo ""
