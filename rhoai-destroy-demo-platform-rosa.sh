#!/usr/bin/env zsh
# =============================================================================
#  IIS Tech — Demo AI Platform on AWS + ROSA
#  DESTROY — ROSA Layer (run this BEFORE rhoai-destroy-demo-platform-aws.sh)
#  https://www.iistech.com/
#
#  Destroys:
#    - IAM IRSA roles
#    - ROSA HCP Cluster (rhoai-demo)
#    - Worker + GPU machine pools
#    - ROSA operator IAM roles
#    - OIDC config (optional — prompted)
#    - ROSA account roles (optional — prompted)
#
#  Does NOT destroy:
#    - VPC, Aurora, S3, EFS, ECR, Lambda (use platform-aws destroy script)
#
#  Usage: chmod +x rhoai-destroy-demo-platform-rosa.sh
#         ./rhoai-destroy-demo-platform-rosa.sh
# =============================================================================

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
AWS_PROFILE="rhoai-demo"
REPO_PATH="$HOME/GitHub/rhoai-demo-iac/environments/demo"
LOG_DIR="$HOME/GitHub/rhoai-demo-iac/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CLUSTER_NAME="rhoai-demo"
ACCOUNT_ROLE_PREFIX="rhoai-demo"
OIDC_CONFIG_ID="2ovm1pcngkss9e6stmbirbefljiiuptk"

# ── Tracking ──────────────────────────────────────────────────────────────────
STEPS_PASSED=0
STEPS_FAILED=0
STEPS_WARNED=0
SUMMARY_LINES=()

