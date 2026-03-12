#!/usr/bin/env zsh
# =============================================================================
#  IIS Tech — Demo AI Platform on AWS  │  Platform Layer
#  Platform AWS — AWS Infrastructure Layer (VPC, Aurora, S3, EFS, ECR, Lambda, Budgets)
#  https://www.iistech.com/
#
#  Usage:  chmod +x rhoai-deploy.sh && ./rhoai-deploy.sh
#  Covers: Phase 0 Pre-flight → Phase 1 terraform init → terraform plan → apply
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

# ── Config — edit if paths or profile change ──────────────────────────────────
AWS_PROFILE="rhoai-demo"
REPO_PATH="$HOME/GitHub/rhoai-demo-iac/environments/demo"
TFVARS_FILE="terraform.tfvars"
OIDC_CONFIG_ID="2ovm1pcngkss9e6stmbirbefljiiuptk"
LOG_DIR="$HOME/GitHub/rhoai-demo-iac/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# ── Tracking ──────────────────────────────────────────────────────────────────
STEPS_PASSED=0
STEPS_FAILED=0
STEPS_WARNED=0
SUMMARY_LINES=()

# ── Helper: persist token to shell rc file and export to current session ──────
persist_and_export_token() {
  local TOKEN="$1"
  local SHELL_RC=""

  # Detect shell rc file
  if [[ -n "$ZSH_VERSION" || "$SHELL" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
  elif [[ -n "$BASH_VERSION" || "$SHELL" == */bash ]]; then
    SHELL_RC="$HOME/.bash_profile"
  else
    SHELL_RC="$HOME/.profile"
  fi

  # Export in current session immediately
  export RHCS_TOKEN="$TOKEN"
  export ROSA_TOKEN="$TOKEN"
  step_ok "RHCS_TOKEN + ROSA_TOKEN exported in current session"

  # Remove any existing RHCS_TOKEN / ROSA_TOKEN lines from rc file
  if [[ -f "$SHELL_RC" ]]; then
    local TMPFILE=$(mktemp)
    grep -v "^export RHCS_TOKEN=" "$SHELL_RC" | grep -v "^export ROSA_TOKEN=" > "$TMPFILE"
    mv "$TMPFILE" "$SHELL_RC"
  fi

  # Append fresh values
  {
    echo ""
    echo "# IIS Tech — rhoai-demo-iac — Red Hat offline token (updated $(date '+%Y-%m-%d %H:%M'))"
    echo "export RHCS_TOKEN="${TOKEN}""
    echo "export ROSA_TOKEN="${TOKEN}""
  } >> "$SHELL_RC"

  step_ok "Token persisted to ${SHELL_RC} — future sessions will auto-authenticate"
}

# ── Helpers ───────────────────────────────────────────────────────────────────
print_banner() {
  clear
  echo ""
  echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
  echo -e "${BLUE}${BOLD}║  ${RED}██╗██╗███████╗    ████████╗███████╗ ██████╗ ██╗  ██╗${BLUE}               ║${RESET}"
  echo -e "${BLUE}${BOLD}║  ${RED}██║██║██╔════╝    ╚══██╔══╝██╔════╝██╔════╝ ██║  ██║${BLUE}               ║${RESET}"
  echo -e "${BLUE}${BOLD}║  ${RED}██║██║███████╗       ██║   █████╗  ██║      ███████║${BLUE}               ║${RESET}"
  echo -e "${BLUE}${BOLD}║  ${RED}██║██║╚════██║       ██║   ██╔══╝  ██║      ██╔══██║${BLUE}               ║${RESET}"
  echo -e "${BLUE}${BOLD}║  ${RED}╚═╝╚═╝╚══════╝       ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝${BLUE}               ║${RESET}"
  echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${WHITE}${BOLD}Demo AI Platform on AWS  │  Platform Layer${RESET}${BLUE}${BOLD}                        ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}https://www.iistech.com/${RESET}${BLUE}${BOLD}                                          ║${RESET}"
  echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${CYAN}Installs:${RESET}${BLUE}${BOLD}                                                          ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  VPC  (public + private subnets, NAT GW, IGW)${RESET}${BLUE}${BOLD}                  ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  Aurora PostgreSQL Serverless v2 + pgvector${RESET}${BLUE}${BOLD}                    ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  S3 Data Lake bucket${RESET}${BLUE}${BOLD}                                           ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  EFS Shared Storage${RESET}${BLUE}${BOLD}                                            ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  ECR Repositories (notebook, langchain, lambda)${RESET}${BLUE}${BOLD}                ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  Lambda Cost Scheduler (weekday auto start/stop)${RESET}${BLUE}${BOLD}               ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  SSM Parameter Store (secrets)${RESET}${BLUE}${BOLD}                                 ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  AWS Budgets alert (monthly cap \$700)${RESET}${BLUE}${BOLD}                          ║${RESET}"
  echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${YELLOW}Next: rhoai-deploy-demo-platform-rosa.sh${RESET}${BLUE}${BOLD}                           ║${RESET}"
  echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}Run: ${TIMESTAMP}${RESET}${BLUE}${BOLD}                                    ║${RESET}"
  echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

section() {
  echo ""
  echo -e "${CYAN}${BOLD}┌──────────────────────────────────────────────────────────────────────┐${RESET}"
  printf "${CYAN}${BOLD}│  %-68s│${RESET}\n" "$1"
  echo -e "${CYAN}${BOLD}└──────────────────────────────────────────────────────────────────────┘${RESET}"
}

step_info()  { echo -e "  ${BLUE}➤${RESET}  $1"; }

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
  echo -e "${RED}${BOLD}╔══ FATAL ERROR ══════════════════════════════════════════════════════════╗${RESET}"
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

print_summary() {
  echo ""
  echo -e "${WHITE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${WHITE}${BOLD}║              IIS TECH — DEPLOYMENT RUN SUMMARY                      ║${RESET}"
  echo -e "${WHITE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  for line in "${SUMMARY_LINES[@]}"; do
    echo -e "$line"
  done
  echo ""
  echo -e "  ${GREEN}${BOLD}Passed : ${STEPS_PASSED}${RESET}     ${YELLOW}${BOLD}Warnings : ${STEPS_WARNED}${RESET}     ${RED}${BOLD}Failed : ${STEPS_FAILED}${RESET}"
  echo ""
  if [[ $STEPS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ✔  All critical steps passed.${RESET}"
  else
    echo -e "${RED}${BOLD}  ✘  ${STEPS_FAILED} step(s) failed — review errors above before re-running.${RESET}"
  fi
  echo ""
  echo -e "${DIM}  Full logs: ${LOG_DIR}/${RESET}"
  echo -e "${DIM}  IIS Tech   https://www.iistech.com/${RESET}"
  echo ""
}

# ── Create log dir ────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

# =============================================================================
print_banner
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
section "PHASE 0.1 — REQUIRED TOOLS CHECK"
# ─────────────────────────────────────────────────────────────────────────────

ABORT_MISSING=false
for tool in aws terraform rosa git; do
  if command -v "$tool" &>/dev/null; then
    VER=$("$tool" --version 2>&1 | head -1)
    step_ok "$tool   →  $VER"
  else
    step_fail "$tool not found — install before continuing"
    ABORT_MISSING=true
  fi
done

[[ "$ABORT_MISSING" == "true" ]] && abort "Missing required tools. Install them and re-run."

# ─────────────────────────────────────────────────────────────────────────────
section "PHASE 0.2 — AWS SSO AUTHENTICATION  (profile: ${AWS_PROFILE})"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Opening browser for SSO login — complete it then return here..."
echo ""

if aws sso login --profile "$AWS_PROFILE"; then
  step_ok "AWS SSO login succeeded"
else
  abort "AWS SSO login failed. Verify profile '${AWS_PROFILE}' in ~/.aws/config"
fi

step_info "Verifying AWS caller identity..."
IDENTITY_JSON=$(aws sts get-caller-identity --profile "$AWS_PROFILE" 2>&1)
if [[ $? -eq 0 ]]; then
  ACCOUNT=$(echo "$IDENTITY_JSON" | grep -o '"Account": "[^"]*"' | awk -F'"' '{print $4}')
  ARN=$(echo "$IDENTITY_JSON"     | grep -o '"Arn": "[^"]*"'     | awk -F'"' '{print $4}')
  step_ok "Identity confirmed"
  echo -e "     ${DIM}Account : ${ACCOUNT}${RESET}"
  echo -e "     ${DIM}Role    : ${ARN}${RESET}"
else
  abort "Could not get caller identity. SSO token may be expired — re-run the script."
fi

export AWS_PROFILE="$AWS_PROFILE"
step_ok "AWS_PROFILE exported → ${AWS_PROFILE}"

# ─────────────────────────────────────────────────────────────────────────────
section "PHASE 0.3 — ROSA / OCM AUTHENTICATION"
# ─────────────────────────────────────────────────────────────────────────────

# Export RHCS_TOKEN from env if already set (set before running script)
if [[ -n "${RHCS_TOKEN}" ]]; then
  step_ok "RHCS_TOKEN already set in environment — Terraform rhcs provider will use it"
elif [[ -n "${ROSA_TOKEN}" ]]; then
  export RHCS_TOKEN="${ROSA_TOKEN}"
  step_ok "RHCS_TOKEN set from ROSA_TOKEN env var"
else
  step_warn "RHCS_TOKEN not set — will prompt for token if rosa auth fails"
  echo -e "     ${DIM}Tip: export RHCS_TOKEN=<offline-token> before running this script${RESET}"
  echo -e "     ${DIM}     https://console.redhat.com/openshift/token${RESET}"
fi

step_info "Checking ROSA CLI..."
ROSA_VER=$(rosa version 2>&1)
ROSA_VER_NUM=$(echo "$ROSA_VER" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ -n "$ROSA_VER_NUM" ]]; then
  step_ok "ROSA CLI installed — v${ROSA_VER_NUM}"
else
  step_fail "ROSA CLI not found. Install: brew install rosa-cli"
fi

step_info "Checking OCM authentication (rosa whoami)..."
WHOAMI_OUT=$(rosa whoami 2>&1)
if echo "$WHOAMI_OUT" | grep -q "OCM Account Email"; then
  OCM_EMAIL=$(echo "$WHOAMI_OUT" | grep "OCM Account Email"    | awk '{print $NF}')
  OCM_ORG=$(echo "$WHOAMI_OUT"   | grep "OCM Organization Name" | cut -d: -f2- | xargs)
  step_ok "OCM authenticated — ${OCM_EMAIL}"
  echo -e "     ${DIM}Org: ${OCM_ORG}${RESET}"
else
  step_warn "ROSA not authenticated — attempting login..."

  # Check environment variable first
  if [[ -n "${ROSA_TOKEN}" ]]; then
    step_info "Found ROSA_TOKEN in environment — using it..."
    rosa login --token="${ROSA_TOKEN}" 2>&1
  else
    # Not in env — prompt the user
    echo ""
    echo -e "  ${YELLOW}  No ROSA_TOKEN environment variable found.${RESET}"
    echo -e "  ${DIM}  Get your offline token: https://console.redhat.com/openshift/token${RESET}"
    echo ""
    printf "  ${YELLOW}${BOLD}  Paste your Red Hat offline token: ${RESET}"
    read -r ROSA_TOKEN_INPUT

    if [[ -z "$ROSA_TOKEN_INPUT" ]]; then
      step_fail "No token provided — skipping ROSA login"
      echo -e "     ${DIM}To fix later: export RHCS_TOKEN=<token> then re-run${RESET}"
    else
      step_info "Running: rosa login --token=****"
      rosa login --token="${ROSA_TOKEN_INPUT}" 2>&1
    fi
  fi

  # Re-verify after login attempt
  WHOAMI_OUT=$(rosa whoami 2>&1)
  if echo "$WHOAMI_OUT" | grep -q "OCM Account Email"; then
    OCM_EMAIL=$(echo "$WHOAMI_OUT" | grep "OCM Account Email"     | awk '{print $NF}')
    OCM_ORG=$(echo "$WHOAMI_OUT"   | grep "OCM Organization Name" | cut -d: -f2- | xargs)
    step_ok "OCM authenticated — ${OCM_EMAIL}"
    echo -e "     ${DIM}Org: ${OCM_ORG}${RESET}"
    # Persist + export token for current session AND future runs
    local ACTIVE_TOKEN="${ROSA_TOKEN_INPUT:-${ROSA_TOKEN}}"
    if [[ -n "$ACTIVE_TOKEN" ]]; then
      persist_and_export_token "$ACTIVE_TOKEN"
    fi
  else
    step_fail "ROSA login failed — token may be invalid or expired"
    echo -e "     ${DIM}Get a fresh token: https://console.redhat.com/openshift/token${RESET}"
  fi
fi

step_info "Verifying OIDC config ID: ${OIDC_CONFIG_ID}..."
OIDC_LIST=$(rosa list oidc-config 2>&1)
if echo "$OIDC_LIST" | grep -q "$OIDC_CONFIG_ID"; then
  step_ok "OIDC config confirmed — ${OIDC_CONFIG_ID}"
else
  step_warn "OIDC config '${OIDC_CONFIG_ID}' not found — verify in tfvars"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "PHASE 0.4 — REPO & TFVARS VALIDATION"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Navigating to: ${REPO_PATH}"
if cd "$REPO_PATH" 2>/dev/null; then
  step_ok "Directory confirmed: $(pwd)"
else
  abort "Path not found: ${REPO_PATH}\nUpdate REPO_PATH at the top of this script."
fi

step_info "Checking ${TFVARS_FILE}..."
if [[ -f "$TFVARS_FILE" ]]; then
  LINE_COUNT=$(wc -l < "$TFVARS_FILE" | tr -d ' ')
  step_ok "terraform.tfvars found (${LINE_COUNT} lines)"
  echo ""
  echo -e "  ${DIM}  Key values:${RESET}"
  for KEY in project_name environment aws_region rosa_cluster_name ocp_version \
             worker_instance_type oidc_config_id account_role_prefix budget_alert_email; do
    VAL=$(grep "^${KEY}" "$TFVARS_FILE" 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' "' | head -1)
    if [[ -n "$VAL" ]]; then
      printf "     ${DIM}%-30s = %s${RESET}\n" "$KEY" "$VAL"
    else
      step_warn "Key '${KEY}' missing or empty in tfvars"
    fi
  done
else
  abort "terraform.tfvars not found in $(pwd)\nRun: cp terraform.tfvars.example terraform.tfvars && edit it."
fi

step_info "Checking git status..."
if git rev-parse --git-dir &>/dev/null; then
  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached HEAD")
  COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commits")
  step_ok "Git repo active — branch: ${BRANCH}"
  echo -e "     ${DIM}Last commit: ${COMMIT}${RESET}"
else
  step_warn "Not inside a git repository"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "PHASE 1.1 — TERRAFORM INIT"
# ─────────────────────────────────────────────────────────────────────────────

INIT_LOG="${LOG_DIR}/init_${TIMESTAMP}.log"
step_info "Running: terraform init -reconfigure"
echo -e "     ${DIM}Log: ${INIT_LOG}${RESET}"
echo ""

terraform init -reconfigure 2>&1 | tee "$INIT_LOG"
TF_INIT_RC=${PIPESTATUS[0]}

echo ""
if [[ $TF_INIT_RC -eq 0 ]]; then
  MOD_COUNT=$(grep -c "^- " "$INIT_LOG" 2>/dev/null | tr -d ' ' || echo 0)
  PRV_COUNT=$(grep -c "^- Installed " "$INIT_LOG" 2>/dev/null | tr -d ' ' || echo 0)
  step_ok "terraform init succeeded  (modules: ${MOD_COUNT}  providers: ${PRV_COUNT})"
else
  step_fail "terraform init failed — see: ${INIT_LOG}"
  abort "Cannot proceed without successful terraform init."
fi

# ─────────────────────────────────────────────────────────────────────────────
section "PHASE 1.2 — TERRAFORM PLAN"
# ─────────────────────────────────────────────────────────────────────────────

PLAN_LOG="${LOG_DIR}/plan_${TIMESTAMP}.log"
step_info "Running: terraform plan -out=tfplan"
echo -e "     ${DIM}This may take 1-3 minutes...${RESET}"
echo -e "     ${DIM}Log: ${PLAN_LOG}${RESET}"
echo ""

terraform plan -out=tfplan 2>&1 | tee "$PLAN_LOG"
TF_PLAN_RC=${PIPESTATUS[0]}

echo ""
if [[ $TF_PLAN_RC -eq 0 ]]; then
  PLAN_SUMMARY=$(grep -E "^Plan:|^No changes\." "$PLAN_LOG" | tail -1)
  step_ok "terraform plan succeeded"
  echo -e "     ${WHITE}${BOLD}${PLAN_SUMMARY}${RESET}"

  WARN_COUNT=$(grep -c "Warning:" "$PLAN_LOG" 2>/dev/null | tr -d " " || echo 0)
  WARN_COUNT=${WARN_COUNT:-0}
  (( WARN_COUNT > 0 )) && step_warn "${WARN_COUNT} warning(s) in plan — review log before applying"
else
  step_fail "terraform plan failed"
  echo ""
  echo -e "${RED}  ── Error excerpt ──────────────────────────────────────────────${RESET}"
  grep -A3 "│ Error:" "$PLAN_LOG" 2>/dev/null | head -30
  echo -e "${RED}  ────────────────────────────────────────────────────────────────${RESET}"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "PHASE 1.3 — TERRAFORM APPLY (OPTIONAL)"
# ─────────────────────────────────────────────────────────────────────────────

if [[ $TF_PLAN_RC -eq 0 && $STEPS_FAILED -eq 0 ]]; then
  echo ""
  echo -e "${WHITE}  Plan file saved → ${REPO_PATH}/tfplan${RESET}"
  echo -e "${WHITE}  Review the plan output above carefully.${RESET}"
  echo -e "${YELLOW}  ${BOLD}WARNING: Apply will create real AWS resources and incur costs.${RESET}"

  if confirm "Run terraform apply now?"; then
    APPLY_LOG="${LOG_DIR}/apply_${TIMESTAMP}.log"

    # ── Helper: re-auth ROSA and retry apply on token expiry ─────────────────
    run_apply_with_retry() {
      local attempt=1
      local max_attempts=3

      while (( attempt <= max_attempts )); do
        step_info "terraform apply — attempt ${attempt} of ${max_attempts}"
        echo -e "     ${DIM}Log: ${APPLY_LOG}${RESET}"
        echo ""

        terraform apply tfplan 2>&1 | tee "$APPLY_LOG"
        local RC=${PIPESTATUS[0]}

        # ── Scan log for resource-level errors (exit 0 but errors present) ──
        local RESOURCE_ERRORS=$(grep -c "^│ Error:" "$APPLY_LOG" 2>/dev/null | tr -d " " || echo 0)
        RESOURCE_ERRORS=${RESOURCE_ERRORS:-0}

        # ── Check for ROSA / OCM token expiry ───────────────────────────────
        if grep -qiE "invalid_grant|invalid refresh token|can.t get access token|token.*expired" "$APPLY_LOG"; then
          echo ""
          step_warn "ROSA/OCM token expired mid-apply — re-authenticating..."

          # Try env var first, then prompt
          if [[ -n "${ROSA_TOKEN}" ]]; then
            step_info "Re-logging in with ROSA_TOKEN env var..."
            rosa login --token="${ROSA_TOKEN}" 2>&1
          else
            echo ""
            echo -e "  ${YELLOW}  ROSA token expired. Get a fresh token from:${RESET}"
            echo -e "  ${DIM}  https://console.redhat.com/openshift/token${RESET}"
            echo ""
            printf "  ${YELLOW}${BOLD}  Paste your Red Hat offline token: ${RESET}"
            read -r ROSA_TOKEN_INPUT
            if [[ -n "$ROSA_TOKEN_INPUT" ]]; then
              step_info "Running: rosa login --token=****"
              rosa login --token="${ROSA_TOKEN_INPUT}" 2>&1
            else
              step_fail "No token provided — cannot retry apply"
              return 1
            fi
          fi

          # Re-verify auth before retry
          if rosa whoami 2>&1 | grep -q "OCM Account Email"; then
            step_ok "ROSA re-authenticated — retrying apply..."
            # Export RHCS_TOKEN so the rhcs Terraform provider picks it up
            # Persist + export refreshed token for current session AND future runs
            local ACTIVE_TOKEN="${ROSA_TOKEN_INPUT:-${ROSA_TOKEN}}"
            if [[ -n "$ACTIVE_TOKEN" ]]; then
              persist_and_export_token "$ACTIVE_TOKEN"
            fi
            # Refresh AWS SSO too if near expiry
            aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null || {
              step_warn "AWS SSO token also expired — refreshing..."
              aws sso login --profile "$AWS_PROFILE"
            }
            attempt=$(( attempt + 1 ))
            continue
          else
            step_fail "ROSA re-authentication failed — aborting apply"
            return 1
          fi
        fi

        # ── Apply exit code failed (non-token error) ─────────────────────────
        if [[ $RC -ne 0 ]]; then
          step_fail "terraform apply failed (exit ${RC}) — see: ${APPLY_LOG}"
          echo ""
          echo -e "${RED}  ── Error Details ────────────────────────────────────────────────${RESET}"
          grep -A5 "^│ Error:" "$APPLY_LOG" 2>/dev/null | head -40
          echo -e "${RED}  ─────────────────────────────────────────────────────────────────${RESET}"
          return 1
        fi

        # ── Apply exit 0 but resource errors in log ──────────────────────────
        if (( RESOURCE_ERRORS > 0 )); then
          step_fail "terraform apply reported ${RESOURCE_ERRORS} resource error(s) — see: ${APPLY_LOG}"
          echo ""
          echo -e "${RED}  ── Resource Errors ──────────────────────────────────────────────${RESET}"
          grep -A6 "^│ Error:" "$APPLY_LOG" 2>/dev/null | head -50
          echo -e "${RED}  ─────────────────────────────────────────────────────────────────${RESET}"
          return 1
        fi

        # ── Genuine success ──────────────────────────────────────────────────
        local APPLY_SUMMARY=$(grep "^Apply complete!" "$APPLY_LOG" | tail -1)
        step_ok "terraform apply succeeded — ${APPLY_SUMMARY}"
        return 0
      done

      step_fail "terraform apply failed after ${max_attempts} attempts"
      return 1
    }

    run_apply_with_retry
    APPLY_FINAL_RC=$?
    [[ $APPLY_FINAL_RC -ne 0 ]] && step_fail "Apply did not complete successfully — review logs in ${LOG_DIR}"

  else
    echo ""
    echo -e "${YELLOW}  Apply skipped. To apply later:${RESET}"
    echo -e "${WHITE}    cd ${REPO_PATH}${RESET}"
    echo -e "${WHITE}    terraform apply tfplan${RESET}"
  fi
else
  step_warn "Apply skipped — fix the failures above first, then re-run."
fi

# ─────────────────────────────────────────────────────────────────────────────
print_summary
# ─────────────────────────────────────────────────────────────────────────────