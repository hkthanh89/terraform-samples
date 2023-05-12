terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version    = "~> 3.0"
    }
  }

  backend "s3" {
    bucket = "terraform-samples"
    key    = "aws-sample-application/terraform.tfstate"
    region = "ap-southeast-1"
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-southeast-1"
}

resource "aws_instance" "instance_1" {
  ami = "ami-082b1f4237bd816a1"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.instances.name]
  user_data = <<-EOF
    #!/bin/bash
    echo "Hello, World 1" > index.html
    python3 -m http.server 8080 &
    EOF
}

resource "aws_instance" "instance_2" {
  ami = "ami-082b1f4237bd816a1"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.instances.name]
  user_data = <<-EOF
    #!/bin/bash
    echo "Hello, World 2" > index.html
    python3 -m http.server 8080 &
    EOF
}

resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "tf-aws-sample-application"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_crypto_conf" {
  bucket = aws_s3_bucket.bucket.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnet_ids" "default_subnet" {
  vpc_id = data.aws_vpc.default_vpc.id
}

resource "aws_security_group" "instances" {
  name = "tf-instance-security-group"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.instances.id

  from_port = 8080
  to_port = 8080
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group" "alb" {
  name = "tf-alb-security-group"
}

resource "aws_security_group_rule" "allow_alb_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port = 80
  to_port = 80
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_alb_all_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb.id

  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}


resource "aws_lb" "load_balancer" {
  name = "tf-web-app-lb"
  load_balancer_type = "application"
  subnets = data.aws_subnet_ids.default_subnet.ids
  security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn

  port = 80

  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_lb_target_group" "instances" {
  name = "tf-example-target-group"
  port = 8080
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default_vpc.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "instance_1" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id = aws_instance.instance_1.id
  port = 8080
}

resource "aws_lb_target_group_attachment" "instance_2" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id = aws_instance.instance_2.id
  port = 8080
}

resource "aws_lb_listener_rule" "instances" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
    path_pattern {
        values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.instances.arn
  }
}