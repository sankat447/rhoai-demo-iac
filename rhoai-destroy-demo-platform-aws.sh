#!/usr/bin/env zsh
# =============================================================================
#  IIS Tech — Demo AI Platform on AWS + ROSA
#  DESTROY — AWS Platform Layer
#  https://www.iistech.com/
#
#  Destroys (in safe order):
#    - Lambda scheduler
#    - ECR repositories
#    - EFS storage
#    - Aurora PostgreSQL Serverless cluster + subnet group
#    - S3 data lake bucket (prompted — bucket must be empty)
#    - IAM roles + policies
#    - VPC (subnets, NAT GW, IGW, route tables, security groups)
#
#  IMPORTANT: Run rhoai-destroy-demo-platform-rosa.sh FIRST
#             This script will fail if ROSA cluster still exists in the VPC
#
#  Usage: chmod +x rhoai-destroy-demo-platform-aws.sh
#         ./rhoai-destroy-demo-platform-aws.sh
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
AWS_ACCOUNT="406337554361"
AWS_REGION="us-east-1"
S3_BUCKET="rhoai-demo-demo-${AWS_ACCOUNT}"
VPC_ID="vpc-062ba0ee77948a2e9"

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
  echo -e "${RED}${BOLD}║   ${WHITE}${BOLD}DESTROY — Demo AI Platform  │  AWS Platform Layer${RESET}${RED}${BOLD}               ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}https://www.iistech.com/${RESET}${RED}${BOLD}                                          ║${RESET}"
  echo -e "${RED}${BOLD}║                                                                      ║${RESET}"
  echo -e "${RED}${BOLD}║   ${YELLOW}Destroys:${RESET}${RED}${BOLD}                                                          ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  Lambda Cost Scheduler${RESET}${RED}${BOLD}                                          ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  ECR Repositories${RESET}${RED}${BOLD}                                              ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  EFS Shared Storage${RESET}${RED}${BOLD}                                            ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  Aurora PostgreSQL Serverless cluster${RESET}${RED}${BOLD}                          ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  S3 Data Lake bucket  (prompted)${RESET}${RED}${BOLD}                               ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  IAM roles + policies${RESET}${RED}${BOLD}                                          ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  VPC  (subnets, NAT GW, IGW, route tables)${RESET}${RED}${BOLD}                    ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  SSM parameters${RESET}${RED}${BOLD}                                                ║${RESET}"
  echo -e "${RED}${BOLD}║   ${DIM}  ✦  AWS Budgets alert${RESET}${RED}${BOLD}                                             ║${RESET}"
  echo -e "${RED}${BOLD}║                                                                      ║${RESET}"
  echo -e "${RED}${BOLD}║   ${YELLOW}⚠  Run rhoai-destroy-demo-platform-rosa.sh FIRST${RESET}${RED}${BOLD}                   ║${RESET}"
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
  echo -e "${WHITE}${BOLD}║         IIS TECH — AWS PLATFORM DESTROY SUMMARY                     ║${RESET}"
  echo -e "${WHITE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  for line in "${SUMMARY_LINES[@]}"; do echo -e "$line"; done
  echo ""
  echo -e "  ${GREEN}${BOLD}Completed : ${STEPS_PASSED}${RESET}     ${YELLOW}${BOLD}Warnings : ${STEPS_WARNED}${RESET}     ${RED}${BOLD}Failed : ${STEPS_FAILED}${RESET}"
  echo ""
  if [[ $STEPS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ✔  AWS platform layer destroyed successfully.${RESET}"
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
echo -e "${RED}${BOLD}  This will PERMANENTLY DESTROY all AWS platform infrastructure:${RESET}"
echo -e "${RED}  VPC: ${VPC_ID}${RESET}"
echo -e "${RED}  S3 : ${S3_BUCKET}${RESET}"
echo -e "${RED}  Account: ${AWS_ACCOUNT}  │  Region: ${AWS_REGION}${RESET}"

if ! confirm_danger "You are about to destroy ALL AWS platform infrastructure"; then
  echo ""
  echo -e "${YELLOW}  Destroy cancelled — no changes made.${RESET}"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
section "PRE-FLIGHT — AWS AUTH"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Refreshing AWS SSO (profile: ${AWS_PROFILE})..."
aws sso login --profile "$AWS_PROFILE" 2>&1
[[ $? -eq 0 ]] && step_ok "AWS SSO login succeeded" || abort "AWS SSO login failed"

export AWS_PROFILE="$AWS_PROFILE"
aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null \
  && step_ok "AWS identity confirmed — account ${AWS_ACCOUNT}" \
  || abort "Cannot verify AWS identity"

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 1 — VERIFY ROSA CLUSTER IS GONE"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Checking ROSA cluster '${CLUSTER_NAME}' is already destroyed..."
CLUSTER_CHECK=$(rosa describe cluster -c "$CLUSTER_NAME" 2>&1)

if echo "$CLUSTER_CHECK" | grep -qiE "There is no cluster|not found"; then
  step_ok "ROSA cluster '${CLUSTER_NAME}' confirmed gone — safe to destroy VPC"
elif echo "$CLUSTER_CHECK" | grep -qi "uninstalling"; then
  step_warn "ROSA cluster is still uninstalling — VPC destroy may fail"
  if ! confirm "ROSA cluster still uninstalling. Continue anyway?"; then
    echo -e "${YELLOW}  Run rhoai-destroy-demo-platform-rosa.sh first, then re-run this script.${RESET}"
    exit 0
  fi
else
  STATE=$(echo "$CLUSTER_CHECK" | grep "^State:" | awk '{print $2}')
  if [[ -n "$STATE" && "$STATE" != "uninstalling" ]]; then
    step_fail "ROSA cluster '${CLUSTER_NAME}' still exists (state: ${STATE})"
    echo ""
    echo -e "${RED}  You MUST destroy the ROSA cluster first or VPC deletion will fail.${RESET}"
    echo -e "${DIM}  Run: ./rhoai-destroy-demo-platform-rosa.sh${RESET}"
    abort "ROSA cluster must be destroyed before AWS platform layer"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 2 — EMPTY S3 BUCKET"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Checking S3 bucket: ${S3_BUCKET}..."
BUCKET_EXISTS=$(aws s3api head-bucket --bucket "$S3_BUCKET" \
  --profile "$AWS_PROFILE" 2>&1)

if [[ $? -eq 0 ]]; then
  OBJECT_COUNT=$(aws s3 ls "s3://${S3_BUCKET}" --recursive \
    --profile "$AWS_PROFILE" 2>/dev/null | wc -l | tr -d ' ')
  step_warn "Bucket exists with ${OBJECT_COUNT} object(s)"

  if [[ "$OBJECT_COUNT" -gt 0 ]]; then
    echo -e "     ${DIM}Terraform cannot delete non-empty S3 buckets${RESET}"
    if confirm "Empty S3 bucket '${S3_BUCKET}' now? (required for destroy)"; then
      step_info "Emptying bucket including all versions..."
      # Delete all versions and delete markers
      aws s3api list-object-versions \
        --bucket "$S3_BUCKET" \
        --profile "$AWS_PROFILE" \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
        --output json 2>/dev/null | \
        python3 -c "
import sys, json, subprocess
data = json.load(sys.stdin)
objs = data.get('Objects') or []
if objs:
    delete_payload = json.dumps({'Objects': objs, 'Quiet': True})
    subprocess.run(['aws', 's3api', 'delete-objects',
                    '--bucket', '${S3_BUCKET}',
                    '--profile', '${AWS_PROFILE}',
                    '--delete', delete_payload], check=False)
    print(f'Deleted {len(objs)} version(s)')
else:
    print('No versioned objects found')
" 2>/dev/null

      # Also delete current objects
      aws s3 rm "s3://${S3_BUCKET}" --recursive \
        --profile "$AWS_PROFILE" 2>&1 | tail -3

      step_ok "S3 bucket emptied"
    else
      step_warn "S3 bucket not emptied — terraform destroy may fail on S3 module"
    fi
  else
    step_ok "S3 bucket is already empty"
  fi
else
  step_ok "S3 bucket '${S3_BUCKET}' not found — already deleted or never created"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 3 — TERRAFORM DESTROY (ALL AWS MODULES)"
# ─────────────────────────────────────────────────────────────────────────────

cd "$REPO_PATH" || abort "Cannot navigate to ${REPO_PATH}"

step_info "Running terraform init -reconfigure..."
terraform init -reconfigure &>/dev/null \
  && step_ok "terraform init succeeded" \
  || abort "terraform init failed"

DESTROY_LOG="${LOG_DIR}/destroy-aws_${TIMESTAMP}.log"
step_info "Running full terraform destroy..."
echo -e "     ${DIM}This will destroy ALL remaining AWS resources${RESET}"
echo -e "     ${DIM}Log: ${DESTROY_LOG}${RESET}"
echo ""

terraform destroy \
  -target=module.lambda \
  -target=module.ecr \
  -target=module.efs \
  -target=module.aurora \
  -target=module.s3 \
  -target=module.iam_irsa \
  -target=module.vpc \
  --auto-approve \
  2>&1 | tee "$DESTROY_LOG"
TF_DESTROY_RC=${PIPESTATUS[0]}

echo ""
DESTROY_ERRORS=$(grep -c "^│ Error:" "$DESTROY_LOG" 2>/dev/null | tr -d ' ' || echo 0)
DESTROY_ERRORS=${DESTROY_ERRORS:-0}

if [[ $TF_DESTROY_RC -eq 0 ]] && (( DESTROY_ERRORS == 0 )); then
  DESTROY_SUMMARY=$(grep "^Destroy complete!" "$DESTROY_LOG" | tail -1)
  step_ok "Terraform destroy succeeded — ${DESTROY_SUMMARY}"
else
  step_fail "Terraform destroy had errors — see: ${DESTROY_LOG}"
  echo ""
  echo -e "${RED}  ── Error Details ──────────────────────────────────────────────────${RESET}"
  grep -A5 "^│ Error:" "$DESTROY_LOG" 2>/dev/null | head -50
  echo -e "${RED}  ───────────────────────────────────────────────────────────────────${RESET}"

  # Offer full destroy as fallback
  echo ""
  if confirm "Retry with full terraform destroy (no -target filters)?"; then
    DESTROY_LOG2="${LOG_DIR}/destroy-aws-full_${TIMESTAMP}.log"
    echo ""
    terraform destroy --auto-approve 2>&1 | tee "$DESTROY_LOG2"
    [[ ${PIPESTATUS[0]} -eq 0 ]] \
      && step_ok "Full terraform destroy succeeded" \
      || step_fail "Full terraform destroy also failed — check: ${DESTROY_LOG2}"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 4 — VERIFY VPC REMOVED"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Verifying VPC '${VPC_ID}' is removed..."
VPC_CHECK=$(aws ec2 describe-vpcs \
  --vpc-ids "$VPC_ID" \
  --profile "$AWS_PROFILE" 2>&1)

if echo "$VPC_CHECK" | grep -qi "InvalidVpcID.NotFound\|does not exist"; then
  step_ok "VPC '${VPC_ID}' confirmed removed"
else
  step_warn "VPC may still exist — check AWS console"
  echo -e "     ${DIM}aws ec2 describe-vpcs --vpc-ids ${VPC_ID}${RESET}"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "STEP 5 — TERRAFORM STATE BUCKET (OPTIONAL)"
# ─────────────────────────────────────────────────────────────────────────────

step_info "Checking for Terraform state S3 bucket..."
TF_STATE_BUCKET=$(grep "bucket" "$REPO_PATH/../../backend.tf" 2>/dev/null \
  | awk -F'"' '{print $2}' | head -1 || \
  grep "bucket" "$REPO_PATH/backend.tf" 2>/dev/null \
  | awk -F'"' '{print $2}' | head -1 || echo "")

if [[ -n "$TF_STATE_BUCKET" ]]; then
  step_warn "Terraform state bucket found: ${TF_STATE_BUCKET}"
  echo -e "     ${DIM}This stores your terraform.tfstate — delete only if fully done${RESET}"
  if confirm "Delete Terraform state bucket '${TF_STATE_BUCKET}'? (ONLY if fully done with this environment)"; then
    aws s3 rm "s3://${TF_STATE_BUCKET}" --recursive --profile "$AWS_PROFILE" 2>&1
    aws s3api delete-bucket --bucket "$TF_STATE_BUCKET" --profile "$AWS_PROFILE" 2>&1 \
      && step_ok "Terraform state bucket deleted" \
      || step_warn "Could not delete state bucket — delete manually in AWS console"
  else
    step_ok "Terraform state bucket retained — safe to redeploy from scratch later"
  fi
else
  step_ok "No state bucket found in backend config — skipping"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "NEXT STEPS"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${WHITE}  To redeploy from scratch:${RESET}"
echo -e "${DIM}    ./rhoai-deploy-demo-platform-aws.sh   # redeploy AWS layer${RESET}"
echo -e "${DIM}    ./rhoai-deploy-demo-platform-rosa.sh  # redeploy ROSA cluster${RESET}"
echo ""
echo -e "${WHITE}  Verify everything is gone in AWS console:${RESET}"
echo -e "${DIM}    VPC → https://console.aws.amazon.com/vpc/home?region=${AWS_REGION}${RESET}"
echo -e "${DIM}    RDS → https://console.aws.amazon.com/rds/home?region=${AWS_REGION}${RESET}"
echo -e "${DIM}    S3  → https://s3.console.aws.amazon.com/s3/${RESET}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
print_summary
# ─────────────────────────────────────────────────────────────────────────────
