# ─────────────────────────────────────────────────────────────────────────────
# MODULE: aurora-serverless
# Aurora PostgreSQL Serverless v2 with pgvector + Data API enabled
# ─────────────────────────────────────────────────────────────────────────────

resource "random_password" "db_master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.ssm_path_prefix}/aurora/master-password"
  type  = "SecureString"
  value = random_password.db_master.result
  tags  = var.tags
}

resource "aws_ssm_parameter" "db_endpoint" {
  name       = "/${var.ssm_path_prefix}/aurora/endpoint"
  type       = "String"
  value      = aws_rds_cluster.this.endpoint
  depends_on = [aws_rds_cluster.this]
  tags       = var.tags
}

resource "aws_rds_cluster_parameter_group" "params" {
  family      = "aurora-postgresql16"
  name        = "${var.cluster_identifier}-params"
  description = "Aurora PostgreSQL params for RHOAI demo"

  parameter {
    name  = "pg_stat_statements.track"
    value = "ALL"
  }

  tags = var.tags
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.cluster_identifier}-subnet-group" })
}

resource "aws_security_group" "aurora" {
  name        = "${var.cluster_identifier}-aurora-sg"
  description = "Aurora PostgreSQL - allow port 5432 from VPC CIDR only"
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

resource "aws_rds_cluster" "this" {
  cluster_identifier     = var.cluster_identifier
  engine                 = "aurora-postgresql"
  engine_version         = var.engine_version
  database_name          = var.database_name
  master_username        = var.master_username
  master_password        = random_password.db_master.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.params.name

  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu
    max_capacity = var.max_acu
  }

  # Enable Data API — required for RDS Query Editor and direct SQL via AWS CLI
  enable_http_endpoint = true

  storage_encrypted       = true
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection
  apply_immediately       = true
  backup_retention_period = var.backup_retention_days
  preferred_backup_window = "03:00-04:00"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = var.tags
}

resource "aws_rds_cluster_instance" "writer" {
  cluster_identifier   = aws_rds_cluster.this.id
  identifier           = "${var.cluster_identifier}-writer"
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.this.engine
  engine_version       = aws_rds_cluster.this.engine_version
  db_subnet_group_name = aws_db_subnet_group.this.name

  performance_insights_enabled = true

  tags = var.tags
}
