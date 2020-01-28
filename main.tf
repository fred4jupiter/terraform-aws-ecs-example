provider "aws" {
  region = "eu-central-1"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.101.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-1a"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-1a"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_eip" "nat-eip" {
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat-eip.id
  subnet_id     = aws_subnet.public.id
}

resource "aws_default_route_table" "private" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "private routes"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public routes"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

module "alb" {
  source             = "umotif-public/alb/aws"
  version            = "~> 1.0"
  name_prefix        = "alb-example"
  load_balancer_type = "application"
  internal           = false
  vpc_id             = aws_vpc.main.id
  subnets            = [aws_subnet.public.id]
  tags = {
    Owner = var.owner
  }
}

resource "aws_lb_listener" "alb_80" {
  load_balancer_arn = module.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = module.ecs-fargate.target_group_arn
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = "example-ecs-cluster"
}

module "ecs-fargate" {
  source  = "umotif-public/ecs-fargate/aws"
  version = "~> 1.0"

  name_prefix                     = "ecs-fargate-example"
  vpc_id                          = aws_vpc.main.id
  lb_arn                          = module.alb.arn
  private_subnet_ids              = [aws_subnet.private.id]
  cluster_id                      = aws_ecs_cluster.cluster.id
  task_container_image            = "fred4jupiter/fredbet:latest"
  task_definition_cpu             = 256
  task_definition_memory          = 1024
  task_container_port             = 8080
  task_container_assign_public_ip = true
  health_check = {
    port = "traffic-port"
    path = "/"
  }
  tags = {
    Owner = var.owner
  }
}