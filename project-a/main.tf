# VPC
resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "my-vpc"
  }
}

# Subnets
resource "aws_subnet" "public1_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public1-subnet"
  }
}

resource "aws_subnet" "public2_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public2-subnet"
  }
}

resource "aws_subnet" "private1_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private1-subnet"
  }
}

resource "aws_subnet" "private2_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "private2-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "my-igw"
  }
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public1_subnet_route" {
  subnet_id      = aws_subnet.public1_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public2_subnet_route" {
  subnet_id      = aws_subnet.public2_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public1_subnet.id
  tags = {
    Name = "my-nat-gateway"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "my-nat-eip"
  }
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "private1_subnet_route" {
  subnet_id      = aws_subnet.private1_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private2_subnet_route" {
  subnet_id      = aws_subnet.private2_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Key Pair
resource "tls_private_key" "my_private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.my_private_key.private_key_pem
  filename        = "my_private_key.pem"
  file_permission = "0400"
}

resource "aws_key_pair" "my_key_pair" {
  key_name   = "my_key_pair"
  public_key = tls_private_key.my_private_key.public_key_openssh
}

# Security Group
resource "aws_security_group" "my_security_group" {
  name        = "my-security-group"
  vpc_id      = aws_vpc.my_vpc.id
  description = "Allow SSH and HTTP inbound traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "my-security-group"
  }
}

# Launch Template
resource "aws_launch_template" "my_launch_template" {
  name_prefix            = "my-launch-template"
  image_id               = var.ami_id # Replace with the desired AMI ID
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.my_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.my_security_group.id]
  user_data              = filebase64("userdata.txt") # Replace with the path to your userdata script
  lifecycle {
    create_before_destroy = true
  }
}

# Autoscaling Group
resource "aws_autoscaling_group" "my_autoscaling_group" {
  name                      = "my-autoscaling-group"
  target_group_arns = [aws_lb_target_group.my_target_group.arn]
  min_size                  = 1
  max_size                  = 5
  desired_capacity          = 2
  health_check_type         = "EC2"
  health_check_grace_period = 300
  vpc_zone_identifier       = [aws_subnet.private1_subnet.id, aws_subnet.private2_subnet.id]
  launch_template {
    id      = aws_launch_template.my_launch_template.id
    version = "$Latest"
  }
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [load_balancers]
  }
}

# Load Balancer Target Group
resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id

  health_check {
    path     = "/"
    protocol = "HTTP"
    port     = "traffic-port"
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Load Balancer
resource "aws_lb" "my_load_balancer" {
  name               = "my-load-balancer"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public1_subnet.id, aws_subnet.public2_subnet.id]
  security_groups    = [aws_security_group.my_security_group.id]

  tags = {
    Name = "my-load-balancer"
  }
}

# Load Balancer Listener
# resource "aws_lb_listener" "my_listener" {
#   load_balancer_arn = aws_lb.my_load_balancer.arn
#   port              = 80
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.my_target_group.id
#   }
# }

resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}



resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.my_load_balancer.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn = aws_acm_certificate.my_certificate.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.id
  }
}

resource "aws_route53_zone" "public_zone" {
  name = var.root_domain_name  # Update with your desired domain name
}

resource "aws_route53_record" "lb_record" {
  zone_id = aws_route53_zone.public_zone.zone_id
  name    = "prod.${var.root_domain_name}"  # Update with your desired record name
  type    = "A"

  alias {
    name                   = aws_lb.my_load_balancer.dns_name
    zone_id                = aws_lb.my_load_balancer.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "my_certificate" {
  domain_name       = var.root_domain_name
  subject_alternative_names = ["*.${var.root_domain_name}"]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}


data "aws_route53_zone" "route53_zone" {
  name = var.root_domain_name
  private_zone = false
}

resource "aws_route53_record" "route53_record" {
  for_each = {
    for dvo in aws_acm_certificate.my_certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.route53_zone.zone_id
}

resource "aws_acm_certificate_validation" "acm_certificate_validation" {
  certificate_arn         = aws_acm_certificate.my_certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.route53_record : record.fqdn]
}


