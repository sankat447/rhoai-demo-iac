-- ─────────────────────────────────────────────────────────────────────────────
-- Aurora PostgreSQL Init Script — run after cluster creation
-- Usage: psql "postgresql://rhoai_admin:PASSWORD@ENDPOINT/rhoai_demo" -f init.sql
-- ─────────────────────────────────────────────────────────────────────────────

-- Enable pgvector extension (requires parameter group + reboot first)
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify pgvector is installed
SELECT * FROM pg_extension WHERE extname = 'vector';

-- ── Schema for RAG / LangChain embeddings ────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS rhoai;

-- Embeddings table — stores document chunks + their vector representations
CREATE TABLE IF NOT EXISTS rhoai.embeddings (
    id          BIGSERIAL PRIMARY KEY,
    collection  VARCHAR(255) NOT NULL DEFAULT 'default',
    content     TEXT         NOT NULL,
    metadata    JSONB                 DEFAULT '{}',
    embedding   vector(1536),         -- Bedrock Titan Embeddings v2 dimension
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- IVFFlat index for approximate nearest-neighbor search
-- Faster queries; rebuild after adding many rows: REINDEX INDEX embeddings_vector_idx
CREATE INDEX IF NOT EXISTS embeddings_vector_idx
    ON rhoai.embeddings USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Index on collection for filtering by document set
CREATE INDEX IF NOT EXISTS embeddings_collection_idx
    ON rhoai.embeddings (collection);

-- ── Application state table — LangGraph / n8n workflow state ─────────────────
CREATE TABLE IF NOT EXISTS rhoai.workflow_state (
    session_id  VARCHAR(255) PRIMARY KEY,
    state       JSONB        NOT NULL DEFAULT '{}',
    updated_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE rhoai.embeddings       IS 'Vector embeddings for RAG — managed by LangChain PGVector';
COMMENT ON TABLE rhoai.workflow_state   IS 'LangGraph agent session state';

\echo 'pgvector init complete. Run: SELECT extversion FROM pg_extension WHERE extname = ''vector'';'
