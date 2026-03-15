#!/usr/bin/env bash
# =============================================================================
#  IIS Tech — Setup Cluster Admin for Existing ROSA Deployment
#  https://www.iistech.com/
#
#  Usage   : ./scripts/setup-cluster-admin.sh
#  Purpose : Delete old admin and create new one with credentials display
#  Duration: ~2-3 minutes
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
ENV_DIR="${ROOT_DIR}/environments/demo"
LOG_DIR="${ROOT_DIR}/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/setup-admin_${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

# ── Colour palette ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Config ────────────────────────────────────────────────────────────────────
AWS_PROFILE="${AWS_PROFILE:-rhoai-demo}"
CLUSTER_NAME="rhoai-demo"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()       { echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
log_ok()    { echo -e "  ${GREEN}✔${RESET}  ${GREEN}$*${RESET}" | tee -a "${LOG_FILE}"; }
log_warn()  { echo -e "  ${YELLOW}⚠${RESET}  ${YELLOW}$*${RESET}" | tee -a "${LOG_FILE}"; }
log_fail()  { echo -e "  ${RED}✘${RESET}  ${RED}$*${RESET}" | tee -a "${LOG_FILE}"; }
log_info()  { echo -e "  ${BLUE}➤${RESET}  $*" | tee -a "${LOG_FILE}"; }

section() {
  echo "" | tee -a "${LOG_FILE}"
  echo -e "${CYAN}${BOLD}┌──────────────────────────────────────────────────────────────────────┐${RESET}" | tee -a "${LOG_FILE}"
  printf "${CYAN}${BOLD}│  %-68s│${RESET}\\n" "$1" | tee -a "${LOG_FILE}"
  echo -e "${CYAN}${BOLD}└──────────────────────────────────────────────────────────────────────┘${RESET}" | tee -a "${LOG_FILE}"
}

abort() {
  echo "" | tee -a "${LOG_FILE}"
  echo -e "${RED}${BOLD}╔══ FATAL ERROR ══════════════════════════════════════════════════════════╗${RESET}" | tee -a "${LOG_FILE}"
  echo -e "${RED}${BOLD}║  $1${RESET}" | tee -a "${LOG_FILE}"
  echo -e "${RED}${BOLD}╚═════════════════════════════════════════════════════════════════════════╝${RESET}" | tee -a "${LOG_FILE}"
  exit 1
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${WHITE}${BOLD}Setup Cluster Admin — Existing ROSA Deployment${RESET}${BLUE}${BOLD}                  ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}https://www.iistech.com/${RESET}${BLUE}${BOLD}                                          ║${RESET}"
echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${GREEN}Duration: ~2-3 minutes${RESET}${BLUE}${BOLD}                                          ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}Run: ${TIMESTAMP}${RESET}${BLUE}${BOLD}                                    ║${RESET}"
echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
log "Log file: ${LOG_FILE}"

# =============================================================================
section "PHASE 1 — AUTHENTICATION CHECK"
# =============================================================================

log_info "Checking AWS SSO session..."
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
  log_warn "AWS SSO session expired — logging in..."
  aws sso login --profile "$AWS_PROFILE" || abort "AWS SSO login failed"
fi
log_ok "AWS authenticated"

log_info "Checking ROSA/OCM authentication..."
if ! rosa whoami &>/dev/null; then
  log_warn "ROSA not authenticated — launching Red Hat SSO login..."
  echo -e "     ${DIM}A browser window will open for Red Hat SSO. Complete login then return here.${RESET}"
  echo ""
  rosa login --use-auth-code || abort "ROSA login failed"
fi
log_ok "ROSA/OCM authenticated"

# =============================================================================
section "PHASE 2 — VERIFY CLUSTER EXISTS"
# =============================================================================

log_info "Checking cluster '${CLUSTER_NAME}'..."
DESCRIBE_OUT=$(rosa describe cluster -c "$CLUSTER_NAME" 2>&1)
DESCRIBE_RC=$?

if [[ $DESCRIBE_RC -ne 0 ]]; then
  log_fail "Cluster '${CLUSTER_NAME}' not found or not accessible"
  echo "$DESCRIBE_OUT"
  abort "Cannot proceed without accessible cluster"
fi

CLUSTER_STATE=$(echo "$DESCRIBE_OUT" | grep -iE "^State:" | awk '{print tolower($2)}' | tr -d '[:space:]')
CLUSTER_STATE="${CLUSTER_STATE:-unknown}"

log_ok "Cluster found — State: ${CLUSTER_STATE}"

