#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# post-apply.sh
# Run AFTER terraform apply completes
# Handles all steps terraform cannot do:
#   1. Create operator roles (required for cluster to move from waiting->installing)
#   2. Wait for cluster ready
#   3. Make ingress public (private by default on ROSA HCP)
#   4. Create cluster-admin user
#   5. Initialise pgvector
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CLUSTER="rhoai-demo"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "═══════════════════════════════════════════════════════════"
echo "  RHOAI Demo — Post-Apply Setup"
echo "  Cluster: ${CLUSTER}  |  Account: ${ACCOUNT_ID}"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Step 1: Operator roles ────────────────────────────────────────────────────
echo "→ Step 1/5: Creating operator roles..."
echo "  (required for cluster to leave 'waiting' state)"
rosa create operator-roles --cluster "${CLUSTER}" --hosted-cp --yes
echo "✅ Operator roles created"
echo ""

# ── Step 2: Wait for cluster ready ───────────────────────────────────────────
echo "→ Step 2/5: Waiting for cluster to be ready (~15-20 min)..."
echo "  Polling every 30 seconds..."
ELAPSED=0
while true; do
  STATE=$(rosa describe cluster -c "${CLUSTER}" | grep "^State:" | awk '{print $2}')
  echo "  $(date '+%H:%M:%S') — State: ${STATE} (${ELAPSED}s elapsed)"
  if [[ "${STATE}" == "ready" ]]; then
    break
  fi
  if [[ ${ELAPSED} -gt 2400 ]]; then
    echo "❌ Timeout after 40 minutes. Check: rosa describe cluster -c ${CLUSTER}"
    exit 1
  fi
  sleep 30
  ELAPSED=$((ELAPSED + 30))
done
echo "✅ Cluster is ready!"
echo ""

# ── Step 3: Make ingress public ───────────────────────────────────────────────
# FIX: ROSA HCP creates private ingress by default
# Must set BOTH cluster private=false AND ingress private=false
echo "→ Step 3/5: Making cluster ingress public..."
rosa edit cluster -c "${CLUSTER}" --private=false
sleep 10

# Get ingress ID and make it public
INGRESS_ID=$(rosa list ingresses -c "${CLUSTER}" | grep -v "^ID" | awk '{print $1}' | head -1)
echo "  Ingress ID: ${INGRESS_ID}"
rosa edit ingress -c "${CLUSTER}" "${INGRESS_ID}" --private=false --yes
echo "  Waiting 3 minutes for DNS propagation..."
sleep 180

# Verify DNS is public
CONSOLE_HOST="console-openshift-console.apps.rosa.${CLUSTER}.pdde.p3.openshiftapps.com"
DNS_RESULT=$(dig "${CONSOLE_HOST}" +short | grep -v "amazonaws.com" | head -1)
if [[ -n "${DNS_RESULT}" ]] && [[ "${DNS_RESULT}" != 10.* ]]; then
  echo "✅ Console is publicly accessible: ${DNS_RESULT}"
else
  echo "⚠️  DNS still propagating — wait 5 more minutes then check:"
  echo "   dig ${CONSOLE_HOST} +short"
fi
echo ""

# ── Step 4: Create admin user ─────────────────────────────────────────────────
echo "→ Step 4/5: Creating cluster-admin user..."
rosa delete admin -c "${CLUSTER}" --yes 2>/dev/null || true
echo ""
echo "════════════════════════════════════════════════════════"
echo "  ⚠️  COPY THE PASSWORD BELOW — only shown once!"
echo "════════════════════════════════════════════════════════"
rosa create admin -c "${CLUSTER}"
echo ""

# ── Step 5: Initialise pgvector ───────────────────────────────────────────────
echo "→ Step 5/5: Initialising pgvector in Aurora..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/init-pgvector.sh"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
API_URL=$(rosa describe cluster -c "${CLUSTER}" | grep "^API URL:" | awk '{print $3}')
CONSOLE_URL=$(rosa describe cluster -c "${CLUSTER}" | grep "^Console URL:" | awk '{print $3}')

echo "═══════════════════════════════════════════════════════════"
echo "✅ Post-apply setup complete!"
echo ""
echo "  Console:  ${CONSOLE_URL}"
echo "  API:      ${API_URL}"
echo ""
echo "  Login from Mac (once DNS resolves):"
echo "  oc login ${API_URL} --username cluster-admin"
echo ""
echo "  Next: Install RHOAI operator via bastion or console"
echo "═══════════════════════════════════════════════════════════"
