provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "collab-platform-aws"
      Environment = "collab"
      ManagedBy   = "terraform"
    }
  }
}

# Network, endpoints and database come from aws-platform-as-code,
# pinned to one commit so this stack never changes by surprise.

module "network" {
  source = "git::https://github.com/fiehna-hue/aws-platform-as-code.git//modules/network?ref=e196efcfb4042da44b4e880d1f7c8eecaec6a7e8"

  name = "collab"
}

resource "aws_security_group" "app" {
  name        = "collab-app"
  description = "Nextcloud tasks"
  vpc_id      = module.network.vpc_id

  tags = { Name = "collab-app" }
}

module "endpoints" {
  source = "git::https://github.com/fiehna-hue/aws-platform-as-code.git//modules/endpoints?ref=e196efcfb4042da44b4e880d1f7c8eecaec6a7e8"

  name                  = "collab"
  vpc_id                = module.network.vpc_id
  subnet_ids            = module.network.private_subnet_ids
  app_security_group_id = aws_security_group.app.id
}

module "database" {
  source = "git::https://github.com/fiehna-hue/aws-platform-as-code.git//modules/database?ref=e196efcfb4042da44b4e880d1f7c8eecaec6a7e8"

  name                  = "collab"
  vpc_id                = module.network.vpc_id
  subnet_ids            = module.network.database_subnet_ids
  app_security_group_id = aws_security_group.app.id
}

module "storage" {
  source = "../../modules/storage"

  name                  = "collab"
  vpc_id                = module.network.vpc_id
  subnet_ids            = module.network.private_subnet_ids
  app_security_group_id = aws_security_group.app.id
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "db_endpoint" {
  value = module.database.endpoint
}

output "efs_id" {
  value = module.storage.file_system_id
}
