resource "aws_security_group" "efs" {
  name        = "${var.name}-efs"
  description = "NFS from the app tier only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-efs" }
}

resource "aws_vpc_security_group_ingress_rule" "nfs_from_app" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = var.app_security_group_id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  description                  = "NFS from the app tier"
}

# The app security group has no allow-all egress, so NFS must be opened explicitly.
resource "aws_vpc_security_group_egress_rule" "app_to_efs" {
  security_group_id            = var.app_security_group_id
  referenced_security_group_id = aws_security_group.efs.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  description                  = "NFS to the file system"
}

resource "aws_efs_file_system" "this" {
  encrypted = true

  tags = { Name = "${var.name}-files" }
}

resource "aws_efs_mount_target" "this" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}
