# Create a VPC
resource "aws_vpc" "dori_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "pri_subnet" {
  cidr_block        = "10.0.1.0/24"
  vpc_id            = aws_vpc.dori_vpc.id
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "pub_subnet" {
  cidr_block        = "10.0.2.0/24"
  vpc_id            = aws_vpc.dori_vpc.id
  availability_zone = "us-east-1b"
}

# Create an internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.dori_vpc.id
}

# Create a NAT gateway
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.pub_subnet.id
}

# Create an Elastic IP address for the NAT gateway
resource "aws_eip" "nat_eip" {
  vpc = true
}

# Create a route table for the private subnet
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.dori_vpc.id
}

# Add a route to the NAT gateway in the private route table
resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway.id
}

# Associate the private subnet with the private route table
resource "aws_route_table_association" "private_route_association" {
  subnet_id      = aws_subnet.pri_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_instance" "web" {
  ami           = "ami-0dfcb1ef8550277af"
  key_name = "testkey"
  instance_type = "t2.micro"
  subnet_id                   = aws_subnet.pub_subnet.id
  vpc_security_group_ids      = [aws_security_group.web_app_sg.id]

  tags = {
    Name = "${var.app_name}-web"
  }
  user_data = <<-EOF
  #!/bin/bash
  sudo apt update
  sudo apt install nginx -y
  sudo systemctl enable nginx
  sudo systemctl start nginx
  sudo apt install certbot python3-certbot-nginx -y
  sudo certbot --nginx --non-interactive --agree-tos --email dorianazodo@gmail.com --domains thatdorinda.com
  EOF
}


resource "aws_security_group" "web_app_sg" {
  name_prefix = "web_app_sg"
  vpc_id      = aws_vpc.dori_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "db" {
  ami           = "ami-065bb5126e4504910"
  key_name = "testkey"
  instance_type = "t2.micro"

  tags = {
    Name = "${var.app_name}-db"
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y postgresql-server

    /usr/bin/postgresql-setup initdb
    systemctl enable postgresql
    systemctl start postgresql

    sudo -u postgres psql -c "CREATE DATABASE ${var.db_name};"
    sudo -u postgres psql -c "CREATE USER ${var.db_user} WITH ENCRYPTED PASSWORD '${var.db_password}';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${var.db_name} TO ${var.db_user};"
  EOF
}

resource "aws_security_group" "db_sg" {
  name_prefix = "db_sg"
  vpc_id      = aws_vpc.dori_vpc.id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "web_lb" {
  name = "${var.app_name}-lb"

  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.pub_subnet.id, aws_subnet.pri_subnet.id]

  security_groups = [aws_security_group.web_app_sg.id]

  tags = {
    Name = "${var.app_name}-lb"
  }
}

resource "aws_lb_target_group" "web" {
  name        = "${var.app_name}-tg"
  target_type = "instance"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.dori_vpc.id

  health_check {
    enabled  = true
    interval = 10
    path     = "/health"
    port     = var.app_port
    protocol = "HTTP"
    matcher  = "200-399"
  }
}

resource "aws_lb_listener" "lb-http-listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = var.app_port
}

resource "aws_route53_zone" "main" {
  name = var.app_domain
}

resource "aws_acm_certificate" "dori_certificate" {
  domain_name       = var.app_domain
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "web_validation" {
  allow_overwrite = true
  name =  tolist(aws_acm_certificate.dori_certificate.domain_validation_options)[0].resource_record_name
  records = [tolist(aws_acm_certificate.dori_certificate.domain_validation_options)[0].resource_record_value]
  type = tolist(aws_acm_certificate.dori_certificate.domain_validation_options)[0].resource_record_type
  zone_id = aws_route53_zone.main.zone_id
  ttl = 60
}


resource "aws_route53_record" "web" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.app_domain
  type    = "A"

  alias {
    name                   = aws_lb.web_lb.dns_name
    zone_id                = aws_lb.web_lb.zone_id
    evaluate_target_health = true
  }
}