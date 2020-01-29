provider "aws" {
  region  = "eu-central-1"
  version = "~> 2.46"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "fredbet-vpc"
  }
}

resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.101.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-1a"
  }
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.102.0/24"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-1b"
  }
}

resource "aws_subnet" "private1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-1a"
  }
}

resource "aws_subnet" "private2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-1b"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "fredbet-igw"
  }
}

resource "aws_eip" "nat" {
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public1.id
}

resource "aws_route_table" "rt-public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public routes"
  }
}

resource "aws_route_table" "rt-private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "private routes"
  }
}

resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.rt-public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.rt-public.id
}

resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.rt-private.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.rt-private.id
}

# ALB -------------------------------------------------------------

resource "random_id" "logs_bucket_id" {
  byte_length = 2
}

data "aws_elb_service_account" "this" {}

data "aws_iam_policy_document" "s3_access_logs_permissions" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.environment}-${var.name}-logs-${random_id.logs_bucket_id.dec}/ALB/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }
  }
}

resource "aws_s3_bucket" "alb-logs" {
  bucket        = "${var.environment}-${var.name}-logs-${random_id.logs_bucket_id.dec}"
  acl           = "private"
  policy        = data.aws_iam_policy_document.s3_access_logs_permissions.json
  force_destroy = true

  tags = {
    Name = "alb-logs-fredbet"
  }
}

resource "aws_security_group" "alb-sg" {
  name        = "alb-sg"
  description = "security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

resource "aws_lb" "alb" {
  name                       = "fredbet-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb-sg.id]
  subnets                    = [aws_subnet.public1.id, aws_subnet.public2.id]
  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.alb-logs.id
    prefix  = "ALB"
    enabled = true
  }

  tags = {
    Name = "alb-fredbet"
  }
}

resource "aws_lb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-tg.arn
  }
}

resource "aws_lb_target_group" "alb-tg" {
  name        = "alb-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "5"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/actuator/health"
    unhealthy_threshold = "2"
  }

  stickiness {
    type = "lb_cookie"
  }
  vpc_id = aws_vpc.main.id
}

# ECS---------------------------------------------------------------------------

resource "aws_iam_role" "execution_role" {
  name               = "${var.name}-${var.environment}-exec-role"
  description        = "Execution role for ${var.name}-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "execution_policy" {
  name        = "${var.name}-${var.environment}-policy"
  description = "Execution policy for ${var.name}-${var.environment}"

  policy = data.aws_iam_policy_document.execution_permission.json
}

data "aws_iam_policy_document" "execution_permission" {
  statement {
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.execution_role.name
  policy_arn = aws_iam_policy.execution_policy.arn
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${var.name}-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_cluster" "cluster" {
  name = "fredbet-ecs-cluster"
}

resource "aws_security_group" "ecs_tasks-sg" {
  name   = "ecs_tasks-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "Allow HTTP from load balancer"
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.alb-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs_tasks-sg"
  }
}

resource "aws_ecs_service" "fredbet-service" {
  name                              = "fredbet-service"
  cluster                           = aws_ecs_cluster.cluster.id
  desired_count                     = 1
  task_definition                   = aws_ecs_task_definition.fredbet-td.id
  health_check_grace_period_seconds = 30
  launch_type                       = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private1.id, aws_subnet.private2.id]
    security_groups  = [aws_security_group.ecs_tasks-sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.alb-tg.id
    container_name   = "fredbet"
    container_port   = "8080"
  }

  depends_on = [aws_lb_listener.alb-listener]

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ecs_container_definition" "ecs-fredbet" {
  task_definition = aws_ecs_task_definition.fredbet-td.id
  container_name  = "fredbet"
}

resource "aws_ecs_task_definition" "fredbet-td" {
  container_definitions    = file("task-definitions/service.json")
  execution_role_arn       = aws_iam_role.execution_role.arn
  family                   = "fredbet-task-def"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "1024"
  lifecycle {
    create_before_destroy = true
  }
}

