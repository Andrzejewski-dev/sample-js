terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # version = "~> 4.16"
    }
  }

  backend "s3" {
    bucket = "andrzejewski-dev-sample-js"
    key    = "sample-js-tf"
    region = "eu-central-1"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "sample-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.0.0/24", "10.0.16.0/24"]
  public_subnets  = ["10.0.128.0/24", "10.0.144.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  default_security_group_ingress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      self        = "false"
      cidr_blocks = "0.0.0.0/0"
      description = "any"
    }
  ]
  default_security_group_egress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

# -----------------------------------------------------------------------------------
resource "aws_lb" "sample_ecs_alb" {
  name               = "sample-ecs-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.vpc.default_security_group_id]
  subnets            = module.vpc.public_subnets

  tags = {
    Name = "sample-ecs-alb"
  }
}

resource "aws_lb_target_group" "sample_ecs_tg" {
  name        = "sample-ecs-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "ecs_alb_listener" {
  load_balancer_arn = aws_lb.sample_ecs_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sample_ecs_tg.arn
  }
}
# -----------------------------------------------------------------------------------

resource "aws_ecs_cluster" "sample_ecs_cluster" {
  name = "sample-ecs-cluster"
}

resource "aws_ecs_task_definition" "sample_ecs_task_definition" {
  family                   = "sample-ecs-task-definition"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  execution_role_arn = "arn:aws:iam::${var.aws_account_id}:role/ecsTaskExecutionRole"
  cpu                = 256
  memory             = 512

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
  container_definitions = jsonencode([
    {
      name      = var.image_name
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.image_name}:${var.image_version}"
      cpu       = 256
      memory    = 512
      essential = true
      environment = [
        {
          name  = "MESSAGE",
          value = var.message
        }
      ]
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "sample_ecs_service" {
  name            = "sample-ecs-service"
  cluster         = aws_ecs_cluster.sample_ecs_cluster.id
  task_definition = aws_ecs_task_definition.sample_ecs_task_definition.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [module.vpc.default_security_group_id]
    # assign_public_ip = true
  }

  # placement_constraints {
  #   type = "distinctInstance"
  # }

  force_new_deployment = true
  # triggers = {
  #   redeployment = timestamp()
  # }

  # capacity_provider_strategy {
  #   capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
  #   weight            = 100
  # }

  load_balancer {
    target_group_arn = aws_lb_target_group.sample_ecs_tg.arn
    container_name   = var.image_name
    container_port   = 80
  }

  # depends_on = [aws_autoscaling_group.ecs_asg]
}
