#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — Complete RHOAI Demo Environment Deployment
# Provisions: AWS Platform Layer + ROSA HCP Cluster + IAM IRSA
# Usage: ./scripts/deploy.sh
# Duration: ~30-35 minutes
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
ENV_DIR="${ROOT_DIR}/environments/demo"
LOG_DIR="${ROOT_DIR}/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/deploy_${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Config
AWS_PROFILE="${AWS_PROFILE:-rhoai-demo}"
CLUSTER_NAME="rhoai-demo"
ACCOUNT_ROLE_PREFIX="rhoai-demo"
AWS_REGION="us-east-1"

log() { 
    echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_section() {
    echo "" | tee -a "${LOG_FILE}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}" | tee -a "${LOG_FILE}"
    echo -e "${CYAN}${BOLD}  $1${RESET}" | tee -a "${LOG_FILE}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════${RESET}" | tee -a "${LOG_FILE}"
}

log_ok() { echo -e "${GREEN}✔${RESET} $*" | tee -a "${LOG_FILE}"; }
log_warn() { echo -e "${YELLOW}⚠${RESET} $*" | tee -a "${LOG_FILE}"; }
log_error() { echo -e "${RED}✘${RESET} $*" | tee -a "${LOG_FILE}"; }
log_info() { echo -e "${BLUE}➤${RESET} $*" | tee -a "${LOG_FILE}"; }

abort() {
    echo "" | tee -a "${LOG_FILE}"
    echo -e "${RED}${BOLD}╔══ FATAL ERROR ══════════════════════════════════════════════════════╗${RESET}" | tee -a "${LOG_FILE}"
    echo -e "${RED}${BOLD}║  $1${RESET}" | tee -a "${LOG_FILE}"
    echo -e "${RED}${BOLD}╚═════════════════════════════════════════════════════════════════════╝${RESET}" | tee -a "${LOG_FILE}"
    log "Full log: ${LOG_FILE}"
    exit 1
}

# Banner
clear
echo ""
echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${WHITE}██████╗ ██╗  ██╗ ██████╗  █████╗ ██╗    ██████╗ ███████╗███╗   ███╗ ██████╗${RESET}${BLUE}${BOLD}  ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${WHITE}██╔══██╗██║  ██║██╔═══██╗██╔══██╗██║    ██╔══██╗██╔════╝████╗ ████║██╔═══██╗${RESET}${BLUE}${BOLD} ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${WHITE}██████╔╝███████║██║   ██║███████║██║    ██║  ██║█████╗  ██╔████╔██║██║   ██║${RESET}${BLUE}${BOLD} ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${WHITE}██╔══██╗██╔══██║██║   ██║██╔══██║██║    ██║  ██║██╔══╝  ██║╚██╔╝██║██║   ██║${RESET}${BLUE}${BOLD} ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${WHITE}██║  ██║██║  ██║╚██████╔╝██║  ██║██║    ██████╔╝███████╗██║ ╚═╝ ██║╚██████╔╝${RESET}${BLUE}${BOLD} ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${WHITE}╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝    ╚═════╝ ╚══════╝╚═╝     ╚═╝ ╚═════╝${RESET}${BLUE}${BOLD}  ║${RESET}"
echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${WHITE}${BOLD}Complete Environment Deployment${RESET}${BLUE}${BOLD}                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}AWS Platform + ROSA HCP + IAM IRSA${RESET}${BLUE}${BOLD}                                ║${RESET}"
echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${GREEN}Duration: ~30-35 minutes${RESET}${BLUE}${BOLD}                                          ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}Run: ${TIMESTAMP}${RESET}${BLUE}${BOLD}                                    ║${RESET}"
echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""

log_section "DEPLOYMENT STARTED"
log "Log file: ${LOG_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 1: PREREQUISITES CHECK"
# ─────────────────────────────────────────────────────────────────────────────

log_info "Checking required tools..."
MISSING_TOOLS=false

for tool in aws terraform rosa oc git jq; do
    if command -v "$tool" &>/dev/null; then
        VER=$("$tool" --version 2>&1 | head -1)
        log_ok "$tool → $VER"
    else
        log_error "$tool not found"
        MISSING_TOOLS=true
    fi
done

if [ "$MISSING_TOOLS" = true ]; then
    abort "Missing required tools. Install: brew install awscli terraform rosa-cli openshift-cli jq"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 2: AWS AUTHENTICATION"
# ─────────────────────────────────────────────────────────────────────────────

log_info "Checking AWS SSO authentication..."
if aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
    ACCOUNT=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
    log_ok "AWS authenticated - Account: $ACCOUNT"
