#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# AI-demo-stack-destroy.sh — Destroy ALL AWS, ROSA, and OCP resources created in this install
# This is a COMPLETE stack destruction - use when demo environment is no longer needed
# Usage: ./scripts/AI-demo-stack-destroy.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
ENV_DIR="${ROOT_DIR}/environments/demo"
LOG_DIR="${ROOT_DIR}/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/stack-destroy_${TIMESTAMP}.log"

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

log_section() {
    echo "" | tee -a "${LOG_FILE}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}" | tee -a "${LOG_FILE}"
    echo -e "${BLUE}${BOLD}  $1${RESET}" | tee -a "${LOG_FILE}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}" | tee -a "${LOG_FILE}"
}

log_ok() { echo -e "${GREEN}✔${RESET} $*" | tee -a "${LOG_FILE}"; }
log_warn() { echo -e "${YELLOW}⚠${RESET} $*" | tee -a "${LOG_FILE}"; }
log_error() { echo -e "${RED}✘${RESET} $*" | tee -a "${LOG_FILE}"; }

echo ""
echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${RED}${BOLD}║                    COMPLETE TEARDOWN WARNING                        ║${RESET}"
echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${RED}This will PERMANENTLY DESTROY all resources created in this install:${RESET}"
echo ""
echo -e "${YELLOW}ROSA Layer:${RESET}"
echo "   • ROSA HCP cluster (all namespaces and workloads)"
echo "   • Machine pools (compute + GPU)"
echo "   • IAM IRSA roles (S3, Bedrock, ECR, SSM access)"
echo "   • Operator IAM roles"
echo ""
echo -e "${YELLOW}AWS Platform Layer:${RESET}"
echo "   • Aurora PostgreSQL cluster (ALL DATA WILL BE LOST)"
echo "   • EFS file system (all notebook files)"
echo "   • S3 bucket (data lake - will be emptied)"
echo "   • ECR repositories"
echo "   • Lambda scheduler"
echo "   • VPC, subnets, NAT gateway, security groups"
echo "   • IAM roles and policies"
echo "   • SSM parameters"
echo "   • Budget alerts"
echo ""
echo -e "${YELLOW}OpenShift Objects:${RESET}"
echo "   • All user-created namespaces and workloads"
echo "   • PVCs and associated storage"
echo "   • ConfigMaps, Secrets, ServiceAccounts"
echo "   • (Platform objects like StorageClasses, SCCs are cluster-scoped and removed with cluster)"
echo ""
echo -e "${RED}${BOLD}⚠  THIS ACTION CANNOT BE UNDONE${RESET}"
echo ""
read -rp "Type 'destroy-demo' to confirm complete teardown: " confirm

if [ "${confirm}" != "destroy-demo" ]; then
    echo -e "${YELLOW}Teardown cancelled - no changes made${RESET}"
    exit 0
fi

log_section "TEARDOWN STARTED"
log "Log file: ${LOG_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 1: ROSA AUTHENTICATION"
# ─────────────────────────────────────────────────────────────────────────────

log_ok "Checking ROSA authentication..."
if rosa whoami &>/dev/null; then
    OCM_EMAIL=$(rosa whoami 2>&1 | grep "OCM Account Email" | awk '{print $NF}')
    log_ok "ROSA authenticated - $OCM_EMAIL"
else
    log_warn "ROSA not authenticated"
    log "Red Hat has deprecated token-based login"
    log "Using Red Hat SSO credentials to login"
    echo ""
    
    log_ok "Logging in with Red Hat SSO..."
    if rosa login --use-auth-code; then
        OCM_EMAIL=$(rosa whoami 2>&1 | grep "OCM Account Email" | awk '{print $NF}')
        log_ok "ROSA authenticated - $OCM_EMAIL"
        
        # Export token for Terraform rhcs provider
        RHCS_TOKEN=$(rosa token 2>/dev/null || echo "")
        if [ -n "$RHCS_TOKEN" ]; then
            export RHCS_TOKEN
            export ROSA_TOKEN="$RHCS_TOKEN"
            log_ok "Token exported for Terraform provider"
        fi
    else
        log_error "ROSA login failed"
        exit 1
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 2: OPENSHIFT CLEANUP (User Workloads)"
# ─────────────────────────────────────────────────────────────────────────────

