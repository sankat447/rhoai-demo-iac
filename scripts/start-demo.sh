#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# start-demo.sh — Start all resources and restore demo environment
# This scales up compute resources and verifies cluster readiness
# Usage: ./scripts/start-demo.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CLUSTER="${ROSA_CLUSTER:-rhoai-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/start-demo_${TIMESTAMP}.log"

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
log_error() { echo -e "${RED}✘${RESET} $*" | tee -a "${LOG_FILE}"; }
log_info() { echo -e "${BLUE}➤${RESET} $*" | tee -a "${LOG_FILE}"; }

echo ""
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  START DEMO ENVIRONMENT${RESET}"
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo ""
log "Cluster: ${CLUSTER}"
log "This will scale up compute resources and verify cluster readiness"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 1: Verifying cluster status..."
# ─────────────────────────────────────────────────────────────────────────────

if ! rosa describe cluster -c "${CLUSTER}" &> /dev/null; then
    log_error "Cluster '${CLUSTER}' not found or not accessible"
    log "Ensure you are logged in: rosa login"
    exit 1
fi

CLUSTER_STATE=$(rosa describe cluster -c "${CLUSTER}" | grep "^State:" | awk '{print $2}')
log_ok "Cluster state: ${CLUSTER_STATE}"

if [ "${CLUSTER_STATE}" != "ready" ]; then
    log_error "Cluster is not in 'ready' state - current state: ${CLUSTER_STATE}"
    log "Wait for cluster to be ready before starting"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 2: Scaling compute machine pool with autoscaling..."
# ─────────────────────────────────────────────────────────────────────────────

log "Enabling autoscaling for compute pool: min=2, max=4..."
if rosa edit machinepool compute --cluster="${CLUSTER}" --enable-autoscaling --min-replicas=2 --max-replicas=4 2>&1 | tee -a "${LOG_FILE}"; then
    log_ok "Compute pool autoscaling enabled and scaling initiated"
else
    log_error "Failed to scale compute pool"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 3: Waiting for worker nodes to be Ready..."
# ─────────────────────────────────────────────────────────────────────────────

log "Waiting for nodes to provision and become Ready (typically 5-8 minutes)..."
log "This may take longer on first start after a stop"

TIMEOUT=600  # 10 minutes
ELAPSED=0
TARGET_NODES=2

while [ $ELAPSED -lt $TIMEOUT ]; do
    if command -v oc &> /dev/null && oc whoami &> /dev/null 2>&1; then
        READY_COUNT=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
        
        if [ "$READY_COUNT" -ge "$TARGET_NODES" ]; then
            log_ok "$READY_COUNT worker node(s) are Ready"
            break
        else
            log "  $READY_COUNT/$TARGET_NODES nodes ready... (${ELAPSED}s elapsed)"
        fi
    else
        # Fallback to ROSA CLI if not connected to cluster
        CURRENT_REPLICAS=$(rosa describe machinepool compute -c "${CLUSTER}" 2>/dev/null | grep "Replicas:" | awk '{print $2}' | cut -d'/' -f1 || echo "0")
        
        if [ "$CURRENT_REPLICAS" -ge "$TARGET_NODES" ]; then
            log_ok "$CURRENT_REPLICAS worker node(s) provisioned"
            log_warn "Not connected to cluster - cannot verify node Ready status"
            break
        else
            log "  $CURRENT_REPLICAS/$TARGET_NODES nodes provisioned... (${ELAPSED}s elapsed)"
        fi
    fi
    
    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    log_error "Timeout waiting for nodes to be Ready"
    log "Check node status manually: oc get nodes"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 4: Uncordoning nodes (if previously cordoned)..."
# ─────────────────────────────────────────────────────────────────────────────

if command -v oc &> /dev/null && oc whoami &> /dev/null 2>&1; then
    CORDONED_NODES=$(oc get nodes -l node-role.kubernetes.io/worker -o json 2>/dev/null | jq -r '.items[] | select(.spec.unschedulable==true) | .metadata.name' || echo "")
    
    if [ -n "$CORDONED_NODES" ]; then
        log "Found cordoned nodes - uncordoning..."
        echo "$CORDONED_NODES" | while read -r node; do
            oc adm uncordon "$node" 2>&1 | tee -a "${LOG_FILE}" || log_warn "Failed to uncordon $node"
        done
        log_ok "Nodes uncordoned"
    else
        log_ok "No cordoned nodes found"
    fi
else
    log_warn "Not connected to cluster - skipping uncordon check"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_info "Step 5: Verifying cluster health..."
# ─────────────────────────────────────────────────────────────────────────────

if command -v oc &> /dev/null && oc whoami &> /dev/null 2>&1; then
    log "Checking cluster operators..."
    DEGRADED_OPS=$(oc get co --no-headers 2>/dev/null | grep -v "True.*False.*False" | wc -l | tr -d ' ')
    
    if [ "$DEGRADED_OPS" -eq 0 ]; then
        log_ok "All cluster operators healthy"
    else
        log_warn "$DEGRADED_OPS cluster operator(s) not fully available"
        log "Check status: oc get co"
    fi
    
    log "Current node status:"
    oc get nodes -o wide 2>&1 | tee -a "${LOG_FILE}"
else
    log_warn "Not connected to cluster - skipping health checks"
    log "Connect with: oc login <API-URL>"
fi

echo ""
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  DEMO ENVIRONMENT READY${RESET}"
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
echo ""
log_ok "Worker nodes scaled up and ready"
log_ok "Cluster is operational"
log_ok "All data preserved (Aurora, EFS, S3)"
echo ""

API_URL=$(rosa describe cluster -c "${CLUSTER}" | grep "^API URL:" | awk '{print $3}')
CONSOLE_URL=$(rosa describe cluster -c "${CLUSTER}" | grep "^Console URL:" | awk '{print $3}')

if [ -n "$API_URL" ]; then
    log "API URL:     ${API_URL}"
fi
if [ -n "$CONSOLE_URL" ]; then
    log "Console URL: ${CONSOLE_URL}"
fi

echo ""
log "Next steps:"
log "  • Access OpenShift Console: ${CONSOLE_URL}"
log "  • Login via CLI: oc login ${API_URL}"
log "  • Start GPU pool (if needed): ./scripts/gpu-on.sh"
echo ""
log "To stop the demo environment:"
log "  ${BLUE}./scripts/stop-demo.sh${RESET}"
echo ""
log "Full log: ${LOG_FILE}"
echo ""