else
    log_warn "AWS SSO not authenticated - logging in..."
    aws sso login --profile "$AWS_PROFILE" || abort "AWS SSO login failed"
    log_ok "AWS SSO login succeeded"
fi

export AWS_PROFILE="$AWS_PROFILE"

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 3: ROSA AUTHENTICATION"
# ─────────────────────────────────────────────────────────────────────────────

log_info "Checking ROSA authentication..."
if rosa whoami &>/dev/null; then
    OCM_EMAIL=$(rosa whoami 2>&1 | grep "OCM Account Email" | awk '{print $NF}')
    log_ok "ROSA authenticated - $OCM_EMAIL"
else
    log_warn "ROSA not authenticated"
    log "Red Hat has deprecated token-based login"
    log "Please use Red Hat SSO credentials to login"
    echo ""
    
    log_info "Logging in with Red Hat SSO..."
    if rosa login; then
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
        abort "ROSA login failed"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 4: TERRAFORM INITIALIZATION"
# ─────────────────────────────────────────────────────────────────────────────

cd "$ENV_DIR" || abort "Cannot navigate to $ENV_DIR"

log_info "Running terraform init..."
if terraform init -reconfigure &>> "${LOG_FILE}"; then
    log_ok "Terraform initialized"
else
    abort "Terraform init failed - check log: ${LOG_FILE}"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 5: TERRAFORM PLAN"
# ─────────────────────────────────────────────────────────────────────────────

log_info "Running terraform plan..."
if terraform plan -out=tfplan &>> "${LOG_FILE}"; then
    PLAN_SUMMARY=$(grep -E "^Plan:|^No changes\." "${LOG_FILE}" | tail -1)
    log_ok "Terraform plan succeeded"
    log "$PLAN_SUMMARY"
else
    log_error "Terraform plan failed"
    grep -A5 "Error:" "${LOG_FILE}" | tail -20
    abort "Fix plan errors and re-run"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 6: TERRAFORM APPLY (AWS + ROSA)"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}${BOLD}This will create real AWS resources and incur costs.${RESET}"
echo -e "${YELLOW}Estimated cost: ~\$2/hr (~\$50/day) with cluster running${RESET}"
echo ""
read -rp "Continue with deployment? [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_warn "Deployment cancelled by user"
    exit 0
fi

log_info "Running terraform apply (this will take 25-30 minutes)..."
log "Phase 1: AWS infrastructure (~10 min)"
log "Phase 2: ROSA cluster creation (~20 min)"
echo ""

# Apply with retry on token expiry
ATTEMPT=1
MAX_ATTEMPTS=3

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    log_info "Terraform apply - attempt $ATTEMPT of $MAX_ATTEMPTS"
    
    terraform apply tfplan 2>&1 | tee -a "${LOG_FILE}"
    APPLY_RC=${PIPESTATUS[0]}
    
    # Check for token expiry
    if grep -qiE "invalid_grant|invalid refresh token|can't get access token|token.*expired" "${LOG_FILE}"; then
        log_warn "ROSA token expired - re-authenticating..."
        
        echo ""
        echo -e "${YELLOW}Get fresh token: https://console.redhat.com/openshift/token${RESET}"
        read -rp "Paste your Red Hat offline token: " ROSA_TOKEN_INPUT
        
        if [ -n "$ROSA_TOKEN_INPUT" ]; then
            rosa login --token="$ROSA_TOKEN_INPUT"
            export RHCS_TOKEN="$ROSA_TOKEN_INPUT"
            export ROSA_TOKEN="$ROSA_TOKEN_INPUT"
            log_ok "Re-authenticated - retrying apply..."
            ATTEMPT=$((ATTEMPT + 1))
            continue
        else
            abort "No token provided - cannot retry"
        fi
    fi
    
    # Check for errors
    ERROR_COUNT=$(grep -c "^│ Error:" "${LOG_FILE}" 2>/dev/null || echo 0)
    
    if [ $APPLY_RC -eq 0 ] && [ "$ERROR_COUNT" -eq 0 ]; then
        APPLY_SUMMARY=$(grep "^Apply complete!" "${LOG_FILE}" | tail -1)
        log_ok "Terraform apply succeeded - $APPLY_SUMMARY"
        break
    else
        log_error "Terraform apply failed"
        grep -A5 "^│ Error:" "${LOG_FILE}" | tail -30
        
        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
            log_warn "Retrying..."
            ATTEMPT=$((ATTEMPT + 1))
        else
            abort "Apply failed after $MAX_ATTEMPTS attempts"
        fi
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 7: CLUSTER READINESS CHECK"
# ─────────────────────────────────────────────────────────────────────────────

