terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # version = "~> 4.16"
    }
  }

  backend "s3" {
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "sample_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "sample-vpc"
  }
}

resource "aws_subnet" "sample_subnet_public1" {
  vpc_id            = aws_vpc.sample_vpc.id
  cidr_block        = "10.0.0.0/20"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "sample-subnet-public1"
  }
}

resource "aws_subnet" "sample_subnet_public2" {
  vpc_id            = aws_vpc.sample_vpc.id
  cidr_block        = "10.0.16.0/20"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "sample-subnet-public2"
  }
}

resource "aws_subnet" "sample_subnet_private1" {
  vpc_id            = aws_vpc.sample_vpc.id
  cidr_block        = "10.0.128.0/20"
  availability_zone = "${var.aws_region}a"
  # map_public_ip_on_launch = true

  tags = {
    Name = "sample-subnet-private1"
  }
}

resource "aws_subnet" "sample_subnet_private2" {
  vpc_id            = aws_vpc.sample_vpc.id
  cidr_block        = "10.0.144.0/20"
  availability_zone = "${var.aws_region}b"
  # map_public_ip_on_launch = true

  tags = {
    Name = "sample-subnet-private2"
  }
}

resource "aws_internet_gateway" "sample_ig" {
  vpc_id = aws_vpc.sample_vpc.id

  tags = {
    Name = "sample-ig"
  }
}

resource "aws_eip" "sample_eip" {
  # instance = aws_instance.web.id
  domain = "vpc"
}

resource "aws_nat_gateway" "sample_ng" {
  allocation_id = aws_eip.sample_eip.id
  subnet_id     = aws_subnet.sample_subnet_public1.id

  tags = {
    Name = "sample-nat-gateway"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.sample_ig]
}

resource "aws_route_table" "sample_route_table_public" {
  vpc_id = aws_vpc.sample_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sample_ig.id
  }
}
resource "aws_route_table" "sample_route_table_private" {
  vpc_id = aws_vpc.sample_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    # gateway_id = aws_internet_gateway.sample_ig.id
    nat_gateway_id = aws_nat_gateway.sample_ng.id
  }
}

resource "aws_route_table_association" "sample_subnet_route_public1" {
  subnet_id      = aws_subnet.sample_subnet_public1.id
  route_table_id = aws_route_table.sample_route_table_public.id
}

resource "aws_route_table_association" "sample_subnet_route_public2" {
  subnet_id      = aws_subnet.sample_subnet_public2.id
  route_table_id = aws_route_table.sample_route_table_public.id
}
resource "aws_route_table_association" "sample_subnet_route_private1" {
  subnet_id      = aws_subnet.sample_subnet_private1.id
  route_table_id = aws_route_table.sample_route_table_private.id
}

resource "aws_route_table_association" "sample_subnet_route_private2" {
  subnet_id      = aws_subnet.sample_subnet_private2.id
  route_table_id = aws_route_table.sample_route_table_private.id
}

resource "aws_security_group" "sample_security_group" {
  name   = "sample-security-group"
  vpc_id = aws_vpc.sample_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    self        = "false"
    cidr_blocks = ["0.0.0.0/0"]
    description = "any"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------------
resource "aws_lb" "sample_ecs_alb" {
  name               = "sample-ecs-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sample_security_group.id]
  subnets            = [aws_subnet.sample_subnet_public1.id, aws_subnet.sample_subnet_public2.id]

  tags = {
    Name = "sample-ecs-alb"
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

resource "aws_lb_target_group" "sample_ecs_tg" {
  name        = "sample-ecs-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.sample_vpc.id

  health_check {
    path = "/"
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
    subnets         = [aws_subnet.sample_subnet_private1.id, aws_subnet.sample_subnet_private2.id]
    security_groups = [aws_security_group.sample_security_group.id]
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
