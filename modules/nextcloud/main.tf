data "aws_region" "current" {}

data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${data.aws_region.current.name}.s3"
}

# ---------- Network rules ----------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Load balancer: HTTP from one allowed source"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.allowed_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP from the allowed source"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = var.app_security_group_id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "To the app tier"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = var.app_security_group_id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  description                  = "From the load balancer"
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = var.app_security_group_id
  referenced_security_group_id = var.db_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres"
}

resource "aws_vpc_security_group_egress_rule" "app_to_endpoints" {
  security_group_id            = var.app_security_group_id
  referenced_security_group_id = var.endpoints_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Interface endpoints (ECR, Logs, Secrets Manager)"
}

resource "aws_vpc_security_group_egress_rule" "app_to_s3" {
  security_group_id = var.app_security_group_id
  prefix_list_id    = data.aws_prefix_list.s3.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "S3 gateway endpoint (image layers)"
}

# ---------- Load balancer ----------

resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "nextcloud" {
  name                 = "${var.name}-nextcloud"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    path                = "/status.php"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nextcloud.arn
  }
}

# ---------- Task execution role and logs ----------

resource "aws_iam_role" "exec" {
  name = "${var.role_prefix}-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "exec" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Read exactly one secret: the database password.
resource "aws_iam_role_policy" "read_db_secret" {
  name = "read-db-secret"
  role = aws_iam_role.exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.db_secret_arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "nextcloud" {
  name              = "/platform/${var.name}/nextcloud"
  retention_in_days = 7
}

# ---------- ECS ----------

resource "aws_ecs_cluster" "this" {
  name = var.name
}

resource "aws_ecs_task_definition" "nextcloud" {
  family                   = "${var.name}-nextcloud"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.exec.arn

  volume {
    name = "html"

    efs_volume_configuration {
      file_system_id     = var.file_system_id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }

  container_definitions = jsonencode([{
    name         = "nextcloud"
    image        = var.image
    essential    = true
    portMappings = [{ containerPort = 80 }]

    mountPoints = [{
      sourceVolume  = "html"
      containerPath = "/var/www/html"
      readOnly      = false
    }]

    # Database settings only. The admin account is created by a person in the
    # browser on first visit, so no admin password exists in code or state.
    environment = [
      { name = "POSTGRES_HOST", value = var.db_host },
      { name = "POSTGRES_DB", value = var.db_name },
      { name = "POSTGRES_USER", value = var.db_user }
    ]

    secrets = [{
      name      = "POSTGRES_PASSWORD"
      valueFrom = "${var.db_secret_arn}:password::"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.nextcloud.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "nextcloud"
      }
    }
  }])
}

resource "aws_ecs_service" "nextcloud" {
  name            = "${var.name}-nextcloud"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.nextcloud.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # First start copies Nextcloud into the empty file system, which is slow.
  health_check_grace_period_seconds = 600
  wait_for_steady_state             = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nextcloud.arn
    container_name   = "nextcloud"
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.exec,
    aws_iam_role_policy.read_db_secret,
    aws_vpc_security_group_egress_rule.app_to_db,
    aws_vpc_security_group_egress_rule.app_to_endpoints,
    aws_vpc_security_group_egress_rule.app_to_s3,
  ]
}
