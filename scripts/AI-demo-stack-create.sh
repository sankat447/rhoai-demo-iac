#!/usr/bin/env bash
# =============================================================================
#  IIS Tech — Demo AI Platform on AWS  │  Full Stack Provisioning
#  https://www.iistech.com/
#
#  Usage   : ./scripts/AI-demo-stack-create.sh
#  Covers  : AWS Platform Layer + ROSA HCP Cluster + IAM IRSA
#  Duration: ~30-35 minutes
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
ENV_DIR="${ROOT_DIR}/environments/demo"
LOG_DIR="${ROOT_DIR}/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/stack-create_${TIMESTAMP}.log"

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
ACCOUNT_ROLE_PREFIX="rhoai-demo"
AWS_REGION="us-east-1"
OIDC_CONFIG_ID="2p4ru24skdhahlddjliu19fl90bm9927"

# ── Tracking ──────────────────────────────────────────────────────────────────
STEPS_PASSED=0
STEPS_FAILED=0
STEPS_WARNED=0
SUMMARY_LINES=()

# ── Helpers ───────────────────────────────────────────────────────────────────
log()       { echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
log_ok()    { echo -e "  ${GREEN}✔${RESET}  ${GREEN}$*${RESET}" | tee -a "${LOG_FILE}"; STEPS_PASSED=$((STEPS_PASSED+1)); SUMMARY_LINES+=("${GREEN}  ✔  $*${RESET}"); }
log_warn()  { echo -e "  ${YELLOW}⚠${RESET}  ${YELLOW}$*${RESET}" | tee -a "${LOG_FILE}"; STEPS_WARNED=$((STEPS_WARNED+1)); SUMMARY_LINES+=("${YELLOW}  ⚠  $*${RESET}"); }
log_fail()  { echo -e "  ${RED}✘${RESET}  ${RED}$*${RESET}" | tee -a "${LOG_FILE}"; STEPS_FAILED=$((STEPS_FAILED+1)); SUMMARY_LINES+=("${RED}  ✘  $*${RESET}"); }
log_info()  { echo -e "  ${BLUE}➤${RESET}  $*" | tee -a "${LOG_FILE}"; }

section() {
  echo "" | tee -a "${LOG_FILE}"
  echo -e "${CYAN}${BOLD}┌──────────────────────────────────────────────────────────────────────┐${RESET}" | tee -a "${LOG_FILE}"
  printf "${CYAN}${BOLD}│  %-68s│${RESET}\n" "$1" | tee -a "${LOG_FILE}"
  echo -e "${CYAN}${BOLD}└──────────────────────────────────────────────────────────────────────┘${RESET}" | tee -a "${LOG_FILE}"
}

abort() {
  echo "" | tee -a "${LOG_FILE}"
  echo -e "${RED}${BOLD}╔══ FATAL ERROR ══════════════════════════════════════════════════════════╗${RESET}" | tee -a "${LOG_FILE}"
  echo -e "${RED}${BOLD}║  $1${RESET}" | tee -a "${LOG_FILE}"
  echo -e "${RED}${BOLD}╚═════════════════════════════════════════════════════════════════════════╝${RESET}" | tee -a "${LOG_FILE}"
  print_summary
  exit 1
}

confirm() {
  echo ""
  echo -e "${YELLOW}${BOLD}  ?  $1${RESET}"
  printf "     ${YELLOW}Enter [y/N]: ${RESET}"
  read -r _answer
  [[ "$_answer" =~ ^[Yy]$ ]]
}

print_summary() {
  echo ""
  echo -e "${WHITE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${WHITE}${BOLD}║        IIS TECH — AI DEMO STACK CREATE — RUN SUMMARY                 ║${RESET}"
  echo -e "${WHITE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  for line in "${SUMMARY_LINES[@]}"; do echo -e "$line"; done
  echo ""
  echo -e "  ${GREEN}${BOLD}Passed : ${STEPS_PASSED}${RESET}     ${YELLOW}${BOLD}Warnings : ${STEPS_WARNED}${RESET}     ${RED}${BOLD}Failed : ${STEPS_FAILED}${RESET}"
  echo ""
  if [[ $STEPS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ✔  All critical steps passed.${RESET}"
  else
    echo -e "${RED}${BOLD}  ✘  ${STEPS_FAILED} step(s) failed — review errors above before re-running.${RESET}"
  fi
  echo ""
  echo -e "${DIM}  Full log : ${LOG_FILE}${RESET}"
  echo -e "${DIM}  IIS Tech : https://www.iistech.com/${RESET}"
  echo ""
}

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
    echo "# IIS Tech — rhoai-demo-iac — RHCS token for Terraform provider (updated $(date '+%Y-%m-%d %H:%M'))"
    echo "export RHCS_TOKEN=\"${TOKEN}\""
    echo "export ROSA_TOKEN=\"${TOKEN}\""
  } >> "$SHELL_RC"
  log_ok "RHCS_TOKEN persisted to ${SHELL_RC}"
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${RED}██╗██╗███████╗    ████████╗███████╗ ██████╗ ██╗  ██╗${BLUE}               ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${RED}██║██║██╔════╝    ╚══██╔══╝██╔════╝██╔════╝ ██║  ██║${BLUE}               ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${RED}██║██║███████╗       ██║   █████╗  ██║      ███████║${BLUE}               ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${RED}██║██║╚════██║       ██║   ██╔══╝  ██║      ██╔══██║${BLUE}               ║${RESET}"
echo -e "${BLUE}${BOLD}║  ${RED}╚═╝╚═╝╚══════╝       ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝${BLUE}               ║${RESET}"
echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${WHITE}${BOLD}Demo AI Platform on AWS  │  Full Stack Provisioning${RESET}${BLUE}${BOLD}             ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}https://www.iistech.com/${RESET}${BLUE}${BOLD}                                          ║${RESET}"
echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${CYAN}Provisions:${RESET}${BLUE}${BOLD}                                                       ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  VPC · Aurora PostgreSQL Serverless v2 + pgvector${RESET}${BLUE}${BOLD}              ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  S3 · EFS · ECR · Lambda Scheduler · SSM · Budgets${RESET}${BLUE}${BOLD}             ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  ROSA HCP Cluster (OCP 4.17) + worker + GPU pools${RESET}${BLUE}${BOLD}              ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  IAM IRSA roles (S3, Bedrock, Aurora, ECR)${RESET}${BLUE}${BOLD}                    ║${RESET}"
echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${GREEN}Duration: ~30-35 minutes${RESET}${BLUE}${BOLD}                                          ║${RESET}"
echo -e "${BLUE}${BOLD}║   ${DIM}Run: ${TIMESTAMP}${RESET}${BLUE}${BOLD}                                    ║${RESET}"
echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
log "Log file: ${LOG_FILE}"

# =============================================================================
section "PHASE 0.1 — REQUIRED TOOLS CHECK"
# =============================================================================

ABORT_MISSING=false
for tool in aws terraform rosa oc git jq; do
  if command -v "$tool" &>/dev/null; then
    if [[ "$tool" == "rosa" || "$tool" == "oc" ]]; then
      VER=$(timeout 5 "$tool" version 2>&1 | head -1 || echo "(version check timeout)")
    else
      VER=$(timeout 5 "$tool" --version 2>&1 | head -1 || echo "(version check timeout)")
    fi
    log_ok "$tool  →  $VER"
  else
    log_fail "$tool not found"
    ABORT_MISSING=true
  fi
done

[[ "$ABORT_MISSING" == "true" ]] && abort "Missing required tools. Install: brew install awscli terraform rosa-cli openshift-cli jq"

# =============================================================================
section "PHASE 0.2 — AWS SSO AUTHENTICATION  (profile: ${AWS_PROFILE})"
# =============================================================================

log_info "Checking AWS SSO session..."
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
  log_warn "AWS SSO session expired — logging in..."
  aws sso login --profile "$AWS_PROFILE" || abort "AWS SSO login failed. Verify profile '${AWS_PROFILE}' in ~/.aws/config"
fi

IDENTITY_JSON=$(aws sts get-caller-identity --profile "$AWS_PROFILE" 2>&1)
ACCOUNT=$(echo "$IDENTITY_JSON" | grep -o '"Account": "[^"]*"' | awk -F'"' '{print $4}')
ARN=$(echo "$IDENTITY_JSON"     | grep -o '"Arn": "[^"]*"'     | awk -F'"' '{print $4}')
log_ok "AWS authenticated — Account: ${ACCOUNT}"
echo -e "     ${DIM}Role: ${ARN}${RESET}"
export AWS_PROFILE

# =============================================================================
section "PHASE 0.3 — ROSA / OCM AUTHENTICATION"
# =============================================================================

# ── rosa CLI login (Red Hat SSO — browser-based) ──────────────────────────────
# Offline token login is deprecated by Red Hat. rosa login now uses SSO.
log_info "Checking OCM authentication (rosa whoami)..."
WHOAMI_OUT=$(rosa whoami 2>&1)
if echo "$WHOAMI_OUT" | grep -q "OCM Account Email"; then
  OCM_EMAIL=$(echo "$WHOAMI_OUT" | grep "OCM Account Email" | awk '{print $NF}')
  log_ok "OCM authenticated — ${OCM_EMAIL}"
else
  log_warn "ROSA not authenticated — launching Red Hat SSO login..."
  echo -e "     ${DIM}A browser window will open for Red Hat SSO. Complete login then return here.${RESET}"
  echo ""
  rosa login --use-auth-code || abort "ROSA login failed — ensure you have a Red Hat account at https://console.redhat.com"

  WHOAMI_OUT=$(rosa whoami 2>&1)
  if echo "$WHOAMI_OUT" | grep -q "OCM Account Email"; then
    OCM_EMAIL=$(echo "$WHOAMI_OUT" | grep "OCM Account Email" | awk '{print $NF}')
    log_ok "OCM authenticated — ${OCM_EMAIL}"
  else
    abort "ROSA login failed — check your Red Hat account at https://console.redhat.com"
  fi
fi

# ── RHCS_TOKEN for Terraform rhcs provider ────────────────────────────────────
# The rhcs Terraform provider still requires a token. Obtain it from the active
# rosa CLI session (no manual copy/paste needed after SSO login).
if [[ -z "${RHCS_TOKEN:-}" ]]; then
  log_info "Obtaining RHCS_TOKEN from active rosa session for Terraform provider..."
  RHCS_TOKEN_FROM_ROSA=$(rosa token 2>/dev/null || echo "")
  if [[ -n "$RHCS_TOKEN_FROM_ROSA" ]]; then
    persist_and_export_token "$RHCS_TOKEN_FROM_ROSA"
  else
    log_warn "Could not obtain token from rosa session — Terraform rhcs provider may fail"
    echo -e "     ${DIM}If apply fails with auth errors, run: export RHCS_TOKEN=\$(rosa token)${RESET}"
  fi
else
  log_ok "RHCS_TOKEN already set in environment — Terraform rhcs provider ready"
fi

log_info "Verifying OIDC config ID: ${OIDC_CONFIG_ID}..."
if rosa list oidc-config 2>&1 | grep -q "$OIDC_CONFIG_ID"; then
  log_ok "OIDC config confirmed — ${OIDC_CONFIG_ID}"
else
  log_warn "OIDC config '${OIDC_CONFIG_ID}' not found — creating a new one..."
  OIDC_CREATE_OUT=$(rosa create oidc-config --managed --yes --mode auto --region "${AWS_REGION}" 2>&1)
  NEW_OIDC_ID=$(echo "$OIDC_CREATE_OUT" | grep -oP "oidc-provider/[^/]+/\K[a-z0-9]+" | head -1)

  if [[ -z "$NEW_OIDC_ID" ]]; then
    # Fallback: grab the newest OIDC config from the list
    NEW_OIDC_ID=$(rosa list oidc-config 2>/dev/null | tail -1 | awk '{print $1}')
  fi

  if [[ -n "$NEW_OIDC_ID" ]]; then
    log_ok "Created new OIDC config: ${NEW_OIDC_ID}"

    # Update the hardcoded ID in this script for current run
    OLD_OIDC_CONFIG_ID="$OIDC_CONFIG_ID"
    OIDC_CONFIG_ID="$NEW_OIDC_ID"

    # Persist the new ID into terraform.tfvars and this script
    sed -i '' "s|oidc_config_id.*=.*\"${OLD_OIDC_CONFIG_ID}\"|oidc_config_id      = \"${NEW_OIDC_ID}\"|" "${ENV_DIR}/terraform.tfvars"
    log_ok "Updated terraform.tfvars with new OIDC config ID"

    sed -i '' "s|OIDC_CONFIG_ID=\"${OLD_OIDC_CONFIG_ID}\"|OIDC_CONFIG_ID=\"${NEW_OIDC_ID}\"|" "${SCRIPT_DIR}/AI-demo-stack-create.sh"
    sed -i '' "s|${OLD_OIDC_CONFIG_ID}|${NEW_OIDC_ID}|g" "${SCRIPT_DIR}/AI-demo-stack-destroy.sh"
    log_ok "Updated script files with new OIDC config ID"
  else
    abort "Failed to create OIDC config — check 'rosa create oidc-config' output"
  fi
fi

# ── Verify operator role trust policies match the OIDC config ──────────────
log_info "Checking operator role trust policies match OIDC config..."
OIDC_MISMATCH=false
OIDC_ISSUER_URL=$(rosa list oidc-config 2>/dev/null | grep "$OIDC_CONFIG_ID" | awk '{print $3}' | sed 's|https://||')

for ROLE_NAME in $(aws iam list-roles --query "Roles[?starts_with(RoleName, '${ACCOUNT_ROLE_PREFIX}-') && contains(RoleName, '-openshift-') || starts_with(RoleName, '${ACCOUNT_ROLE_PREFIX}-kube-')].RoleName" --output text 2>/dev/null); do
  TRUST_POLICY=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.AssumeRolePolicyDocument" --output json 2>/dev/null)
  if echo "$TRUST_POLICY" | grep -q "oidc" && ! echo "$TRUST_POLICY" | grep -q "$OIDC_CONFIG_ID"; then
    OIDC_MISMATCH=true
    OLD_OIDC_IN_ROLE=$(echo "$TRUST_POLICY" | grep -o 'oidc\.op1\.openshiftapps\.com/[a-z0-9]*' | head -1 | awk -F'/' '{print $NF}')
    if [[ -z "$OLD_OIDC_IN_ROLE" ]]; then
      OLD_OIDC_IN_ROLE=$(echo "$TRUST_POLICY" | grep -o 'rh-oidc\.s3\.[^/]*/[a-z0-9]*' | head -1 | awk -F'/' '{print $NF}')
    fi
    log_warn "Role ${ROLE_NAME} trusts old OIDC: ${OLD_OIDC_IN_ROLE}"
    if [[ -z "$OLD_OIDC_IN_ROLE" ]]; then
      log_warn "  Could not extract old OIDC ID from trust policy — skipping ${ROLE_NAME}"
      continue
    fi
    NEW_TRUST=$(echo "$TRUST_POLICY" | sed "s|${OLD_OIDC_IN_ROLE}|${OIDC_CONFIG_ID}|g")
    aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$NEW_TRUST" 2>/dev/null \
      && log_ok "  Updated trust policy for ${ROLE_NAME}" \
      || log_warn "  Failed to update trust policy for ${ROLE_NAME}"
  fi
done

if [[ "$OIDC_MISMATCH" == "false" ]]; then
  log_ok "All operator roles trust the correct OIDC provider"
fi

# =============================================================================
section "PHASE 0.4 — REPO & TFVARS VALIDATION"
# =============================================================================

cd "$ENV_DIR" || abort "Cannot navigate to ${ENV_DIR}"
log_ok "Working directory: $(pwd)"

if [[ -f "terraform.tfvars" ]]; then
  LINE_COUNT=$(wc -l < terraform.tfvars | tr -d ' ')
  log_ok "terraform.tfvars found (${LINE_COUNT} lines)"
  for KEY in project_name environment aws_region rosa_cluster_name ocp_version \
             worker_instance_type oidc_config_id account_role_prefix budget_alert_email; do
    VAL=$(grep "^${KEY}" terraform.tfvars 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' "' | head -1)
    [[ -n "$VAL" ]] && printf "     ${DIM}%-30s = %s${RESET}\n" "$KEY" "$VAL" \
                    || log_warn "Key '${KEY}' missing or empty in terraform.tfvars"
  done
else
  abort "terraform.tfvars not found in $(pwd)\nRun: cp terraform.tfvars.example terraform.tfvars && edit it."
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "detached HEAD")
COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commits")
log_ok "Git branch: ${BRANCH}  |  ${COMMIT}"

