#!/usr/bin/env bash
# =============================================================================
#  Test Suite for AI-demo-stack-create.sh
#  Tests: tool checks, auth validation, terraform phases, error handling
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Test helpers
test_start() {
  echo -e "\n${BLUE}▶ $1${RESET}"
}

test_pass() {
  echo -e "  ${GREEN}✔ $1${RESET}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
  echo -e "  ${RED}✘ $1${RESET}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_skip() {
  echo -e "  ${YELLOW}⊘ $1${RESET}"
}

# =============================================================================
# UNIT TESTS
# =============================================================================

test_start "UNIT: Script exists and is executable"
if [[ -x "${ROOT_DIR}/scripts/AI-demo-stack-create.sh" ]]; then
  test_pass "Script is executable"
else
  test_fail "Script not found or not executable"
fi

test_start "UNIT: Script has required sections"
SCRIPT="${ROOT_DIR}/scripts/AI-demo-stack-create.sh"
for section in "PHASE 0.1" "PHASE 0.2" "PHASE 0.3" "PHASE 1.1" "PHASE 1.2" "PHASE 1.3" "PHASE 2" "PHASE 3"; do
  if grep -q "$section" "$SCRIPT"; then
    test_pass "Section '$section' found"
  else
    test_fail "Section '$section' missing"
  fi
done

test_start "UNIT: Helper functions defined"
for func in "log" "log_ok" "log_fail" "log_warn" "section" "abort" "confirm"; do
  if grep -q "^${func}()" "$SCRIPT"; then
    test_pass "Function '$func' defined"
  else
    test_fail "Function '$func' not defined"
  fi
done

test_start "UNIT: Required tools list"
if grep -q "for tool in aws terraform rosa oc git jq" "$SCRIPT"; then
  test_pass "Tool check loop present"
else
  test_fail "Tool check loop missing"
fi

test_start "UNIT: Token handling functions"
if grep -q "persist_and_export_token" "$SCRIPT"; then
  test_pass "Token persistence function defined"
else
  test_fail "Token persistence function missing"
fi

if grep -q "RHCS_TOKEN" "$SCRIPT"; then
  test_pass "RHCS_TOKEN handling present"
else
  test_fail "RHCS_TOKEN handling missing"
fi

test_start "UNIT: Error handling and retry logic"
if grep -q "run_apply_with_retry" "$SCRIPT"; then
  test_pass "Retry logic function defined"
else
  test_fail "Retry logic function missing"
fi

if grep -q "invalid_grant\|invalid refresh token" "$SCRIPT"; then
  test_pass "Token expiry detection present"
else
  test_fail "Token expiry detection missing"
fi

test_start "UNIT: Terraform phases"
for phase in "terraform init" "terraform plan" "terraform apply"; do
  if grep -q "$phase" "$SCRIPT"; then
    test_pass "Phase '$phase' present"
  else
    test_fail "Phase '$phase' missing"
  fi
done

test_start "UNIT: Cluster readiness polling"
if grep -q "rosa describe cluster" "$SCRIPT"; then
  test_pass "Cluster status check present"
else
  test_fail "Cluster status check missing"
fi

if grep -q "CLUSTER_STATE" "$SCRIPT"; then
  test_pass "Cluster state tracking present"
else
  test_fail "Cluster state tracking missing"
fi

test_start "UNIT: Output extraction"
for output in "rosa_api_url" "rosa_console_url" "vpc_id" "s3_bucket_name" "aurora_endpoint"; do
  if grep -q "$output" "$SCRIPT"; then
    test_pass "Output '$output' extraction present"
  else
    test_fail "Output '$output' extraction missing"
  fi
done

# =============================================================================
# INTEGRATION TESTS (non-destructive)
# =============================================================================

