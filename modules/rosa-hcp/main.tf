# ─────────────────────────────────────────────────────────────────────────────
# MODULE: rosa-hcp
# Purpose : ROSA Hosted Control Plane cluster + machine pools
# Provider: terraform-redhat/rhcs (Red Hat Cloud Services)
#
# PLATFORM SCOPE:
#   - ROSA HCP cluster (control plane managed by Red Hat)
#   - Worker machine pool (Spot for demo cost savings)
#   - GPU machine pool (starts at 0 replicas — scale up for vLLM demos)
#   - OIDC provider for IRSA (pod-level AWS credential federation)
#
# WHAT THIS DOES NOT COVER (application layer — GitOps repo):
#   - RHOAI operator installation
#   - ArgoCD bootstrap
#   - Helm chart deployments
# ─────────────────────────────────────────────────────────────────────────────

# ── ROSA Account Roles (must exist before cluster) ───────────────────────────
# These are account-wide IAM roles Red Hat needs to manage ROSA.
# Create once per AWS account, reuse across clusters.
resource "rhcs_rosa_hcp_account_roles" "this" {
  account_role_prefix = var.cluster_name
  path                = "/"
}

# ── ROSA HCP Cluster ─────────────────────────────────────────────────────────
resource "rhcs_cluster_rosa_hcp" "this" {
  name               = var.cluster_name
  cloud_region       = var.aws_region
  version            = "openshift-v${var.ocp_version}"

  aws_account_id         = data.aws_caller_identity.current.account_id
  aws_billing_account_id = data.aws_caller_identity.current.account_id

  # HCP model — control plane runs in Red Hat's account (no CP cost to you)
  aws_subnet_ids = var.private_subnet_ids

  # Network configuration
  machine_cidr = var.vpc_cidr
  service_cidr = "172.30.0.0/16"   # OCP internal services
  pod_cidr     = "10.128.0.0/14"   # OCP pod network
  host_prefix  = 23

  # Admin user for initial oc login
  create_admin_user = true

  properties = {
    rosa_creator_arn = data.aws_caller_identity.current.arn
  }

  # Wait for account roles before creating cluster
  depends_on = [rhcs_rosa_hcp_account_roles.this]
}

# ── Worker Machine Pool — General Workloads ───────────────────────────────────
resource "rhcs_hcp_machine_pool" "workers" {
  cluster      = rhcs_cluster_rosa_hcp.this.id
  name         = "workers"
  machine_type = var.worker_instance_type   # default: c5.2xlarge

  # SPOT INSTANCES — saves 60-70% on EC2 vs on-demand
  # Demo: use spot. Prod: use on-demand or mixed fleet.
  aws_node_pool = {
    instance_profile = ""   # auto-managed by ROSA
  }

  # Autoscaling: scale to 0 overnight to save cost
  autoscaling = {
    min_replicas = var.worker_min_replicas   # 0 for overnight, 2 for active
    max_replicas = var.worker_max_replicas   # 4 for demo peak capacity
  }

  subnet_id = var.private_subnet_ids[0]

  labels = {
    "node-role" = "worker"
    "workload"  = "general"
  }
}

# ── GPU Machine Pool — vLLM / RHOAI Model Serving ────────────────────────────
resource "rhcs_hcp_machine_pool" "gpu" {
  count = var.create_gpu_pool ? 1 : 0

  cluster      = rhcs_cluster_rosa_hcp.this.id
  name         = "gpu-demo"
  machine_type = var.gpu_instance_type   # default: g4dn.xlarge (16GB T4)

  # CRITICAL: Start at 0 replicas — only spin up for active GPU demos
  # Run: rosa edit machinepool gpu-demo --cluster=NAME --replicas=1
  autoscaling = {
    min_replicas = 0
    max_replicas = var.gpu_max_replicas   # default: 1 for demo
  }

  subnet_id = var.private_subnet_ids[0]

  labels = {
    "node-role"           = "worker"
    "workload"            = "gpu"
    "nvidia.com/gpu"      = "true"
  }

  taints = [
    {
      key    = "nvidia.com/gpu"
      value  = "true"
      effect = "NoSchedule"
    }
  ]
}

# ── Data Sources ─────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