# =============================================================================
section "PHASE 1.1 — TERRAFORM INIT"
# =============================================================================

INIT_LOG="${LOG_DIR}/init_${TIMESTAMP}.log"
log_info "Running: terraform init -reconfigure"
echo -e "     ${DIM}Log: ${INIT_LOG}${RESET}"
echo ""

terraform init -reconfigure 2>&1 | tee "$INIT_LOG"
TF_INIT_RC=${PIPESTATUS[0]}

echo ""
if [[ $TF_INIT_RC -eq 0 ]]; then
  log_ok "terraform init succeeded"
else
  log_fail "terraform init failed — see: ${INIT_LOG}"
  abort "Cannot proceed without successful terraform init."
fi

# =============================================================================
section "PHASE 1.2 — TERRAFORM PLAN"
# =============================================================================

PLAN_LOG="${LOG_DIR}/plan_${TIMESTAMP}.log"
log_info "Running: terraform plan -out=tfplan"
echo -e "     ${DIM}Log: ${PLAN_LOG}${RESET}"
echo ""

terraform plan -out=tfplan 2>&1 | tee "$PLAN_LOG" || true
TF_PLAN_RC=${PIPESTATUS[0]}

echo "" || true
if [[ $TF_PLAN_RC -eq 0 ]]; then
  PLAN_SUMMARY=$(grep -E "^Plan:|^No changes\." "$PLAN_LOG" | tail -1)
  log_ok "terraform plan succeeded"
  echo -e "     ${WHITE}${BOLD}${PLAN_SUMMARY}${RESET}"
  WARN_COUNT=$(grep -c "Warning:" "$PLAN_LOG" 2>/dev/null | tr -d ' ' || echo 0)
  (( ${WARN_COUNT:-0} > 0 )) && log_warn "${WARN_COUNT} warning(s) in plan — review log before applying"
