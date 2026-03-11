# ─────────────────────────────────────────────────────────────────────────────
# MODULE: efs-storage
# Purpose : Amazon EFS for RHOAI Jupyter notebook persistent volumes (RWX PVCs)
#
# EFS CSI Driver on ROSA provides ReadWriteMany PersistentVolumeClaims.
# This replaces full ODF (Ceph) for demo — saves 3 dedicated infra nodes.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs-sg"
  description = "EFS mount targets — allow NFS from VPC CIDR"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS from VPC (ROSA nodes)"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, { Name = "${var.name}-efs-sg" })
}

resource "aws_efs_file_system" "this" {
  creation_token = "${var.name}-notebooks"
  encrypted      = true

  performance_mode = var.performance_mode   # "generalPurpose" for demo
  throughput_mode  = var.throughput_mode     # "bursting" for demo (free tier)

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"      # Move cold data to IA to save cost
  }

  tags = merge(var.tags, { Name = "${var.name}-notebooks-efs" })
}

resource "aws_efs_mount_target" "this" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# ── EFS Access Point — scoped for RHOAI namespace ────────────────────────────
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

# ── Store EFS ID in SSM for ROSA CSI driver configuration ────────────────────
resource "aws_ssm_parameter" "efs_id" {
  name  = "/${var.ssm_path_prefix}/efs/file-system-id"
  type  = "String"
  value = aws_efs_file_system.this.id
  tags  = var.tags
}
