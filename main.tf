provider "aws" {
  region = "eu-central-1"
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

# -------------------------------------------------------------

module "alb" {
  source             = "umotif-public/alb/aws"
  version            = "~> 1.1.0"
  name_prefix        = "alb-fredbet"
  load_balancer_type = "application"
  internal           = false
  vpc_id             = aws_vpc.main.id
  subnets            = [aws_subnet.public1.id, aws_subnet.public2.id]

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
  name = "fredbet-ecs-cluster"
}

module "ecs-fargate" {
  source  = "umotif-public/ecs-fargate/aws"
  version = "~> 1.0.8"

  name_prefix                     = "ecs-fargate"
  vpc_id                          = aws_vpc.main.id
  lb_arn                          = module.alb.arn
  private_subnet_ids              = [aws_subnet.private1.id, aws_subnet.private2.id]
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
}