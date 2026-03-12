# ─────────────────────────────────────────────────────────────────────────────
# MODULE: efs-storage
# Amazon EFS for RHOAI Jupyter notebook persistent volumes (RWX PVCs)
# ─────────────────────────────────────────────────────────────────────────────

# NOTE: Security group descriptions must use ASCII only
resource "aws_security_group" "efs" {
  name        = "${var.name}-efs-sg"
  description = "EFS mount targets - allow NFS port 2049 from VPC CIDR"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-efs-sg" })
}

resource "aws_efs_file_system" "this" {
  creation_token   = "${var.name}-notebooks"
  encrypted        = true
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(var.tags, { Name = "${var.name}-notebooks-efs" })
}

resource "aws_efs_mount_target" "this" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "rhoai" {
  file_system_id = aws_efs_file_system.this.id

  root_directory {
    path = "/rhoai-notebooks"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = merge(var.tags, { Name = "${var.name}-rhoai-ap" })
}

resource "aws_ssm_parameter" "efs_id" {
  name  = "/${var.ssm_path_prefix}/efs/file-system-id"
  type  = "String"
  value = aws_efs_file_system.this.id
  tags  = var.tags
}
