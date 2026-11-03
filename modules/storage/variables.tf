variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets that get an EFS mount target (one per AZ)"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "The only security group allowed to mount the file system"
  type        = string
}
