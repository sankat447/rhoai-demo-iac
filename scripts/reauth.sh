#!/usr/bin/env bash
# =============================================================================
#  Re-authentication Recovery Script
#  Refreshes expired AWS SSO and ROSA/OCM tokens
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}${BOLD}║  Re-authentication Recovery                                          ║${RESET}"
echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# Step 1: AWS SSO Login
echo -e "${YELLOW}Step 1: AWS SSO Authentication${RESET}"
echo "Logging in to AWS SSO (profile: rhoai-demo)..."
echo ""
aws sso login --profile rhoai-demo

echo ""
echo -e "${GREEN}✓ AWS SSO authenticated${RESET}"
echo ""

# Step 2: Verify AWS credentials
echo -e "${YELLOW}Step 2: Verify AWS Credentials${RESET}"
IDENTITY=$(aws sts get-caller-identity --profile rhoai-demo 2>&1)
ACCOUNT=$(echo "$IDENTITY" | grep -o '"Account": "[^"]*"' | awk -F'"' '{print $4}')
ARN=$(echo "$IDENTITY" | grep -o '"Arn": "[^"]*"' | awk -F'"' '{print $4}')
echo -e "${GREEN}✓ AWS Account: ${ACCOUNT}${RESET}"
echo -e "${GREEN}✓ AWS Role: ${ARN}${RESET}"
echo ""

# Step 3: ROSA/OCM Login
echo -e "${YELLOW}Step 3: ROSA/OCM Authentication${RESET}"
echo "Logging in to Red Hat SSO (browser-based)..."
echo "A browser window will open. Complete the login and return here."
echo ""
rosa login --use-auth-code

echo ""
echo -e "${GREEN}✓ ROSA/OCM authenticated${RESET}"
echo ""

# Step 4: Verify ROSA authentication
echo -e "${YELLOW}Step 4: Verify ROSA Authentication${RESET}"
WHOAMI=$(rosa whoami 2>&1)
OCM_EMAIL=$(echo "$WHOAMI" | grep "OCM Account Email" | awk '{print $NF}')
echo -e "${GREEN}✓ OCM Email: ${OCM_EMAIL}${RESET}"
echo ""

# Step 5: Export RHCS_TOKEN for Terraform
echo -e "${YELLOW}Step 5: Export RHCS_TOKEN for Terraform${RESET}"
RHCS_TOKEN=$(rosa token 2>/dev/null || echo "")
if [[ -n "$RHCS_TOKEN" ]]; then
  export RHCS_TOKEN
  export ROSA_TOKEN="$RHCS_TOKEN"
  
  # Persist to shell rc
  if [[ -n "${ZSH_VERSION:-}" || "${SHELL:-}" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
  elif [[ -n "${BASH_VERSION:-}" || "${SHELL:-}" == */bash ]]; then
    SHELL_RC="$HOME/.bash_profile"
  else
    SHELL_RC="$HOME/.profile"
  fi
  
  # Remove old entries
  if [[ -f "$SHELL_RC" ]]; then
    TMP=$(mktemp)
    grep -v "^export RHCS_TOKEN=" "$SHELL_RC" | grep -v "^export ROSA_TOKEN=" > "$TMP"
    mv "$TMP" "$SHELL_RC"
  fi
  
  # Add new entries
  {
    echo ""
    echo "# RHCS token for Terraform provider (updated $(date '+%Y-%m-%d %H:%M'))"
    echo "export RHCS_TOKEN=\"${RHCS_TOKEN}\""
    echo "export ROSA_TOKEN=\"${RHCS_TOKEN}\""
  } >> "$SHELL_RC"
  
  echo -e "${GREEN}✓ RHCS_TOKEN exported and persisted to ${SHELL_RC}${RESET}"
else
  echo -e "${RED}✗ Could not obtain RHCS_TOKEN${RESET}"
  echo "   Try manually: export RHCS_TOKEN=\$(rosa token)"
fi
echo ""

# Step 6: Summary
echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}${BOLD}║  Re-authentication Complete ✓                                        ║${RESET}"
echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${GREEN}You can now run:${RESET}"
echo -e "  ${YELLOW}./scripts/bootstrap-state.sh${RESET}"
echo -e "  ${YELLOW}./scripts/AI-demo-stack-create.sh${RESET}"
echo ""