test_start "INTEGRATION: terraform.tfvars validation"
TFVARS="${ROOT_DIR}/environments/demo/terraform.tfvars"
if [[ -f "$TFVARS" ]]; then
  test_pass "terraform.tfvars exists"
  
  REQUIRED_KEYS=("project_name" "environment" "aws_region" "rosa_cluster_name" "ocp_version" "oidc_config_id" "account_role_prefix" "budget_alert_email")
  for key in "${REQUIRED_KEYS[@]}"; do
    if grep -q "^${key}" "$TFVARS"; then
      test_pass "Key '$key' present in terraform.tfvars"
    else
      test_fail "Key '$key' missing from terraform.tfvars"
    fi
  done
else
  test_fail "terraform.tfvars not found"
fi

test_start "INTEGRATION: Terraform configuration"
TF_DIR="${ROOT_DIR}/environments/demo"
for file in "main.tf" "variables.tf" "outputs.tf" "backend.tf" "versions.tf"; do
  if [[ -f "${TF_DIR}/${file}" ]]; then
    test_pass "Terraform file '$file' exists"
  else
    test_fail "Terraform file '$file' missing"
  fi
done

test_start "INTEGRATION: Terraform modules"
MODULES_DIR="${ROOT_DIR}/modules"
for module in "vpc" "rosa-hcp" "iam-irsa" "aurora-serverless" "s3-data-lake" "efs-storage" "ecr-repos" "lambda-triggers"; do
  if [[ -d "${MODULES_DIR}/${module}" ]]; then
    test_pass "Module '$module' directory exists"
    if [[ -f "${MODULES_DIR}/${module}/main.tf" ]]; then
      test_pass "Module '$module' has main.tf"
    else
      test_fail "Module '$module' missing main.tf"
    fi
  else
    test_fail "Module '$module' directory missing"
  fi
done

test_start "INTEGRATION: Script syntax validation"
if bash -n "$SCRIPT" 2>/dev/null; then
  test_pass "Script syntax is valid"
else
  test_fail "Script has syntax errors"
fi

test_start "INTEGRATION: Log directory setup"
LOG_DIR="${ROOT_DIR}/logs"
if [[ -d "$LOG_DIR" ]]; then
  test_pass "Log directory exists"
else
  test_fail "Log directory missing"
fi

test_start "INTEGRATION: Environment directory"
if [[ -d "$TF_DIR" ]]; then
  test_pass "Environment directory exists"
else
  test_fail "Environment directory missing"
fi

# =============================================================================
# MOCK TESTS (simulate script behavior)
# =============================================================================

test_start "MOCK: Tool availability check"
TOOLS_FOUND=0
for tool in aws terraform rosa oc git jq; do
  if command -v "$tool" &>/dev/null; then
    TOOLS_FOUND=$((TOOLS_FOUND + 1))
  fi
done
if (( TOOLS_FOUND >= 4 )); then
  test_pass "At least 4 required tools available (found: $TOOLS_FOUND/6)"
else
  test_skip "Fewer than 4 required tools available (found: $TOOLS_FOUND/6) — some tests require full environment"
fi

test_start "MOCK: AWS profile configuration"
if [[ -f "$HOME/.aws/config" ]]; then
  if grep -q "rhoai-demo" "$HOME/.aws/config"; then
    test_pass "AWS profile 'rhoai-demo' configured"
  else
    test_skip "AWS profile 'rhoai-demo' not configured — skipping AWS auth tests"
  fi
else
  test_skip "AWS config not found — skipping AWS auth tests"
fi

test_start "MOCK: Git repository"
if cd "$ROOT_DIR" && git rev-parse --git-dir &>/dev/null; then
  test_pass "Repository is a valid git repo"
  BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
  test_pass "Current branch: $BRANCH"
else
  test_fail "Not a valid git repository"
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║           TEST SUITE SUMMARY                              ║${RESET}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${GREEN}Passed${RESET}  : $TESTS_PASSED"
echo -e "  ${RED}Failed${RESET}  : $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}✔ All tests passed!${RESET}"
  exit 0
else
  echo -e "${RED}✘ $TESTS_FAILED test(s) failed — review errors above${RESET}"
  exit 1
fi
