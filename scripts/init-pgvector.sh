#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# init-pgvector.sh
# Initialises pgvector schema in Aurora using Data API (no bastion/VPN needed)
# Prerequisites: terraform apply complete, Secrets Manager secret created
#
# Usage:
#   ./scripts/init-pgvector.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
CLUSTER_ID="rhoai-demo-demo-db"
CLUSTER_ARN="arn:aws:rds:${REGION}:${ACCOUNT_ID}:cluster:${CLUSTER_ID}"
SSM_PASSWORD_PATH="/rhoai-demo-demo/aurora/master-password"
SECRET_NAME="rhoai-demo/aurora-master"

echo "🔧 Initialising pgvector in Aurora..."

# Create Secrets Manager secret if it doesn't exist
DB_PASS=$(aws ssm get-parameter \
  --name "${SSM_PASSWORD_PATH}" \
  --with-decryption \
  --query Parameter.Value \
  --output text)

SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "${SECRET_NAME}" \
  --query ARN --output text 2>/dev/null) || \
SECRET_ARN=$(aws secretsmanager create-secret \
  --name "${SECRET_NAME}" \
  --secret-string "{\"username\":\"rhoai_admin\",\"password\":\"${DB_PASS}\"}" \
  --region "${REGION}" \
  --query ARN --output text)

echo "   Secret ARN: ${SECRET_ARN}"
echo "   Cluster ARN: ${CLUSTER_ARN}"

run_sql() {
  local sql="$1"
  local desc="$2"
  aws rds-data execute-statement \
    --resource-arn "${CLUSTER_ARN}" \
    --secret-arn "${SECRET_ARN}" \
    --database "rhoai_demo" \
    --sql "${sql}" \
    --region "${REGION}" > /dev/null
  echo "✅ ${desc}"
}

run_sql "CREATE EXTENSION IF NOT EXISTS vector;" \
  "pgvector extension installed"

run_sql "CREATE SCHEMA IF NOT EXISTS rhoai;" \
  "rhoai schema created"

run_sql "CREATE TABLE IF NOT EXISTS rhoai.embeddings (
    id BIGSERIAL PRIMARY KEY,
    collection VARCHAR(255) NOT NULL DEFAULT 'default',
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    embedding vector(1536),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
  );" \
  "embeddings table created"

run_sql "CREATE INDEX IF NOT EXISTS embeddings_vector_idx
    ON rhoai.embeddings USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);" \
  "vector index created"

run_sql "CREATE TABLE IF NOT EXISTS rhoai.workflow_state (
    session_id VARCHAR(255) PRIMARY KEY,
    state JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
  );" \
  "workflow_state table created"

echo ""
echo "🎉 pgvector schema initialised successfully!"
echo "   Verify with: aws rds-data execute-statement \\"
echo "     --resource-arn ${CLUSTER_ARN} \\"
echo "     --secret-arn ${SECRET_ARN} \\"
echo "     --database rhoai_demo \\"
echo "     --sql \"SELECT extversion FROM pg_extension WHERE extname='vector';\""
