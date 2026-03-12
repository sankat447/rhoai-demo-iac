#!/usr/bin/env zsh
# =============================================================================
#  IIS Tech — Demo AI Platform on AWS + ROSA
#  Platform ROSA — ROSA HCP Cluster + IAM IRSA + Cluster Readiness
#  https://www.iistech.com/
#
#  Prerequisites : rhoai-deploy-demo-platform-aws.sh complete
#  Usage         : chmod +x rhoai-deploy-demo-phase2.sh && ./rhoai-deploy-demo-phase2.sh
#
#  Covers:
#    Step 1  — Aurora pgvector initialisation
#    Step 2  — IAM permissions pre-check for ROSA
#    Step 3  — ROSA account-roles creation (rhoai-demo prefix)
#    Step 4  — OIDC config verification / creation
#    Step 5  — terraform.tfvars update
#    Step 6  — Uncomment ROSA modules in main.tf
#    Step 7  — terraform init + plan + apply (ROSA + IAM IRSA)
#    Step 8  — Cluster readiness wait + post-deploy validation
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
MAIN_TF="$HOME/GitHub/rhoai-demo-iac/environments/demo/../../main.tf"
MODULES_PATH="$HOME/GitHub/rhoai-demo-iac"
TFVARS_FILE="terraform.tfvars"
LOG_DIR="$HOME/GitHub/rhoai-demo-iac/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Known Phase 1 outputs (update if yours differ)
CLUSTER_NAME="rhoai-demo"
ACCOUNT_ROLE_PREFIX="rhoai-demo"
AWS_REGION="us-east-1"
AWS_ACCOUNT="406337554361"
AURORA_HOST="rhoai-demo-demo-db.cluster-cidweltunfq6.us-east-1.rds.amazonaws.com"
AURORA_USER="rhoai_admin"
AURORA_DB="rhoai_demo"
SSM_DB_PASS_PATH="/rhoai-demo-demo/aurora/master-password"

# ── Tracking ──────────────────────────────────────────────────────────────────
STEPS_PASSED=0
STEPS_FAILED=0
STEPS_WARNED=0
SUMMARY_LINES=()

