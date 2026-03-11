output "file_system_id"      { value = aws_efs_file_system.this.id;             description = "EFS file system ID — configure in AWS EFS CSI StorageClass on ROSA" }
output "access_point_id"     { value = aws_efs_access_point.rhoai.id;           description = "Access point ID for RHOAI namespace" }
output "security_group_id"   { value = aws_security_group.efs.id }
output "ssm_efs_id_path"     { value = aws_ssm_parameter.efs_id.name }
