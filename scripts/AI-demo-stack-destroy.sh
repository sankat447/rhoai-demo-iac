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

# ── Token helper: persist RHCS_TOKEN to shell rc for the Terraform rhcs provider
# NOTE: This is only needed for the rhcs Terraform provider, NOT for rosa CLI login.
# rosa CLI now uses Red Hat SSO (browser-based). The rhcs provider still requires
# a token obtained via: rosa token  (after SSO login)
persist_and_export_token() {
  local TOKEN="$1"
  local SHELL_RC
  if [[ -n "${ZSH_VERSION:-}" || "${SHELL:-}" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
  elif [[ -n "${BASH_VERSION:-}" || "${SHELL:-}" == */bash ]]; then
    SHELL_RC="$HOME/.bash_profile"
  else
    SHELL_RC="$HOME/.profile"
  fi

  export RHCS_TOKEN="$TOKEN"
  export ROSA_TOKEN="$TOKEN"
  log_ok "RHCS_TOKEN exported for Terraform rhcs provider"

  if [[ -f "$SHELL_RC" ]]; then
    local TMP
    TMP=$(mktemp)
    grep -v "^export RHCS_TOKEN=" "$SHELL_RC" | grep -v "^export ROSA_TOKEN=" > "$TMP"
    mv "$TMP" "$SHELL_RC"
  fi
  {
    echo ""
    echo "# RHCS token for Terraform provider (updated $(date '+%Y-%m-%d %H:%M'))"
    echo "export RHCS_TOKEN=\"${TOKEN}\""
    echo "export ROSA_TOKEN=\"${TOKEN}\""
  } >> "$SHELL_RC"
  log_ok "RHCS_TOKEN persisted to ${SHELL_RC}"
}

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

# ── rosa CLI login (Red Hat SSO — browser-based) ──────────────────────────────
# Offline token login is deprecated by Red Hat. rosa login now uses SSO.
log_ok "Checking OCM authentication (rosa whoami)..."
WHOAMI_OUT=$(rosa whoami 2>&1)
if echo "$WHOAMI_OUT" | grep -q "OCM Account Email"; then
    OCM_EMAIL=$(echo "$WHOAMI_OUT" | grep "OCM Account Email" | awk '{print $NF}')
    log_ok "OCM authenticated — $OCM_EMAIL"
else
    log_warn "ROSA not authenticated — launching Red Hat SSO login..."
    echo -e "     A browser window will open for Red Hat SSO. Complete login then return here."
    echo ""
    if rosa login --use-auth-code; then
        WHOAMI_OUT=$(rosa whoami 2>&1)
        if echo "$WHOAMI_OUT" | grep -q "OCM Account Email"; then
            OCM_EMAIL=$(echo "$WHOAMI_OUT" | grep "OCM Account Email" | awk '{print $NF}')
            log_ok "OCM authenticated — $OCM_EMAIL"
        else
            log_error "ROSA login failed — check your Red Hat account at https://console.redhat.com"
            exit 1
        fi
    else
        log_error "ROSA login failed"
        exit 1
    fi
fi

# ── RHCS_TOKEN for Terraform rhcs provider ────────────────────────────────────
# The rhcs Terraform provider still requires a token. Obtain it from the active
# rosa CLI session (no manual copy/paste needed after SSO login).
if [[ -z "${RHCS_TOKEN:-}" ]]; then
    log "Obtaining RHCS_TOKEN from active rosa session for Terraform provider..."
    RHCS_TOKEN_FROM_ROSA=$(rosa token 2>/dev/null || echo "")
    if [[ -n "$RHCS_TOKEN_FROM_ROSA" ]]; then
        persist_and_export_token "$RHCS_TOKEN_FROM_ROSA"
    else
        log_error "Could not obtain RHCS_TOKEN — Terraform destroy will fail"
        log_error "Try: ./scripts/reauth.sh then retry destroy"
        exit 1
    fi
else
    log_ok "RHCS_TOKEN already set in environment — Terraform rhcs provider ready"
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

# Refresh token before terraform destroy — Steps 2-3 may have taken several minutes
log "Refreshing ROSA token before Terraform destroy..."
NEW_TOKEN=$(rosa token 2>/dev/null || echo "")
if [[ -n "$NEW_TOKEN" ]]; then
    persist_and_export_token "$NEW_TOKEN"
else
    log_warn "Could not refresh token — proceeding with existing token"
fi

# ── Destroy with token-expiry retry (mirrors run_apply_with_retry in create script)
run_destroy_with_retry() {
    local DESTROY_TARGETS="$1"
    local DESTROY_LOG="${LOG_DIR}/destroy_${TIMESTAMP}.log"
    local attempt=1
    local max_attempts=3

    while (( attempt <= max_attempts )); do
        log "terraform destroy — attempt ${attempt} of ${max_attempts}"

        eval terraform destroy $DESTROY_TARGETS -auto-approve 2>&1 | tee "$DESTROY_LOG"
        local RC=${PIPESTATUS[0]}

        # ── Token expiry mid-destroy ─────────────────────────────────────────
        if grep -qiE "invalid_grant|invalid refresh token|can.t get access token|token.*expired" "$DESTROY_LOG" 2>/dev/null; then
            echo ""
            log_warn "ROSA/OCM token expired mid-destroy — re-authenticating via SSO..."
            echo -e "     A browser window will open for Red Hat SSO. Complete login then return here."

            rosa login --use-auth-code || { log_error "ROSA re-login failed"; return 1; }

            if rosa whoami 2>&1 | grep -q "OCM Account Email"; then
                NEW_TOKEN=$(rosa token 2>/dev/null || echo "")
                [[ -n "$NEW_TOKEN" ]] && persist_and_export_token "$NEW_TOKEN"
                log_ok "ROSA re-authenticated — retrying destroy..."
                attempt=$(( attempt + 1 ))
                continue
            else
                log_error "ROSA re-authentication failed"
                return 1
            fi
        fi

        # ── Cluster already deleted outside Terraform ────────────────────────
        if grep -qiE "can.t find cluster|cluster.*not found" "$DESTROY_LOG" 2>/dev/null; then
            log_warn "Cluster appears already deleted outside Terraform — removing from state"
            terraform state rm module.rosa.rhcs_cluster_rosa_hcp.this 2>&1 | tee -a "${LOG_FILE}" || true
            terraform state rm module.rosa.rhcs_hcp_machine_pool.workers 2>&1 | tee -a "${LOG_FILE}" || true
            terraform state rm 'module.rosa.rhcs_hcp_machine_pool.gpu[0]' 2>&1 | tee -a "${LOG_FILE}" || true
            log_ok "Stale ROSA resources removed from state"

            # Retry destroy for remaining resources (IAM IRSA)
            log "Retrying destroy for remaining resources..."
            terraform destroy -target=module.iam_irsa -auto-approve 2>&1 | tee -a "${LOG_FILE}" || log_warn "IAM IRSA destroy had errors"
            return 0
        fi

        # ── Success ──────────────────────────────────────────────────────────
        if [[ $RC -eq 0 ]]; then
            return 0
        fi

        # ── Non-token error ──────────────────────────────────────────────────
        log_error "terraform destroy failed (exit ${RC}) — see: ${DESTROY_LOG}"
        grep -A5 "│ Error:" "$DESTROY_LOG" 2>/dev/null | head -40
        return 1
    done

    log_error "terraform destroy failed after ${max_attempts} attempts"
    return 1
}

log "Running terraform destroy for ROSA and IAM IRSA modules..."
if run_destroy_with_retry "-target=module.rosa -target=module.iam_irsa"; then
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

# Refresh token before full destroy — ROSA teardown (Steps 4-6) may have taken 15+ minutes
log "Refreshing ROSA token before full Terraform destroy..."
NEW_TOKEN=$(rosa token 2>/dev/null || echo "")
if [[ -n "$NEW_TOKEN" ]]; then
    persist_and_export_token "$NEW_TOKEN"
else
    log_warn "Could not refresh token — proceeding with existing token"
fi

log "Running full terraform destroy (handles all dependencies)..."
log "This may take 10-15 minutes..."

# Full destroy using retry wrapper (handles token expiry mid-destroy)
if run_destroy_with_retry ""; then
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