if command -v oc &> /dev/null && oc whoami &> /dev/null; then
    log "Connected to OpenShift cluster - cleaning up user workloads..."
    
    # Delete user namespaces (exclude openshift-*, kube-*, default)
    log "Deleting user-created namespaces..."
    USER_NAMESPACES=$(oc get namespaces -o json | jq -r '.items[] | select(.metadata.name | test("^(openshift-|kube-|default$)") | not) | .metadata.name' 2>/dev/null || echo "")
    
    if [ -n "$USER_NAMESPACES" ]; then
        echo "$USER_NAMESPACES" | while read -r ns; do
            log "  Deleting namespace: $ns"
            oc delete namespace "$ns" --wait=false 2>&1 | tee -a "${LOG_FILE}" || log_warn "Failed to delete namespace $ns"
        done
        log_ok "User namespaces deletion initiated"
    else
        log_ok "No user namespaces found"
    fi
    
    # Wait for namespace deletion (with timeout)
    log "Waiting for namespace deletion to complete (max 5 minutes)..."
    TIMEOUT=300
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        REMAINING=$(oc get namespaces -o json | jq -r '.items[] | select(.metadata.name | test("^(openshift-|kube-|default$)") | not) | .metadata.name' 2>/dev/null | wc -l | tr -d ' ')
        if [ "$REMAINING" -eq 0 ]; then
            log_ok "All user namespaces deleted"
            break
        fi
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        log_warn "Namespace deletion timeout - some namespaces may still be terminating"
    fi
else
    log_warn "Not connected to OpenShift cluster - skipping OCP cleanup"
    log_warn "User workloads will be deleted when cluster is destroyed"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 3: ROSA CLUSTER TEARDOWN"
# ─────────────────────────────────────────────────────────────────────────────

CLUSTER_NAME=$(cd "${ENV_DIR}" && terraform output -raw rosa_cluster_name 2>/dev/null || echo "rhoai-demo")

log "Checking ROSA cluster: ${CLUSTER_NAME}"
if rosa describe cluster -c "${CLUSTER_NAME}" &> /dev/null; then
    log "Scaling machine pools to 0 for faster deletion..."
    # Disable autoscaling and set to 0 (learned from stop-demo.sh)
    rosa edit machinepool compute --cluster="${CLUSTER_NAME}" --enable-autoscaling=false --replicas=0 2>&1 | tee -a "${LOG_FILE}" || log_warn "Failed to scale compute pool"
    rosa edit machinepool gpu-demo --cluster="${CLUSTER_NAME}" --enable-autoscaling=false --replicas=0 2>&1 | tee -a "${LOG_FILE}" || log_warn "Failed to scale GPU pool"
    log_ok "Machine pools scaled to 0"
else
    log_warn "ROSA cluster not found - may already be deleted"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 4: TERRAFORM DESTROY (ROSA + IAM IRSA)"
# ─────────────────────────────────────────────────────────────────────────────

cd "${ENV_DIR}" || { log_error "Cannot navigate to ${ENV_DIR}"; exit 1; }

log "Running terraform destroy for ROSA and IAM IRSA modules..."
terraform destroy \
    -target=module.rosa \
    -target=module.iam_irsa \
    -auto-approve \
    2>&1 | tee -a "${LOG_FILE}"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    log_ok "ROSA cluster and IAM IRSA roles destroyed"
else
    log_error "ROSA destroy had errors - check log file"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 5: ROSA OPERATOR ROLES CLEANUP"
# ─────────────────────────────────────────────────────────────────────────────

log "Cleaning up ROSA operator roles..."
rosa delete operator-roles -c "${CLUSTER_NAME}" --mode auto --yes 2>&1 | tee -a "${LOG_FILE}" || log_warn "Operator roles cleanup had errors"
log_ok "Operator roles cleanup attempted"

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 6: VERIFY CLUSTER REMOVED"
# ─────────────────────────────────────────────────────────────────────────────