# ── Helpers ───────────────────────────────────────────────────────────────────
print_banner() {
  clear
  echo ""
  echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${RED}${BOLD}║                                                                      ║${RESET}"
  echo -e "${RED}${BOLD}║  ${WHITE}██╗██╗███████╗    ████████╗███████╗ ██████╗ ██╗  ██╗${RED}               ║${RESET}"
  echo -e "${RED}${BOLD}║  ${WHITE}██║██║██╔════╝    ╚══██╔══╝██╔════╝██╔════╝ ██║  ██║${RED}               ║${RESET}"
  echo -e "${RED}${BOLD}║  ${WHITE}██║██║███████╗       ██║   █████╗  ██║      ███████║${RED}               ║${RESET}"
  echo -e "${RED}${BOLD}║  ${WHITE}██║██║╚════██║       ██║   ██╔══╝  ██║      ██╔══██║${RED}               ║${RESET}"
  echo -e "${RED}${BOLD}║  ${WHITE}╚═╝╚═╝╚══════╝       ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝${RED}               ║${RESET}"
  echo -e "${RED}${BOLD}║                                                                      ║${RESET}"
  echo -e "${RED}${BOLD}║   ${WHITE}${BOLD}DESTROY — Demo AI Platform  │  ROSA Layer${RESET}${RED}${BOLD}                        ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}https://www.iistech.com/${RESET}${RED}${BOLD}                                          ║${RESET}"
  echo -e "${RED}${BOLD}║                                                                      ║${RESET}"
  echo -e "${RED}${BOLD}║   ${YELLOW}Destroys:${RESET}${RED}${BOLD}                                                          ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  IAM IRSA roles (S3, Bedrock, Aurora)${RESET}${RED}${BOLD}                          ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  ROSA HCP Cluster  (rhoai-demo)${RESET}${RED}${BOLD}                                ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  Worker + GPU machine pools${RESET}${RED}${BOLD}                                    ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  ROSA operator IAM roles${RESET}${RED}${BOLD}                                       ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  OIDC config  (prompted)${RESET}${RED}${BOLD}                                       ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  ROSA account roles  (prompted)${RESET}${RED}${BOLD}                                ║${RESET}"
  echo -e "${RED}${BOLD}║                                                                      ║${RESET}"
  echo -e "${RED}${BOLD}║   ${YELLOW}Does NOT destroy: VPC · Aurora · S3 · EFS · ECR · Lambda${RESET}${RED}${BOLD}          ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}Run rhoai-destroy-demo-platform-aws.sh for those${RESET}${RED}${BOLD}                    ║${RESET}"
  echo -e "${RED}${BOLD}║                                                                      ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}Run: ${TIMESTAMP}${RESET}${RED}${BOLD}                                    ║${RESET}"
  echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

section() {
  echo ""
  echo -e "${CYAN}${BOLD}┌──────────────────────────────────────────────────────────────────────┐${RESET}"
  printf "${CYAN}${BOLD}│  %-68s│${RESET}\n" "$1"
  echo -e "${CYAN}${BOLD}└──────────────────────────────────────────────────────────────────────┘${RESET}"
}

step_info() { echo -e "  ${BLUE}➤${RESET}  $1"; }

step_ok() {
  echo -e "  ${GREEN}✔${RESET}  ${GREEN}$1${RESET}"
  STEPS_PASSED=$((STEPS_PASSED + 1))
  SUMMARY_LINES+=("${GREEN}  ✔  $1${RESET}")
}

step_warn() {
  echo -e "  ${YELLOW}⚠${RESET}  ${YELLOW}$1${RESET}"
  STEPS_WARNED=$((STEPS_WARNED + 1))
  SUMMARY_LINES+=("${YELLOW}  ⚠  $1${RESET}")
}

step_fail() {
  echo -e "  ${RED}✘${RESET}  ${RED}$1${RESET}"
  STEPS_FAILED=$((STEPS_FAILED + 1))
  SUMMARY_LINES+=("${RED}  ✘  $1${RESET}")
}

abort() {
  echo ""
  echo -e "${RED}${BOLD}╔══ FATAL ════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${RED}${BOLD}║  $1${RESET}"
  echo -e "${RED}${BOLD}╚═════════════════════════════════════════════════════════════════════════╝${RESET}"
  print_summary
  exit 1
}

confirm() {
  echo ""
  echo -e "${YELLOW}${BOLD}  ?  $1${RESET}"
  printf "     ${YELLOW}Enter [y/N]: ${RESET}"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

confirm_danger() {
  echo ""
  echo -e "${RED}${BOLD}  ⚠  WARNING: $1${RESET}"
  echo -e "${RED}     This action is IRREVERSIBLE.${RESET}"
  echo -e "${YELLOW}     Type exactly 'destroy' to confirm: ${RESET}\c"
  read -r answer
  [[ "$answer" == "destroy" ]]
}

print_summary() {
  echo ""
  echo -e "${WHITE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${WHITE}${BOLD}║         IIS TECH — ROSA DESTROY RUN SUMMARY                         ║${RESET}"
  echo -e "${WHITE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  for line in "${SUMMARY_LINES[@]}"; do echo -e "$line"; done
  echo ""
  echo -e "  ${GREEN}${BOLD}Completed : ${STEPS_PASSED}${RESET}     ${YELLOW}${BOLD}Warnings : ${STEPS_WARNED}${RESET}     ${RED}${BOLD}Failed : ${STEPS_FAILED}${RESET}"
  echo ""
  if [[ $STEPS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ✔  ROSA layer destroyed successfully.${RESET}"
  else
    echo -e "${RED}${BOLD}  ✘  ${STEPS_FAILED} step(s) failed — review errors above.${RESET}"
  fi
  echo ""
  echo -e "${DIM}  Logs : ${LOG_DIR}/${RESET}"
  echo -e "${DIM}  IIS Tech — https://www.iistech.com/${RESET}"
  echo ""
}

mkdir -p "$LOG_DIR"

# =============================================================================
print_banner
# =============================================================================

# ── Safety gate ───────────────────────────────────────────────────────────────
echo -e "${RED}${BOLD}  This script will PERMANENTLY DESTROY the ROSA cluster and related resources.${RESET}"
echo -e "${RED}  Cluster   : ${CLUSTER_NAME}${RESET}"
echo -e "${RED}  AWS Acct  : 406337554361${RESET}"
echo -e "${RED}  Region    : us-east-1${RESET}"

if ! confirm_danger "You are about to destroy the ROSA HCP cluster '${CLUSTER_NAME}'"; then
  echo ""
  echo -e "${YELLOW}  Destroy cancelled — no changes made.${RESET}"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
section "PRE-FLIGHT — AWS + ROSA AUTH"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Refreshing AWS SSO (profile: ${AWS_PROFILE})..."
aws sso login --profile "$AWS_PROFILE" 2>&1
[[ $? -eq 0 ]] && step_ok "AWS SSO login succeeded" || abort "AWS SSO login failed"

export AWS_PROFILE="$AWS_PROFILE"
aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null \
  && step_ok "AWS identity confirmed" \
  || abort "Cannot verify AWS identity"

step_info "Checking ROSA / OCM authentication..."
WHOAMI_OUT=$(rosa whoami 2>&1)
if echo "$WHOAMI_OUT" | grep -q "OCM Account Email"; then
  OCM_EMAIL=$(echo "$WHOAMI_OUT" | grep "OCM Account Email" | awk '{print $NF}')
  step_ok "OCM authenticated — ${OCM_EMAIL}"
else
  step_warn "ROSA not authenticated — logging in..."
  if [[ -n "${RHCS_TOKEN}" ]]; then
    rosa login --token="${RHCS_TOKEN}" 2>&1
  else
    echo -e "  ${YELLOW}  Get token: https://console.redhat.com/openshift/token${RESET}"
    printf "  ${YELLOW}${BOLD}  Paste Red Hat offline token: ${RESET}"
    read -r ROSA_TOKEN_INPUT
    [[ -z "$ROSA_TOKEN_INPUT" ]] && abort "No token provided"
    rosa login --token="${ROSA_TOKEN_INPUT}" 2>&1
    export RHCS_TOKEN="$ROSA_TOKEN_INPUT"
  fi
  rosa whoami 2>&1 | grep -q "OCM Account Email" \
    && step_ok "OCM authenticated" \
    || abort "ROSA login failed"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 1 — TERRAFORM DESTROY (IAM IRSA + ROSA CLUSTER)"
# ─────────────────────────────────────────────────────────────────────────────

cd "$REPO_PATH" || abort "Cannot navigate to ${REPO_PATH}"

step_info "Running terraform init -reconfigure..."
terraform init -reconfigure &>/dev/null \
  && step_ok "terraform init succeeded" \
  || abort "terraform init failed"

DESTROY_LOG="${LOG_DIR}/destroy-rosa_${TIMESTAMP}.log"
step_info "Running targeted terraform destroy..."
echo -e "     ${DIM}Targets: module.iam_irsa, module.rosa${RESET}"
echo -e "     ${DIM}Log: ${DESTROY_LOG}${RESET}"
echo ""

terraform destroy \
  -target=module.rosa.rhcs_hcp_machine_pool.gpu \
  -target=module.rosa.rhcs_hcp_machine_pool.workers \
  -target=module.rosa.rhcs_cluster_rosa_hcp.this \
  -target=module.iam_irsa \
  2>&1 | tee "$DESTROY_LOG"
TF_DESTROY_RC=${PIPESTATUS[0]}

echo ""
# Check for errors even if exit code is 0
DESTROY_ERRORS=$(grep -c "^│ Error:" "$DESTROY_LOG" 2>/dev/null | tr -d ' ' || echo 0)
DESTROY_ERRORS=${DESTROY_ERRORS:-0}

if [[ $TF_DESTROY_RC -eq 0 ]] && (( DESTROY_ERRORS == 0 )); then
  DESTROY_SUMMARY=$(grep "^Destroy complete!" "$DESTROY_LOG" | tail -1)
  step_ok "Terraform destroy succeeded — ${DESTROY_SUMMARY}"
else
  step_fail "Terraform destroy reported errors — see: ${DESTROY_LOG}"
  grep -A4 "^│ Error:" "$DESTROY_LOG" 2>/dev/null | head -30
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 2 — ROSA OPERATOR ROLES CLEANUP"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Checking for ROSA operator roles to clean up..."
OPERATOR_ROLES=$(rosa list operator-roles 2>&1 | grep "$CLUSTER_NAME" || true)

if [[ -n "$OPERATOR_ROLES" ]]; then
  step_warn "Found operator roles for cluster '${CLUSTER_NAME}'"
  echo "$OPERATOR_ROLES" | head -10

  if confirm "Delete ROSA operator roles for cluster '${CLUSTER_NAME}'?"; then
    CLUSTER_ID=$(rosa describe cluster -c "$CLUSTER_NAME" \
      --output json 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

    if [[ -n "$CLUSTER_ID" ]]; then
      rosa delete operator-roles -c "$CLUSTER_ID" --mode auto --yes 2>&1 \
        && step_ok "Operator roles deleted" \
        || step_warn "Operator role deletion had errors — check manually"
    else
      step_warn "Could not determine cluster ID — delete manually:"
      echo -e "     ${DIM}rosa delete operator-roles -c <cluster-id> --mode auto --yes${RESET}"
    fi
  else
    step_warn "Operator roles skipped — delete manually later if needed"
  fi
else
  step_ok "No operator roles found for '${CLUSTER_NAME}'"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 3 — OIDC CONFIG (OPTIONAL CLEANUP)"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Checking OIDC config: ${OIDC_CONFIG_ID}..."
OIDC_LIST=$(rosa list oidc-config 2>&1)

if echo "$OIDC_LIST" | grep -q "$OIDC_CONFIG_ID"; then
  step_warn "OIDC config '${OIDC_CONFIG_ID}' exists"
  echo -e "     ${DIM}Note: You can reuse this OIDC config for future cluster deploys${RESET}"

  if confirm "Delete OIDC config '${OIDC_CONFIG_ID}'? (choose No to reuse it later)"; then
    rosa delete oidc-config --oidc-config-id "$OIDC_CONFIG_ID" --yes 2>&1 \
      && step_ok "OIDC config deleted" \
      || step_warn "OIDC config deletion failed — delete manually:"
    echo -e "     ${DIM}rosa delete oidc-config --oidc-config-id ${OIDC_CONFIG_ID} --yes${RESET}"
  else
    step_ok "OIDC config retained — reuse in next deploy: oidc_config_id = \"${OIDC_CONFIG_ID}\""
  fi
else
  step_ok "OIDC config not found — already deleted or not created"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 4 — ROSA ACCOUNT ROLES (OPTIONAL CLEANUP)"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Checking ROSA account roles (prefix: ${ACCOUNT_ROLE_PREFIX})..."
ACCT_ROLES=$(rosa list account-roles 2>&1 | grep "$ACCOUNT_ROLE_PREFIX" || true)

if [[ -n "$ACCT_ROLES" ]]; then
  step_warn "Found account roles with prefix '${ACCOUNT_ROLE_PREFIX}'"
  echo "$ACCT_ROLES" | head -8
  echo ""
  echo -e "     ${DIM}Note: Account roles can be reused across cluster deploys${RESET}"

  if confirm "Delete ROSA account roles (prefix: '${ACCOUNT_ROLE_PREFIX}')? (choose No to reuse)"; then
    rosa delete account-roles \
      --prefix "$ACCOUNT_ROLE_PREFIX" \
      --mode auto \
      --yes 2>&1 \
      && step_ok "Account roles deleted" \
      || step_warn "Account role deletion had errors — check manually"
  else
    step_ok "Account roles retained — reuse in next deploy with prefix: ${ACCOUNT_ROLE_PREFIX}"
  fi
else
  step_ok "No account roles found with prefix '${ACCOUNT_ROLE_PREFIX}'"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 5 — VERIFY CLUSTER REMOVED"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Verifying cluster '${CLUSTER_NAME}' no longer exists..."
sleep 5
CLUSTER_CHECK=$(rosa describe cluster -c "$CLUSTER_NAME" 2>&1)

if echo "$CLUSTER_CHECK" | grep -qiE "There is no cluster|not found|uninstalling"; then
  step_ok "Cluster '${CLUSTER_NAME}' confirmed removed"
elif echo "$CLUSTER_CHECK" | grep -qi "uninstalling"; then
  step_warn "Cluster is uninstalling — takes 5-10 mins to fully remove"
  echo -e "     ${DIM}Monitor: rosa describe cluster -c ${CLUSTER_NAME}${RESET}"
else
  STATE=$(echo "$CLUSTER_CHECK" | grep "^State:" | awk '{print $2}')
  step_warn "Cluster state: ${STATE:-unknown} — may still be uninstalling"
  echo -e "     ${DIM}Monitor: rosa describe cluster -c ${CLUSTER_NAME}${RESET}"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "NEXT STEPS"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${WHITE}  To redeploy the ROSA cluster:${RESET}"
echo -e "${DIM}    ./rhoai-deploy-demo-platform-rosa.sh${RESET}"
echo ""
echo -e "${WHITE}  To destroy ALL infrastructure (VPC, Aurora, S3, EFS, ECR):${RESET}"
echo -e "${DIM}    ./rhoai-destroy-demo-platform-aws.sh${RESET}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
print_summary
# ─────────────────────────────────────────────────────────────────────────────
