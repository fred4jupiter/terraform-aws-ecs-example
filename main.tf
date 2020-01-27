provider "aws" {
  region = "eu-central-1"
}

module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  version            = "~> 2.21"
  name               = "simple-vpc"
  cidr               = "10.0.0.0/16"
  azs                = ["eu-central-1a", "eu-central-1b"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets     = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway = false
  tags = {
    Owner = var.owner
  }
}

data "aws_subnet_ids" "private" {
  vpc_id = module.vpc.vpc_id
  tags = {
    Name  = "*private*"
    Owner = var.owner
  }
}

module "alb" {
  source             = "umotif-public/alb/aws"
  version            = "~> 1.0"
  name_prefix        = "alb-example"
  load_balancer_type = "application"
  internal           = false
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
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
  vpc_id                          = module.vpc.vpc_id
  lb_arn                          = module.alb.arn
  private_subnet_ids              = data.aws_subnet_ids.private.ids
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