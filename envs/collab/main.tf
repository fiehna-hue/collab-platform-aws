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

module "nextcloud" {
  source = "../../modules/nextcloud"

  name                        = "collab"
  role_prefix                 = "platform-app-collab"
  vpc_id                      = module.network.vpc_id
  public_subnet_ids           = module.network.public_subnet_ids
  private_subnet_ids          = module.network.private_subnet_ids
  app_security_group_id       = aws_security_group.app.id
  db_security_group_id        = module.database.security_group_id
  endpoints_security_group_id = module.endpoints.security_group_id
  allowed_cidr                = var.allowed_cidr

  # Mirrored in ECR (tasks cannot reach Docker Hub), pinned by digest.
  image = "247906201098.dkr.ecr.us-east-1.amazonaws.com/nextcloud@sha256:c73d6b4ada5126dc56bbd6357f9c73c9caf99f4a692bd2da4187ea58b9089eec"

  db_host        = module.database.endpoint
  db_name        = "inventory"
  db_user        = module.database.username
  db_secret_arn  = module.database.secret_arn
  file_system_id = module.storage.file_system_id

  # Mount targets and endpoints must exist before the first task starts.
  depends_on = [module.storage, module.endpoints]
}

output "alb_dns_name" {
  value = module.nextcloud.alb_dns_name
}