else
  log_fail "terraform plan failed"
  echo ""
  echo -e "${RED}  ── Error excerpt ──────────────────────────────────────────────${RESET}"
  grep -A3 "│ Error:" "$PLAN_LOG" 2>/dev/null | head -30
  echo -e "${RED}  ────────────────────────────────────────────────────────────────${RESET}"
  abort "Fix plan errors and re-run."
fi

# =============================================================================
section "PHASE 1.3 — TERRAFORM APPLY  (AWS + ROSA)"
# =============================================================================

echo ""
echo -e "${YELLOW}${BOLD}  ⚠  This will create real AWS resources and incur costs.${RESET}"
echo -e "${YELLOW}     Estimated: ~\$2/hr (~\$50/day) with cluster running${RESET}"
echo ""
log_info "Refreshing ROSA token before apply to prevent mid-apply expiry..."
NEW_TOKEN=$(rosa token 2>/dev/null || echo "")
if [[ -n "$NEW_TOKEN" ]]; then
  persist_and_export_token "$NEW_TOKEN"
  log_ok "Token refreshed successfully"
else
  log_warn "Could not refresh token — proceeding anyway"
fi
echo ""
log_info "Auto-proceeding with terraform apply..."
echo ""

# ── Apply with token-expiry retry ─────────────────────────────────────────────
run_apply_with_retry() {
  local attempt=1
  local max_attempts=3
  local APPLY_LOG="${LOG_DIR}/apply_${TIMESTAMP}.log"

  while (( attempt <= max_attempts )); do
    log_info "terraform apply — attempt ${attempt} of ${max_attempts}"
    echo -e "     ${DIM}Log: ${APPLY_LOG}${RESET}"
    echo ""

    terraform apply tfplan 2>&1 | tee "$APPLY_LOG"
    local RC=${PIPESTATUS[0]}

    local RESOURCE_ERRORS
    RESOURCE_ERRORS=$(grep -c "^│ Error:" "$APPLY_LOG" 2>/dev/null | tr -d ' ' || echo 0)
    RESOURCE_ERRORS=${RESOURCE_ERRORS:-0}

    # ── Token expiry mid-apply ───────────────────────────────────────────────
    if grep -qiE "invalid_grant|invalid refresh token|can.t get access token|token.*expired" "$APPLY_LOG"; then
      echo ""
      log_warn "ROSA/OCM token expired mid-apply — re-authenticating via SSO..."
      echo -e "     ${DIM}A browser window will open for Red Hat SSO. Complete login then return here.${RESET}"

      rosa login --use-auth-code || { log_fail "ROSA re-login failed — aborting apply"; return 1; }

      if rosa whoami 2>&1 | grep -q "OCM Account Email"; then
        # Refresh RHCS_TOKEN from the new SSO session for the rhcs provider
        NEW_TOKEN=$(rosa token 2>/dev/null || echo "")
        [[ -n "$NEW_TOKEN" ]] && persist_and_export_token "$NEW_TOKEN"
        log_ok "ROSA re-authenticated — retrying apply..."
        # Refresh AWS SSO if also near expiry
        aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null || {
          log_warn "AWS SSO also expired — refreshing..."
          aws sso login --profile "$AWS_PROFILE"
        }
        # Re-plan to avoid "Saved plan is stale" error after partial apply
        log_info "Re-generating plan after token refresh..."
        terraform plan -out=tfplan -var "rhcs_token=${RHCS_TOKEN}" 2>&1 | tail -5
        log_ok "Plan refreshed"
        attempt=$(( attempt + 1 ))
        continue
      else
        log_fail "ROSA re-authentication failed — aborting"
        return 1
      fi
    fi

    # ── Non-zero exit (non-token error) ─────────────────────────────────────
    if [[ $RC -ne 0 ]]; then
      log_fail "terraform apply failed (exit ${RC}) — see: ${APPLY_LOG}"
      echo ""
      echo -e "${RED}  ── Error Details ────────────────────────────────────────────────${RESET}"
      grep -A5 "^│ Error:" "$APPLY_LOG" 2>/dev/null | head -40
      echo -e "${RED}  ─────────────────────────────────────────────────────────────────${RESET}"
      return 1
    fi

    # ── Exit 0 but resource errors in log (false success guard) ─────────────
    if (( RESOURCE_ERRORS > 0 )); then
      log_fail "terraform apply reported ${RESOURCE_ERRORS} resource error(s) — see: ${APPLY_LOG}"
      echo ""
      grep -A6 "^│ Error:" "$APPLY_LOG" 2>/dev/null | head -50
      return 1
    fi

    # ── Genuine success ──────────────────────────────────────────────────────
    local APPLY_SUMMARY
    APPLY_SUMMARY=$(grep "^Apply complete!" "$APPLY_LOG" | tail -1)
    log_ok "terraform apply succeeded — ${APPLY_SUMMARY}"
    return 0
  done

  log_fail "terraform apply failed after ${max_attempts} attempts"
  return 1
}

