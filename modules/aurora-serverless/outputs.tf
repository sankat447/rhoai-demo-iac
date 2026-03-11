output "cluster_endpoint"     { value = aws_rds_cluster.this.endpoint;             description = "Writer endpoint for application connections" }
output "cluster_identifier"   { value = aws_rds_cluster.this.cluster_identifier;   description = "Cluster identifier for aws rds commands" }
output "database_name"        { value = aws_rds_cluster.this.database_name }
output "port"                 { value = aws_rds_cluster.this.port }
output "security_group_id"    { value = aws_security_group.aurora.id;              description = "Add to ROSA pod SGs that need DB access" }
output "ssm_password_path"    { value = aws_ssm_parameter.db_password.name;        description = "SSM path for DB password — do NOT use Terraform output for this" }
output "ssm_endpoint_path"    { value = aws_ssm_parameter.db_endpoint.name;        description = "SSM path for DB endpoint" }
