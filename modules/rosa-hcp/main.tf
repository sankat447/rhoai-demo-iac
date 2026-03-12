# ─────────────────────────────────────────────────────────────────────────────
# MODULE: rosa-hcp
# ROSA Hosted Control Plane cluster + worker + GPU machine pools
# Provider: terraform-redhat/rhcs v1.7.x (schema verified from provider)
#
# PREREQS - run ONCE before terraform apply:
#   rosa login
#   rosa create account-roles --hosted-cp --prefix rhoai-demo --yes
#   rosa create oidc-config --managed --yes --region us-east-1
#   rosa list oidc-config   <- copy ID to var.oidc_config_id
# ─────────────────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  installer_role_arn = "arn:aws:iam::${local.account_id}:role/${var.account_role_prefix}-HCP-ROSA-Installer-Role"
  support_role_arn   = "arn:aws:iam::${local.account_id}:role/${var.account_role_prefix}-HCP-ROSA-Support-Role"
  worker_role_arn    = "arn:aws:iam::${local.account_id}:role/${var.account_role_prefix}-HCP-ROSA-Worker-Role"
}

resource "rhcs_cluster_rosa_hcp" "this" {
  name         = var.cluster_name
  cloud_region = var.aws_region
  version      = var.ocp_version

  aws_account_id         = local.account_id
  aws_billing_account_id = local.account_id

  aws_subnet_ids     = var.private_subnet_ids
  availability_zones = var.availability_zones

  machine_cidr = var.vpc_cidr
  service_cidr = "172.30.0.0/16"
  pod_cidr     = "10.128.0.0/14"
  host_prefix  = 23

  private           = true
  create_admin_user = true

  properties = {
    rosa_creator_arn = data.aws_caller_identity.current.arn
  }

  # STS block - exact schema verified from provider v1.7 schema output
  sts = {
    role_arn             = local.installer_role_arn
    support_role_arn     = local.support_role_arn
    oidc_config_id       = var.oidc_config_id
    operator_role_prefix = var.account_role_prefix
    instance_iam_roles = {
      worker_role_arn = local.worker_role_arn
    }
  }

  # Set to false — RHCS token expires before 20-min cluster creation completes
  # Monitor progress with: rosa describe cluster -c rhoai-demo
  wait_for_create_complete            = false
  wait_for_std_compute_nodes_complete = false
}

# ── Worker Machine Pool ───────────────────────────────────────────────────────
resource "rhcs_hcp_machine_pool" "workers" {
  cluster   = rhcs_cluster_rosa_hcp.this.id
  name      = "compute"
  subnet_id = var.private_subnet_ids[0]
  auto_repair = true

  aws_node_pool = {
    instance_type = var.worker_instance_type
  }

  autoscaling = {
    enabled      = true
    min_replicas = var.worker_min_replicas
    max_replicas = var.worker_max_replicas
  }

  labels = {
    "node-role" = "worker"
    "workload"  = "general"
  }
}

# ── GPU Machine Pool - starts at 0 replicas ───────────────────────────────────
resource "rhcs_hcp_machine_pool" "gpu" {
  count = var.create_gpu_pool ? 1 : 0

  cluster   = rhcs_cluster_rosa_hcp.this.id
  name      = "gpu-demo"
  subnet_id = var.private_subnet_ids[0]
  auto_repair = true

  aws_node_pool = {
    instance_type = var.gpu_instance_type
  }

  # Start at 0 - scale up only for vLLM demos to save cost
  autoscaling = {
    enabled      = true
    min_replicas = 0
    max_replicas = var.gpu_max_replicas
  }

  labels = {
    "node-role"      = "worker"
    "workload"       = "gpu"
    "nvidia.com/gpu" = "true"
  }

  taints = [{
    key           = "nvidia.com/gpu"
    value         = "true"
    schedule_type = "NoSchedule"
  }]
}