run_apply_with_retry
APPLY_RC=$?

[[ $APPLY_RC -ne 0 ]] && abort "Apply did not complete successfully — review logs in ${LOG_DIR}"

# =============================================================================
section "PHASE 2 — CLUSTER READINESS CHECK"
# =============================================================================

log_info "Waiting for ROSA cluster '${CLUSTER_NAME}' to reach 'ready' state..."
echo -e "     ${DIM}Polling every 60s — ROSA HCP typically takes 15-25 minutes${RESET}"
echo ""

WAIT_MINUTES=0
MAX_WAIT=35
CLUSTER_STATE="unknown"

while (( WAIT_MINUTES < MAX_WAIT )); do
  DESCRIBE_OUT=$(rosa describe cluster -c "$CLUSTER_NAME" 2>/dev/null || echo "")
  CLUSTER_STATE=$(echo "$DESCRIBE_OUT" | grep -iE "^State:" | awk '{print tolower($2)}' | tr -d '[:space:]')
  CLUSTER_STATE="${CLUSTER_STATE:-unknown}"

  printf "  ${BLUE}[%02d min]${RESET}  State: ${WHITE}%-15s${RESET}\n" "$WAIT_MINUTES" "$CLUSTER_STATE"

  case "$CLUSTER_STATE" in
    ready)
      log_ok "Cluster '${CLUSTER_NAME}' is READY 🎉"
      break
      ;;
    error|degraded|uninstalling)
      log_fail "Cluster entered state: ${CLUSTER_STATE}"
      echo "$DESCRIBE_OUT" | grep -iE "State|Reason|Message|Condition" | head -10
      break
      ;;
    installing|waiting|validating|initializing|pending)
      # Normal provisioning states — keep polling
      ;;
    unknown)
      log_warn "Could not retrieve cluster state — checking ROSA auth..."
      if ! rosa whoami &>/dev/null; then
        log_warn "ROSA session expired — re-authenticating via SSO..."
        rosa login --use-auth-code 2>/dev/null || true
        NEW_TOKEN=$(rosa token 2>/dev/null || echo "")
        [[ -n "$NEW_TOKEN" ]] && persist_and_export_token "$NEW_TOKEN"
      fi
      ;;
  esac

  sleep 60
  WAIT_MINUTES=$(( WAIT_MINUTES + 1 ))