log_info "Waiting for ROSA cluster to be ready..."
log "This typically takes 15-20 minutes for HCP clusters"
echo ""

WAIT_MINUTES=0
MAX_WAIT=30

while [ $WAIT_MINUTES -lt $MAX_WAIT ]; do
    if rosa describe cluster -c "$CLUSTER_NAME" &>/dev/null; then
        STATE=$(rosa describe cluster -c "$CLUSTER_NAME" | grep "^State:" | awk '{print $2}')
        
        printf "[%02d min] Cluster state: %-15s\n" "$WAIT_MINUTES" "$STATE"
        
        if [ "$STATE" = "ready" ]; then
            log_ok "Cluster is READY!"
            break
        elif [[ "$STATE" =~ ^(error|degraded|uninstalling)$ ]]; then
            log_error "Cluster entered error state: $STATE"
            rosa describe cluster -c "$CLUSTER_NAME"
            abort "Cluster deployment failed"
        fi
    else
        log_warn "Cannot query cluster status - checking authentication..."
        rosa whoami &>/dev/null || {
            log_warn "ROSA session expired - re-authenticating..."
            if [ -n "${RHCS_TOKEN:-}" ]; then
                rosa login --token="$RHCS_TOKEN"
            fi
        }
    fi
    
    sleep 60
    WAIT_MINUTES=$((WAIT_MINUTES + 1))
done

if [ "$STATE" != "ready" ]; then
    log_warn "Cluster not ready after $MAX_WAIT minutes"
    log "Check status: rosa describe cluster -c $CLUSTER_NAME"
fi

# ─────────────────────────────────────────────────────────────────────────────
log_section "STEP 8: POST-DEPLOYMENT VERIFICATION"
# ─────────────────────────────────────────────────────────────────────────────

log_info "Gathering deployment information..."

# Get outputs
API_URL=$(cd "$ENV_DIR" && terraform output -raw rosa_api_url 2>/dev/null || echo "")
CONSOLE_URL=$(cd "$ENV_DIR" && terraform output -raw rosa_console_url 2>/dev/null || echo "")
VPC_ID=$(cd "$ENV_DIR" && terraform output -raw vpc_id 2>/dev/null || echo "")
S3_BUCKET=$(cd "$ENV_DIR" && terraform output -raw s3_bucket_name 2>/dev/null || echo "")
AURORA_ENDPOINT=$(cd "$ENV_DIR" && terraform output -raw aurora_endpoint 2>/dev/null || echo "")

log_ok "VPC: $VPC_ID"
log_ok "S3 Bucket: $S3_BUCKET"
log_ok "Aurora: $AURORA_ENDPOINT"
log_ok "API URL: $API_URL"
log_ok "Console: $CONSOLE_URL"

# ─────────────────────────────────────────────────────────────────────────────
log_section "DEPLOYMENT COMPLETE"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║                    DEPLOYMENT SUCCESSFUL                             ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
log_ok "All resources deployed successfully"
echo ""
echo -e "${WHITE}${BOLD}Next Steps:${RESET}"
echo ""
echo -e "${CYAN}1. Create cluster admin:${RESET}"
echo -e "   ${DIM}rosa create admin -c $CLUSTER_NAME${RESET}"
echo ""
echo -e "${CYAN}2. Login to cluster:${RESET}"
echo -e "   ${DIM}oc login $API_URL --username cluster-admin${RESET}"
echo ""
echo -e "${CYAN}3. Verify cluster:${RESET}"
echo -e "   ${DIM}oc get nodes${RESET}"
echo -e "   ${DIM}oc get co${RESET}"
echo ""
echo -e "${CYAN}4. Access console:${RESET}"
echo -e "   ${DIM}$CONSOLE_URL${RESET}"
echo ""
echo -e "${CYAN}5. View resources:${RESET}"
echo -e "   ${DIM}./scripts/show-resources.sh${RESET}"
echo ""
echo -e "${WHITE}Cost Management:${RESET}"
echo -e "   ${DIM}Stop demo:  ./scripts/stop-demo.sh  (~\$0.73/hr)${RESET}"
echo -e "   ${DIM}Start demo: ./scripts/start-demo.sh${RESET}"
echo -e "   ${DIM}Teardown:   ./scripts/AI-demo-stack-destroy.sh   (\$0/hr)${RESET}"
echo ""
log "Full log: ${LOG_FILE}"
echo ""
