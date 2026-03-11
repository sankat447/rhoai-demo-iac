# ─────────────────────────────────────────────────────────────────────────────
# MODULE: rosa-hcp — Outputs
# ─────────────────────────────────────────────────────────────────────────────

output "cluster_id" {
  description = "ROSA cluster ID — used by iam-irsa module"
  value       = rhcs_cluster_rosa_hcp.this.id
}

output "cluster_name" {
  description = "ROSA cluster name"
  value       = rhcs_cluster_rosa_hcp.this.name
}

output "api_url" {
  description = "OCP API server URL — use for: oc login --server=API_URL"
  value       = rhcs_cluster_rosa_hcp.this.api_url
}

output "console_url" {
  description = "OpenShift web console URL"
  value       = rhcs_cluster_rosa_hcp.this.console_url
}

output "oidc_endpoint_url" {
  description = "OIDC endpoint URL — pass to iam-irsa module for IRSA setup"
  value       = rhcs_cluster_rosa_hcp.this.sts.oidc_endpoint_url
}

output "oidc_config_id" {
  description = "OIDC configuration ID"
  value       = rhcs_cluster_rosa_hcp.this.sts.oidc_config_id
}

output "cluster_state" {
  description = "Current cluster state (ready/installing/etc.)"
  value       = rhcs_cluster_rosa_hcp.this.state
}
