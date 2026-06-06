# =============================================================================
# AWS Network Resources
# =============================================================================

resource "aws_vpc" "this" {
  cidr_block           = var.aws_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "demo-vpc"
    Project     = "terraform-aws-interconnect-demo"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.aws_subnet_cidr
  map_public_ip_on_launch = false
  tags = {
    Name        = "demo-private-subnet"
    Project     = "terraform-aws-interconnect-demo"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpn_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name        = "demo-vgw"
    Project     = "terraform-aws-interconnect-demo"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

resource "aws_dx_gateway_association" "this" {
  dx_gateway_id         = aws_dx_gateway.this.id
  associated_gateway_id = aws_vpn_gateway.this.id
  allowed_prefixes      = [var.aws_vpc_cidr]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = var.gcp_vpc_cidr
    gateway_id = aws_vpn_gateway.this.id
  }
  tags = {
    Name        = "demo-private-rt"
    Project     = "terraform-aws-interconnect-demo"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "ec2" {
  name        = "demo-ec2-sg"
  description = "Demo EC2 - ICMP and SSH from GCP VPC CIDR"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "ICMP from GCP"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = [var.gcp_vpc_cidr]
  }

  ingress {
    description = "SSH from GCP"
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = [var.gcp_vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "demo-ec2-sg"
    Project     = "terraform-aws-interconnect-demo"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

# SSM Session Manager access from a private subnet (no bastion required)
resource "aws_security_group" "vpc_endpoints" {
  name        = "demo-vpc-endpoints-sg"
  description = "Allow HTTPS from the VPC to interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.aws_vpc_cidr]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "demo-vpc-endpoints-sg"
    Project     = "terraform-aws-interconnect-demo"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# =============================================================================
# AWS Compute + SSM
# =============================================================================

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name               = "demo-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "demo-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name

  tags = {
    Name        = "demo-ec2-instance"
    Project     = "terraform-aws-interconnect-demo"
    Environment = "demo"
    ManagedBy   = "Terraform"
  }
}
