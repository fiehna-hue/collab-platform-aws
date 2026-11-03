output "file_system_id" {
  value = aws_efs_file_system.this.id
}

output "security_group_id" {
  value = aws_security_group.efs.id
}

output "access_point_ids" {
  value = { for k, v in aws_efs_access_point.this : k => v.id }
}