done

if [[ "$CLUSTER_STATE" != "ready" && $WAIT_MINUTES -ge $MAX_WAIT ]]; then
  log_warn "Cluster not ready after ${MAX_WAIT} minutes — check manually:"
  echo -e "     ${WHITE}rosa describe cluster -c ${CLUSTER_NAME}${RESET}"
fi

# =============================================================================
section "PHASE 2.5 — REFRESH OUTPUTS (ROSA API & CONSOLE URLs)"
# =============================================================================

log_info "Refreshing Terraform state to populate ROSA outputs..."
echo ""

# Refresh token one more time to ensure state refresh succeeds
NEW_TOKEN=$(rosa token 2>/dev/null || echo "")
if [[ -n "$NEW_TOKEN" ]]; then
  persist_and_export_token "$NEW_TOKEN"
fi

# Run terraform apply to sync newly uncommented outputs
if terraform apply -auto-approve 2>&1 | tee -a "${LOG_FILE}"; then
  log_ok "Terraform state refreshed — outputs populated"
else
  log_warn "Terraform apply for output refresh had issues — attempting manual refresh"
  terraform refresh 2>&1 | tee -a "${LOG_FILE}" || true
fi

echo ""

# =============================================================================
section "PHASE 3 — POST-DEPLOY SUMMARY"
# =============================================================================

API_URL=$(terraform output -raw rosa_api_url     2>/dev/null || echo "")
CONSOLE_URL=$(terraform output -raw rosa_console_url 2>/dev/null || echo "")
VPC_ID=$(terraform output -raw vpc_id            2>/dev/null || echo "")
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
AURORA_EP=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")

[[ -n "$VPC_ID"     ]] && log_ok "VPC        : ${VPC_ID}"
[[ -n "$S3_BUCKET"  ]] && log_ok "S3 Bucket  : ${S3_BUCKET}"
[[ -n "$AURORA_EP"  ]] && log_ok "Aurora     : ${AURORA_EP}"
[[ -n "$API_URL"    ]] && log_ok "API URL    : ${API_URL}"
[[ -n "$CONSOLE_URL" ]] && log_ok "Console    : ${CONSOLE_URL}"

# =============================================================================
section "PHASE 4 — CLUSTER ADMIN SETUP"
# =============================================================================

log_info "Cleaning up old cluster admin..."
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
  log_warn "Failed to create cluster admin — you can create it manually later"
  echo "$ADMIN_OUTPUT"
fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║                    PROVISIONING COMPLETE  🎉                         ║${RESET}"
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

print_summary