# ── Helper: persist token to shell rc + current session ──────────────────────
persist_and_export_token() {
  local TOKEN="$1"
  local SHELL_RC=""
  if [[ -n "$ZSH_VERSION" || "$SHELL" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
  elif [[ -n "$BASH_VERSION" || "$SHELL" == */bash ]]; then
    SHELL_RC="$HOME/.bash_profile"
  else
    SHELL_RC="$HOME/.profile"
  fi
  export RHCS_TOKEN="$TOKEN"
  export ROSA_TOKEN="$TOKEN"
  step_ok "RHCS_TOKEN + ROSA_TOKEN exported in current session"
  if [[ -f "$SHELL_RC" ]]; then
    local TMPFILE=$(mktemp)
    grep -v "^export RHCS_TOKEN=" "$SHELL_RC" | grep -v "^export ROSA_TOKEN=" > "$TMPFILE"
    mv "$TMPFILE" "$SHELL_RC"
  fi
  {
    echo ""
    echo "# IIS Tech — rhoai-demo-iac — Red Hat offline token (updated $(date '+%Y-%m-%d %H:%M'))"
    echo "export RHCS_TOKEN=\"${TOKEN}\""
    echo "export ROSA_TOKEN=\"${TOKEN}\""
  } >> "$SHELL_RC"
  step_ok "Token persisted to ${SHELL_RC}"
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
  echo -e "${BLUE}${BOLD}║   ${WHITE}${BOLD}Demo AI Platform on AWS + ROSA  │  ROSA Layer${RESET}${BLUE}${BOLD}                      ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}https://www.iistech.com/${RESET}${BLUE}${BOLD}                                          ║${RESET}"
  echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${CYAN}Installs:${RESET}${BLUE}${BOLD}                                                          ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  Aurora pgvector schema init${RESET}${BLUE}${BOLD}                                   ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  ROSA account-roles (HCP, prefix: rhoai-demo)${RESET}${BLUE}${BOLD}                  ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  OIDC config (managed, HCP-compatible)${RESET}${BLUE}${BOLD}                         ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  ROSA HCP Cluster  (rhoai-demo, OCP 4.17)${RESET}${BLUE}${BOLD}                      ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  Worker node pool  (c5.2xlarge x2, auto-scale x4)${RESET}${BLUE}${BOLD}              ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  GPU node pool     (g4dn.xlarge, scale-to-zero)${RESET}${BLUE}${BOLD}                ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  IAM IRSA roles    (S3, Bedrock, Aurora access)${RESET}${BLUE}${BOLD}                ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${DIM}  ✦  Cluster readiness poll + oc login instructions${RESET}${BLUE}${BOLD}                ║${RESET}"
  echo -e "${BLUE}${BOLD}║                                                                      ║${RESET}"
  echo -e "${BLUE}${BOLD}║   ${YELLOW}Prerequisite: rhoai-deploy-demo-platform-aws.sh complete${RESET}${BLUE}${BOLD}           ║${RESET}"
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

print_summary() {
  echo ""
  echo -e "${WHITE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${WHITE}${BOLD}║         IIS TECH — PLATFORM ROSA DEPLOYMENT SUMMARY                   ║${RESET}"
  echo -e "${WHITE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  for line in "${SUMMARY_LINES[@]}"; do echo -e "$line"; done
  echo ""
  echo -e "  ${GREEN}${BOLD}Passed : ${STEPS_PASSED}${RESET}     ${YELLOW}${BOLD}Warnings : ${STEPS_WARNED}${RESET}     ${RED}${BOLD}Failed : ${STEPS_FAILED}${RESET}"
  echo ""
  if [[ $STEPS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ✔  Platform ROSA complete — ROSA cluster provisioned and ready.${RESET}"
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

# ─────────────────────────────────────────────────────────────────────────────
section "PHASE 2 PRE-FLIGHT — AWS + ROSA AUTH"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Refreshing AWS SSO (profile: ${AWS_PROFILE})..."
aws sso login --profile "$AWS_PROFILE" 2>&1
[[ $? -eq 0 ]] && step_ok "AWS SSO login succeeded" || abort "AWS SSO login failed"

IDENTITY=$(aws sts get-caller-identity --profile "$AWS_PROFILE" 2>&1)
[[ $? -eq 0 ]] && step_ok "AWS identity confirmed — account ${AWS_ACCOUNT}" \
                || abort "Cannot verify AWS identity"
export AWS_PROFILE="$AWS_PROFILE"

# RHCS_TOKEN check
if [[ -n "${RHCS_TOKEN}" ]]; then
  step_ok "RHCS_TOKEN found in environment"
elif [[ -n "${ROSA_TOKEN}" ]]; then
  export RHCS_TOKEN="${ROSA_TOKEN}"
  step_ok "RHCS_TOKEN set from ROSA_TOKEN"
else
  step_warn "RHCS_TOKEN not set — will prompt if needed"
  echo -e "     ${DIM}Tip: export RHCS_TOKEN=<token>  →  https://console.redhat.com/openshift/token${RESET}"
fi

# ROSA auth
step_info "Checking ROSA / OCM authentication..."
WHOAMI_OUT=$(rosa whoami 2>&1)
if echo "$WHOAMI_OUT" | grep -q "OCM Account Email"; then
  OCM_EMAIL=$(echo "$WHOAMI_OUT" | grep "OCM Account Email"    | awk '{print $NF}')
  step_ok "OCM authenticated — ${OCM_EMAIL}"
else
  step_warn "ROSA not authenticated — logging in..."
  if [[ -n "${RHCS_TOKEN}" ]]; then
    rosa login --token="${RHCS_TOKEN}" 2>&1
  else
    echo ""
    echo -e "  ${YELLOW}  Get token: https://console.redhat.com/openshift/token${RESET}"
    printf "  ${YELLOW}${BOLD}  Paste Red Hat offline token: ${RESET}"
    read -r ROSA_TOKEN_INPUT
    [[ -z "$ROSA_TOKEN_INPUT" ]] && abort "No token provided — cannot continue"
    rosa login --token="${ROSA_TOKEN_INPUT}" 2>&1
    persist_and_export_token "$ROSA_TOKEN_INPUT"
  fi
  WHOAMI_OUT=$(rosa whoami 2>&1)
  if echo "$WHOAMI_OUT" | grep -q "OCM Account Email"; then
    OCM_EMAIL=$(echo "$WHOAMI_OUT" | grep "OCM Account Email" | awk '{print $NF}')
    step_ok "OCM authenticated — ${OCM_EMAIL}"
  else
    abort "ROSA login failed — get fresh token from https://console.redhat.com/openshift/token"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 1 — AURORA pgvector INITIALISATION"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Retrieving Aurora master password from SSM..."
DB_PASS=$(aws ssm get-parameter \
  --name "$SSM_DB_PASS_PATH" \
  --with-decryption \
  --query Parameter.Value \
  --output text \
  --profile "$AWS_PROFILE" 2>&1)

if [[ $? -eq 0 && -n "$DB_PASS" ]]; then
  step_ok "DB password retrieved from SSM (${SSM_DB_PASS_PATH})"
else
  step_fail "Could not retrieve DB password from SSM: ${DB_PASS}"
  step_warn "Skipping pgvector init — fix SSM access and run manually"
  DB_PASS=""
fi

if [[ -n "$DB_PASS" ]]; then
  INIT_SQL="$HOME/GitHub/rhoai-demo-iac/modules/aurora-serverless/init.sql"
  step_info "Checking for init.sql at ${INIT_SQL}..."
  if [[ -f "$INIT_SQL" ]]; then
    step_info "Running pgvector init against Aurora..."
    PGPASSWORD="$DB_PASS" psql \
      "postgresql://${AURORA_USER}:${DB_PASS}@${AURORA_HOST}/${AURORA_DB}" \
      -f "$INIT_SQL" 2>&1

    if [[ $? -eq 0 ]]; then
      step_ok "Aurora pgvector initialised successfully"
    else
      step_warn "psql init returned errors — check Aurora security group allows access from this IP"
      echo -e "     ${DIM}Aurora SG may only allow access from within VPC — use AWS Session Manager or a bastion${RESET}"
    fi
  else
    step_warn "init.sql not found at ${INIT_SQL} — skipping pgvector init"
    echo -e "     ${DIM}Run manually when inside VPC:${RESET}"
    echo -e "     ${DIM}psql postgresql://${AURORA_USER}:\$DB_PASS@${AURORA_HOST}/${AURORA_DB} -f init.sql${RESET}"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 2 — IAM PERMISSIONS CHECK FOR ROSA"
# ─────────────────────────────────────────────────────────────────────────────

REQUIRED_IAM_ACTIONS=(
  "iam:CreateRole"
  "iam:AttachRolePolicy"
  "iam:PutRolePolicy"
  "iam:TagRole"
  "iam:ListRoleTags"
  "iam:GetRole"
  "iam:PassRole"
)

step_info "Checking IAM permissions for ROSA account-role creation..."
IAM_OK=true

# Test with a dry-run simulation
SIM_OUT=$(aws iam simulate-principal-policy \
  --policy-source-arn "${ARN:-arn:aws:sts::${AWS_ACCOUNT}:assumed-role/AWSReservedSSO_SystemAdministrator_9f7eac9c29583bb3/skumar}" \
  --action-names iam:CreateRole \
  --resource-arns "arn:aws:iam::${AWS_ACCOUNT}:role/*" \
  --profile "$AWS_PROFILE" 2>&1)

if echo "$SIM_OUT" | grep -q "allowed"; then
  step_ok "iam:CreateRole — ALLOWED"
elif echo "$SIM_OUT" | grep -q "implicitDeny\|explicitDeny"; then
  step_fail "iam:CreateRole — DENIED"
  IAM_OK=false
else
  step_warn "iam:CreateRole — could not simulate (SSO boundary) — attempting directly"
fi

if [[ "$IAM_OK" == "false" ]]; then
  echo ""
  echo -e "${YELLOW}${BOLD}  IAM permissions insufficient for ROSA account-role creation.${RESET}"
  echo -e "${WHITE}  Options:${RESET}"
  echo -e "${DIM}  A) Ask AWS admin to add iam:CreateRole etc. to SystemAdministrator SSO permission set${RESET}"
  echo -e "${DIM}  B) Create a temporary IAM user with AdministratorAccess (commands below)${RESET}"
  echo ""
  echo -e "${WHITE}  Option B — Temp IAM user:${RESET}"
  echo -e "${DIM}    aws iam create-user --user-name rosa-bootstrap-tmp${RESET}"
  echo -e "${DIM}    aws iam attach-user-policy --user-name rosa-bootstrap-tmp \\${RESET}"
  echo -e "${DIM}      --policy-arn arn:aws:iam::aws:policy/AdministratorAccess${RESET}"
  echo -e "${DIM}    aws iam create-access-key --user-name rosa-bootstrap-tmp${RESET}"
  echo -e "${DIM}    # Export the keys, complete ROSA steps, then delete the user${RESET}"
  echo ""
  if ! confirm "Proceed anyway and attempt ROSA role creation? (may fail without iam:CreateRole)"; then
    step_warn "ROSA account-role creation skipped — fix IAM then re-run this script"
    print_summary
    exit 0
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 3 — ROSA ACCOUNT ROLES CREATION"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Checking if account roles already exist (prefix: ${ACCOUNT_ROLE_PREFIX})..."
EXISTING_ROLES=$(rosa list account-roles 2>&1)
ROLE_COUNT=$(echo "$EXISTING_ROLES" | grep -c "$ACCOUNT_ROLE_PREFIX" 2>/dev/null | tr -d ' ' || echo 0)
ROLE_COUNT=${ROLE_COUNT:-0}

if (( ROLE_COUNT >= 4 )); then
  step_ok "Account roles already exist (${ROLE_COUNT} found with prefix '${ACCOUNT_ROLE_PREFIX}')"
  echo "$EXISTING_ROLES" | grep "$ACCOUNT_ROLE_PREFIX" | while read -r line; do
    echo -e "     ${DIM}${line}${RESET}"
  done
else
  step_info "Creating ROSA account roles (prefix: ${ACCOUNT_ROLE_PREFIX})..."
  ROLE_LOG="${LOG_DIR}/rosa-account-roles_${TIMESTAMP}.log"
  echo -e "     ${DIM}Log: ${ROLE_LOG}${RESET}"

  rosa create account-roles \
    --hosted-cp \
    --prefix "$ACCOUNT_ROLE_PREFIX" \
    --mode auto \
    --yes 2>&1 | tee "$ROLE_LOG"

  if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    step_ok "ROSA account roles created successfully"
    echo -e "     ${DIM}Roles created:${RESET}"
    echo -e "     ${DIM}  ${ACCOUNT_ROLE_PREFIX}-HCP-ROSA-Installer-Role${RESET}"
    echo -e "     ${DIM}  ${ACCOUNT_ROLE_PREFIX}-HCP-ROSA-Support-Role${RESET}"
    echo -e "     ${DIM}  ${ACCOUNT_ROLE_PREFIX}-HCP-ROSA-Worker-Role${RESET}"
    echo -e "     ${DIM}  ${ACCOUNT_ROLE_PREFIX}-HCP-ROSA-ControlPlane-Role${RESET}"
  else
    step_fail "ROSA account role creation failed — see: ${ROLE_LOG}"
    echo ""
    grep -i "error\|denied\|failed" "$ROLE_LOG" | head -10
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 4 — OIDC CONFIG VERIFICATION"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Listing OIDC configs..."
OIDC_LIST=$(rosa list oidc-config 2>&1)
CURRENT_OIDC=$(grep "oidc_config_id" "$REPO_PATH/$TFVARS_FILE" | awk -F'"' '{print $2}')

echo -e "     ${DIM}Current tfvars oidc_config_id: ${CURRENT_OIDC}${RESET}"

if echo "$OIDC_LIST" | grep -q "$CURRENT_OIDC"; then
  step_ok "OIDC config '${CURRENT_OIDC}' confirmed active"
else
  step_warn "OIDC config '${CURRENT_OIDC}' not found — creating new one..."

  NEW_OIDC_OUT=$(rosa create oidc-config --managed --yes 2>&1)
  NEW_OIDC_ID=$(echo "$NEW_OIDC_OUT" | grep -oE '[a-z0-9]{32}' | head -1)

  if [[ -n "$NEW_OIDC_ID" ]]; then
    step_ok "New OIDC config created: ${NEW_OIDC_ID}"
    step_info "Updating oidc_config_id in terraform.tfvars..."

    # Update tfvars in place
    sed -i.bak "s/oidc_config_id.*=.*/oidc_config_id      = \"${NEW_OIDC_ID}\"/" \
      "$REPO_PATH/$TFVARS_FILE"

    if grep -q "$NEW_OIDC_ID" "$REPO_PATH/$TFVARS_FILE"; then
      step_ok "terraform.tfvars updated with new OIDC ID: ${NEW_OIDC_ID}"
    else
      step_fail "Failed to update terraform.tfvars — update manually:"
      echo -e "     ${WHITE}oidc_config_id = \"${NEW_OIDC_ID}\"${RESET}"
    fi
  else
    step_fail "Could not create OIDC config — output: ${NEW_OIDC_OUT}"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 5 — UNCOMMENT ROSA MODULES IN main.tf"
# ─────────────────────────────────────────────────────────────────────────────

MAIN_TF_FILE="$REPO_PATH/main.tf"
step_info "Checking for commented-out ROSA modules in ${MAIN_TF_FILE}..."

if [[ ! -f "$MAIN_TF_FILE" ]]; then
  step_warn "main.tf not found at ${MAIN_TF_FILE}"
  echo -e "     ${DIM}Manually uncomment module \"rosa\" and module \"iam_irsa\" blocks${RESET}"
else
  # Check if rosa module is commented out
  ROSA_COMMENTED=$(grep -c "^#.*module.*rosa\|^# *module.*\"rosa\"" "$MAIN_TF_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  ROSA_ACTIVE=$(grep -c "^module.*\"rosa\"" "$MAIN_TF_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  IRSA_ACTIVE=$(grep -c "^module.*\"iam_irsa\"" "$MAIN_TF_FILE" 2>/dev/null | tr -d ' ' || echo 0)

  if (( ROSA_ACTIVE >= 1 )) && (( IRSA_ACTIVE >= 1 )); then
    step_ok "module \"rosa\" already active in main.tf"
    step_ok "module \"iam_irsa\" already active in main.tf"
  else
    step_warn "ROSA/IRSA modules may be commented out — opening main.tf for review..."
    echo ""
    echo -e "${WHITE}  Please ensure these two module blocks are uncommented in main.tf:${RESET}"
    echo -e "${DIM}    module \"rosa\"     { source = \"../../modules/rosa-hcp\" ... }${RESET}"
    echo -e "${DIM}    module \"iam_irsa\" { source = \"../../modules/iam-irsa\"  ... }${RESET}"
    echo ""

    if confirm "Open main.tf in VS Code now?"; then
      code "$MAIN_TF_FILE" && step_ok "VS Code opened — uncomment the modules and save"
      echo ""
      printf "  ${YELLOW}${BOLD}  Press Enter once you have saved main.tf: ${RESET}"
      read -r
    fi

    # Re-check after user edits
    ROSA_ACTIVE=$(grep -c "^module.*\"rosa\"" "$MAIN_TF_FILE" 2>/dev/null | tr -d ' ' || echo 0)
    IRSA_ACTIVE=$(grep -c "^module.*\"iam_irsa\"" "$MAIN_TF_FILE" 2>/dev/null | tr -d ' ' || echo 0)

    if (( ROSA_ACTIVE >= 1 )); then
      step_ok "module \"rosa\" confirmed active"
    else
      step_warn "module \"rosa\" still not detected — verify main.tf manually"
    fi
    if (( IRSA_ACTIVE >= 1 )); then
      step_ok "module \"iam_irsa\" confirmed active"
    else
      step_warn "module \"iam_irsa\" still not detected — verify main.tf manually"
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 6 — TERRAFORM INIT + PLAN"
# ─────────────────────────────────────────────────────────────────────────────

cd "$REPO_PATH" || abort "Cannot navigate to ${REPO_PATH}"

INIT_LOG="${LOG_DIR}/p2-init_${TIMESTAMP}.log"
PLAN_LOG="${LOG_DIR}/p2-plan_${TIMESTAMP}.log"

step_info "Running: terraform init -reconfigure"
echo -e "     ${DIM}Log: ${INIT_LOG}${RESET}"
echo ""

terraform init -reconfigure 2>&1 | tee "$INIT_LOG"
TF_INIT_RC=${PIPESTATUS[0]}

echo ""
if [[ $TF_INIT_RC -eq 0 ]]; then
  step_ok "terraform init succeeded"
else
  step_fail "terraform init failed — see: ${INIT_LOG}"
  abort "Cannot proceed without successful terraform init"
fi

step_info "Running: terraform plan -out=tfplan"
echo -e "     ${DIM}This may take 1-2 minutes...${RESET}"
echo -e "     ${DIM}Log: ${PLAN_LOG}${RESET}"
echo ""

terraform plan -out=tfplan 2>&1 | tee "$PLAN_LOG"
TF_PLAN_RC=${PIPESTATUS[0]}

echo ""
if [[ $TF_PLAN_RC -eq 0 ]]; then
  PLAN_SUMMARY=$(grep -E "^Plan:|^No changes\." "$PLAN_LOG" | tail -1)
  step_ok "terraform plan succeeded"
  echo -e "     ${WHITE}${BOLD}${PLAN_SUMMARY}${RESET}"
  WARN_COUNT=$(grep -c "Warning:" "$PLAN_LOG" 2>/dev/null | tr -d ' ' || echo 0)
  WARN_COUNT=${WARN_COUNT:-0}
  (( WARN_COUNT > 0 )) && step_warn "${WARN_COUNT} warning(s) in plan — review before applying"
else
  step_fail "terraform plan failed — see: ${PLAN_LOG}"
  echo ""
  grep -A5 "^│ Error:" "$PLAN_LOG" 2>/dev/null | head -40
  abort "Fix plan errors before applying"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 7 — TERRAFORM APPLY  (ROSA HCP CLUSTER)"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${YELLOW}${BOLD}  ⚠  ROSA HCP cluster creation takes 15-25 minutes.${RESET}"
echo -e "${YELLOW}     This will incur AWS + Red Hat costs.${RESET}"

if [[ $TF_PLAN_RC -eq 0 && $STEPS_FAILED -eq 0 ]]; then

  if confirm "Run terraform apply now to create the ROSA cluster?"; then

    # ── Apply with token-expiry retry ────────────────────────────────────────
    run_phase2_apply() {
      local attempt=1
      local max_attempts=3
      local APPLY_LOG="${LOG_DIR}/p2-apply_${TIMESTAMP}.log"

      while (( attempt <= max_attempts )); do
        step_info "terraform apply — attempt ${attempt} of ${max_attempts}"
        echo -e "     ${DIM}Log: ${APPLY_LOG}${RESET}"
        echo -e "     ${DIM}Cluster: ${CLUSTER_NAME}  Region: ${AWS_REGION}${RESET}"
        echo ""

        terraform apply tfplan 2>&1 | tee "$APPLY_LOG"
        local RC=${PIPESTATUS[0]}

        local RESOURCE_ERRORS=$(grep -c "^│ Error:" "$APPLY_LOG" 2>/dev/null | tr -d ' ' || echo 0)
        RESOURCE_ERRORS=${RESOURCE_ERRORS:-0}

        # ── Token expiry mid-apply ───────────────────────────────────────────
        if grep -qiE "invalid_grant|invalid refresh token|can.t get access token|token.*expired" "$APPLY_LOG"; then
          echo ""
          step_warn "ROSA/OCM token expired mid-apply — re-authenticating..."

          if [[ -n "${RHCS_TOKEN}" ]]; then
            step_info "Re-using RHCS_TOKEN env var..."
            rosa login --token="${RHCS_TOKEN}" 2>&1
          else
            echo ""
            echo -e "  ${YELLOW}  Get fresh token: https://console.redhat.com/openshift/token${RESET}"
            printf "  ${YELLOW}${BOLD}  Paste Red Hat offline token: ${RESET}"
            read -r ROSA_TOKEN_INPUT
            [[ -z "$ROSA_TOKEN_INPUT" ]] && { step_fail "No token — aborting apply"; return 1; }
            rosa login --token="${ROSA_TOKEN_INPUT}" 2>&1
            persist_and_export_token "$ROSA_TOKEN_INPUT"
          fi

          if rosa whoami 2>&1 | grep -q "OCM Account Email"; then
            step_ok "ROSA re-authenticated — retrying apply..."
            aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null || {
              step_warn "AWS SSO also expired — refreshing..."
              aws sso login --profile "$AWS_PROFILE"
            }
            attempt=$(( attempt + 1 ))
            continue
          else
            step_fail "ROSA re-authentication failed — aborting"
            return 1
          fi
        fi

        # ── Non-zero exit ────────────────────────────────────────────────────
        if [[ $RC -ne 0 ]]; then
          step_fail "terraform apply failed (exit ${RC})"
          echo ""
          echo -e "${RED}  ── Error Details ──────────────────────────────────────────────${RESET}"
          grep -A6 "^│ Error:" "$APPLY_LOG" 2>/dev/null | head -50
          echo -e "${RED}  ───────────────────────────────────────────────────────────────${RESET}"
          return 1
        fi

        # ── Resource errors despite exit 0 ──────────────────────────────────
        if (( RESOURCE_ERRORS > 0 )); then
          step_fail "Apply reported ${RESOURCE_ERRORS} resource error(s)"
          echo ""
          grep -A6 "^│ Error:" "$APPLY_LOG" 2>/dev/null | head -50
          return 1
        fi

        # ── Success ─────────────────────────────────────────────────────────
        local APPLY_SUMMARY=$(grep "^Apply complete!" "$APPLY_LOG" | tail -1)
        step_ok "terraform apply succeeded — ${APPLY_SUMMARY}"
        return 0
      done

      step_fail "Apply failed after ${max_attempts} attempts"
      return 1
    }

    run_phase2_apply
    APPLY_RC=$?

    # ─────────────────────────────────────────────────────────────────────────
    if [[ $APPLY_RC -eq 0 ]]; then

      section "STEP 8 — CLUSTER READINESS CHECK"

      step_info "Waiting for ROSA cluster to reach 'ready' state..."
      echo -e "     ${DIM}Polling every 60s — ROSA HCP typically takes 15-25 minutes total${RESET}"
      echo ""

      WAIT_MINUTES=0
      MAX_WAIT=35

      while (( WAIT_MINUTES < MAX_WAIT )); do
        # Try JSON first, fall back to plain text describe output
        DESCRIBE_OUT=$(rosa describe cluster -c "$CLUSTER_NAME" 2>/dev/null)

        # Extract state — rosa plain output has "State: installing" etc.
        CLUSTER_STATE=$(echo "$DESCRIBE_OUT" | grep -iE "^State:" | awk '{print tolower($2)}' | tr -d '[:space:]')

        # Fallback: try JSON parse if plain text failed
        if [[ -z "$CLUSTER_STATE" ]]; then
          CLUSTER_STATE=$(rosa describe cluster -c "$CLUSTER_NAME"             --output json 2>/dev/null             | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',{}).get('state','unknown'))"             2>/dev/null || echo "unknown")
        fi

        CLUSTER_STATE="${CLUSTER_STATE:-unknown}"

        # Also grab node counts if available
        NODE_INFO=$(echo "$DESCRIBE_OUT" | grep -iE "Compute nodes|Nodes:" | head -1 | xargs 2>/dev/null || true)

        printf "  ${BLUE}[%02d min]${RESET}  State: ${WHITE}%-15s${RESET}  %s\n"           "$WAIT_MINUTES" "$CLUSTER_STATE" "$NODE_INFO"

        case "$CLUSTER_STATE" in
          ready)
            step_ok "Cluster '${CLUSTER_NAME}' is READY 🎉"
            break
            ;;
          error|degraded|uninstalling)
            step_fail "Cluster entered state: ${CLUSTER_STATE}"
            echo ""
            echo -e "${RED}  ── Cluster details ─────────────────────────────────────────────────${RESET}"
            echo "$DESCRIBE_OUT" | grep -iE "State|Reason|Message|Condition" | head -15
            echo -e "${RED}  ─────────────────────────────────────────────────────────────────────${RESET}"
            echo -e "     ${DIM}Full details: rosa describe cluster -c ${CLUSTER_NAME}${RESET}"
            break
            ;;
          installing|waiting|validating|initializing|pending)
            # Normal provisioning states — keep polling
            ;;
          unknown)
            step_warn "Could not retrieve state — check network / ROSA auth"
            # Re-auth if token looks stale
            if ! rosa whoami &>/dev/null; then
              step_warn "ROSA session expired — re-authenticating..."
              if [[ -n "${RHCS_TOKEN}" ]]; then
                rosa login --token="${RHCS_TOKEN}" 2>&1
              else
                echo -e "  ${YELLOW}  Paste fresh token (https://console.redhat.com/openshift/token): ${RESET}"
                read -r _T && [[ -n "$_T" ]] && persist_and_export_token "$_T" && rosa login --token="$_T"
              fi
            fi
            ;;
        esac

        sleep 60
        WAIT_MINUTES=$(( WAIT_MINUTES + 1 ))
      done

      if [[ "$CLUSTER_STATE" != "ready" && WAIT_MINUTES -ge MAX_WAIT ]]; then
        step_warn "Cluster not ready after ${MAX_WAIT} minutes — check manually:"
        echo -e "     ${WHITE}rosa describe cluster -c ${CLUSTER_NAME}${RESET}"
      fi

      # ── Post-deploy info ───────────────────────────────────────────────────
      if [[ "$CLUSTER_STATE" == "ready" ]]; then
        section "PHASE 2 COMPLETE — NEXT STEPS"

        echo ""
        echo -e "${GREEN}${BOLD}  ROSA cluster '${CLUSTER_NAME}' is live!${RESET}"
        echo ""
        echo -e "${WHITE}  Get kubeconfig:${RESET}"
        echo -e "${DIM}    rosa create admin -c ${CLUSTER_NAME}${RESET}"
        echo -e "${DIM}    oc login https://\$(rosa describe cluster -c ${CLUSTER_NAME} --output json | grep api_url | awk -F'\"' '{print \$4}')${RESET}"
        echo ""
        echo -e "${WHITE}  Install RHOAI operator (Phase 3):${RESET}"
        echo -e "${DIM}    oc apply -f ~/GitHub/rhoai-gitops/bootstrap/argocd.yaml${RESET}"
        echo ""
        echo -e "${WHITE}  Verify nodes:${RESET}"
        echo -e "${DIM}    oc get nodes${RESET}"
        echo -e "${DIM}    oc get co   # cluster operators${RESET}"
      fi
    fi

  else
    echo ""
    echo -e "${YELLOW}  Apply skipped. When ready:${RESET}"
    echo -e "${WHITE}    cd ${REPO_PATH}${RESET}"
    echo -e "${WHITE}    export RHCS_TOKEN=\$(cat ~/.rh_token)${RESET}"
    echo -e "${WHITE}    terraform apply tfplan${RESET}"
  fi

else
  step_warn "Apply skipped — fix the failures above first."
fi

# ─────────────────────────────────────────────────────────────────────────────
print_summary
# ─────────────────────────────────────────────────────────────────────────────