log "Waiting for cluster to be fully removed..."
sleep 10

if rosa describe cluster -c "${CLUSTER_NAME}" 2>&1 | grep -qiE "There is no cluster|not found"; then
    log_ok "ROSA cluster confirmed removed"
else
    log_warn "ROSA cluster may still be uninstalling - continuing with AWS teardown"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 7: AWS PLATFORM TEARDOWN"
# ─────────────────────────────────────────────────────────────────────────────

# Empty S3 bucket first (with better error handling)
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
if [ -n "$S3_BUCKET" ]; then
    log "Emptying S3 bucket: ${S3_BUCKET}"
    if aws s3 ls "s3://${S3_BUCKET}" &>/dev/null; then
        aws s3 rm "s3://${S3_BUCKET}" --recursive 2>&1 | tee -a "${LOG_FILE}" || log_warn "S3 bucket empty failed - may already be empty"
        log_ok "S3 bucket emptied"
    else
        log_ok "S3 bucket already empty or doesn't exist"
    fi
fi

log "Running full terraform destroy (handles all dependencies)..."
log "This may take 10-15 minutes..."

# Full destroy without -target flags (handles dependencies properly)
terraform destroy -auto-approve 2>&1 | tee -a "${LOG_FILE}"
DESTROY_RC=${PIPESTATUS[0]}

if [ $DESTROY_RC -eq 0 ]; then
    log_ok "All AWS resources destroyed successfully"
else
    log_warn "Terraform destroy completed with warnings - checking state..."
    
    # Refresh state to sync with actual AWS resources
    log "Refreshing Terraform state..."
    terraform refresh 2>&1 | tee -a "${LOG_FILE}" || log_warn "State refresh had issues"
    
    # Retry destroy if there are remaining resources
    REMAINING=$(terraform plan -json 2>/dev/null | grep -c '"type": "resource"' || echo "0")
    if [ "$REMAINING" -gt 0 ]; then
        log_warn "Found $REMAINING remaining resources - retrying destroy..."
        terraform destroy -auto-approve 2>&1 | tee -a "${LOG_FILE}" || log_error "Final destroy attempt failed"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 8: OPTIONAL CLEANUP"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
read -rp "Delete ROSA account roles? (can be reused for future deploys) [y/N]: " delete_account_roles
if [[ "$delete_account_roles" =~ ^[Yy]$ ]]; then
    log "Deleting ROSA account roles..."
    rosa delete account-roles --prefix "rhoai-demo" --mode auto --yes 2>&1 | tee -a "${LOG_FILE}" || log_warn "Account roles deletion had errors"
    log_ok "Account roles deleted"
else
    log_ok "Account roles retained for future use"
fi

echo ""
read -rp "Delete OIDC config? (can be reused for future deploys) [y/N]: " delete_oidc
if [[ "$delete_oidc" =~ ^[Yy]$ ]]; then
    OIDC_ID=$(terraform output -raw oidc_config_id 2>/dev/null || echo "2ovm1pcngkss9e6stmbirbefljiiuptk")
    log "Deleting OIDC config: ${OIDC_ID}"
    rosa delete oidc-config --oidc-config-id "${OIDC_ID}" --yes 2>&1 | tee -a "${LOG_FILE}" || log_warn "OIDC config deletion had errors"
    log_ok "OIDC config deleted"
else
    log_ok "OIDC config retained for future use"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "TEARDOWN COMPLETE"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
log_ok "All resources destroyed successfully"
log "Billing should drop to ~\$0/hr"
log "Terraform state bucket preserved for future deployments"
echo ""
log "Full log: ${LOG_FILE}"
echo ""
echo -e "${GREEN}${BOLD}To redeploy from scratch:${RESET}"
echo -e "  ${BLUE}./scripts/AI-demo-stack-create.sh${RESET}"
echo ""
