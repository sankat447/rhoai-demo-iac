# ─────────────────────────────────────────────────────────────────────────────
# MODULE: aurora-serverless
# Purpose : Aurora PostgreSQL Serverless v2 with pgvector extension
#
# Why Aurora Serverless v2 for demo:
#   - Scales from 0.5 ACU (~$0.06/hr idle) to 4 ACU under load
#   - No minimum instance fee — only pay for actual ACU-hours used
#   - pgvector extension replaces Amazon OpenSearch for RAG demo (saves $100/mo)
#
# Contains:
#   - Aurora Serverless v2 cluster (PostgreSQL 15)
#   - Parameter group enabling pgvector
#   - Security group scoped to VPC CIDR only
#   - Subnet group across private subnets
#   - SSM parameters for connection details (no secrets in Terraform outputs)
# ─────────────────────────────────────────────────────────────────────────────

# ── Random password for DB master user ───────────────────────────────────────
resource "random_password" "db_master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ── Store password in SSM Parameter Store (NOT in Terraform state) ────────────
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.ssm_path_prefix}/aurora/master-password"
  type  = "SecureString"
  value = random_password.db_master.result

  tags = var.tags
}

resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/${var.ssm_path_prefix}/aurora/endpoint"
  type  = "String"
  value = aws_rds_cluster.this.endpoint

  depends_on = [aws_rds_cluster.this]
  tags       = var.tags
}

# ── Parameter Group — enables pgvector ───────────────────────────────────────
resource "aws_rds_cluster_parameter_group" "pgvector" {
  family      = "aurora-postgresql15"
  name        = "${var.cluster_identifier}-pgvector-params"
  description = "Enable pgvector extension for Aurora PostgreSQL"

  parameter {
    name  = "shared_preload_libraries"
    value = "vector"
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

# ── Subnet Group ─────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.cluster_identifier}-subnet-group" })
}

# ── Security Group — only allow traffic from within VPC ──────────────────────
resource "aws_security_group" "aurora" {
  name        = "${var.cluster_identifier}-aurora-sg"
  description = "Aurora PostgreSQL — allow PostgreSQL from VPC CIDR only"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.cluster_identifier}-aurora-sg" })
}

# ── Aurora Serverless v2 Cluster ─────────────────────────────────────────────
resource "aws_rds_cluster" "this" {
  cluster_identifier     = var.cluster_identifier
  engine                 = "aurora-postgresql"
  engine_version         = var.engine_version
  database_name          = var.database_name
  master_username        = var.master_username
  master_password        = random_password.db_master.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.pgvector.name

  # Serverless v2 scaling — THE key to demo cost savings
  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu   # 0.5 ACU minimum (~$0.06/hr idle)
    max_capacity = var.max_acu   # 4 ACU maximum (scales under load)
  }

  storage_encrypted = true
  # Use default KMS key for demo; specify KMS ARN for production

  # Demo-safe settings (tighten for production)
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection
  apply_immediately       = true
  backup_retention_period = var.backup_retention_days
  preferred_backup_window = "03:00-04:00"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = var.tags
}

# ── Aurora Serverless v2 Writer Instance ─────────────────────────────────────
resource "aws_rds_cluster_instance" "writer" {
  cluster_identifier = aws_rds_cluster.this.id
  identifier         = "${var.cluster_identifier}-writer"
  instance_class     = "db.serverless"    # MUST be "db.serverless" for v2
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_subnet_group_name = aws_db_subnet_group.this.name

  # Performance Insights — free tier (7 days) for demo monitoring
  performance_insights_enabled = true

  tags = var.tags
}
