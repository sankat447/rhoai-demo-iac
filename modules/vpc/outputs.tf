# ─────────────────────────────────────────────────────────────────────────────
# MODULE: vpc — Outputs
# ─────────────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID — pass to rosa-hcp, aurora, efs modules"
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — ROSA workers, Aurora, EFS targets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs — Load balancers, NAT"
  value       = aws_subnet.public[*].id
}

output "vpc_cidr" {
  description = "VPC CIDR block — used for security group ingress rules"
  value       = aws_vpc.this.cidr_block
}

output "nat_gateway_ip" {
  description = "NAT Gateway EIP — whitelist in external firewalls if needed"
  value       = aws_eip.nat.public_ip
}