if [[ "$CLUSTER_STATE" != "ready" ]]; then
  log_warn "Cluster is not in 'ready' state — admin creation may fail"
  echo -e "     ${DIM}Current state: ${CLUSTER_STATE}${RESET}"
fi

# =============================================================================
section "PHASE 3 — CLUSTER ADMIN SETUP"
# =============================================================================

log_info "Deleting old cluster admin (if exists)..."
if rosa delete admin -c "$CLUSTER_NAME" --yes 2>/dev/null; then
  log_ok "Old cluster admin deleted"
else
  log_warn "No existing cluster admin found (or already deleted)"
fi

echo ""
log_info "Creating new cluster admin..."
echo -e "     ${DIM}This may take 1-2 minutes for OAuth to propagate${RESET}"
echo ""

ADMIN_OUTPUT=$(rosa create admin -c "$CLUSTER_NAME" 2>&1)
ADMIN_RC=$?

if [[ $ADMIN_RC -eq 0 ]]; then
  ADMIN_USER=$(echo "$ADMIN_OUTPUT" | grep -oP "username: \K[^ ]+" | head -1)
  ADMIN_PASS=$(echo "$ADMIN_OUTPUT" | grep -oP "password: \K[^ ]+" | head -1)
  
  if [[ -n "$ADMIN_USER" && -n "$ADMIN_PASS" ]]; then
    log_ok "Cluster admin created successfully"
  else
    log_warn "Could not parse admin credentials from output"
    echo "$ADMIN_OUTPUT"
  fi
else
  log_fail "Failed to create cluster admin"
  echo "$ADMIN_OUTPUT"
  abort "Admin creation failed"
fi

# =============================================================================
section "PHASE 4 — RETRIEVE CLUSTER DETAILS"
# =============================================================================

log_info "Retrieving cluster URLs..."

cd "$ENV_DIR" || abort "Cannot navigate to ${ENV_DIR}"

API_URL=$(terraform output -raw rosa_api_url 2>/dev/null || echo "")
CONSOLE_URL=$(terraform output -raw rosa_console_url 2>/dev/null || echo "")

if [[ -z "$API_URL" ]]; then
  API_URL=$(echo "$DESCRIBE_OUT" | grep -iE "^API URL:" | awk '{print $NF}')
fi

if [[ -z "$CONSOLE_URL" ]]; then
  CONSOLE_URL=$(echo "$DESCRIBE_OUT" | grep -iE "^Console URL:" | awk '{print $NF}')
fi

[[ -n "$API_URL" ]] && log_ok "API URL: ${API_URL}"
[[ -n "$CONSOLE_URL" ]] && log_ok "Console URL: ${CONSOLE_URL}"

# =============================================================================
section "CLUSTER ADMIN CREDENTIALS"
# =============================================================================

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║                    ADMIN SETUP COMPLETE  🎉                         ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${WHITE}${BOLD}OpenShift Console Access:${RESET}"
echo ""

if [[ -n "$CONSOLE_URL" ]]; then
  echo -e "${CYAN}Console URL:${RESET}"
  echo -e "  ${WHITE}${BOLD}${CONSOLE_URL}${RESET}"
  echo ""
fi

if [[ -n "$ADMIN_USER" && -n "$ADMIN_PASS" ]]; then
  echo -e "${CYAN}Credentials:${RESET}"
  echo -e "  ${WHITE}${BOLD}Username: ${ADMIN_USER}${RESET}"
  echo -e "  ${WHITE}${BOLD}Password: ${ADMIN_PASS}${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}⚠  Save these credentials — they will not be shown again${RESET}"
  echo ""
fi

echo -e "${WHITE}${BOLD}Next Steps:${RESET}"
echo ""
echo -e "${CYAN}1. Wait 2-3 minutes for OAuth to propagate, then login:${RESET}"
if [[ -n "$API_URL" ]]; then
  echo -e "   ${DIM}oc login ${API_URL} --username ${ADMIN_USER:-cluster-admin}${RESET}"
else
  echo -e "   ${DIM}oc login <API_URL> --username ${ADMIN_USER:-cluster-admin}${RESET}"
fi
echo ""
echo -e "${CYAN}2. Verify cluster:${RESET}"
echo -e "   ${DIM}oc get nodes && oc get co${RESET}"
echo ""
echo -e "${CYAN}3. Cost controls:${RESET}"
echo -e "   ${DIM}Stop:     ./scripts/stop-demo.sh   (~\$0.73/hr)${RESET}"
echo -e "   ${DIM}Destroy:  ./scripts/AI-demo-stack-destroy.sh   (\$0/hr)${RESET}"
echo ""
echo -e "${DIM}Full log: ${LOG_FILE}${RESET}"
echo ""
