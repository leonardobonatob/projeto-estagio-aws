###VPC Creation and Configuration
resource "aws_vpc" "lambda_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "lambda-project-vpc"
  }
}

# Configuration for public resources - subnets and RT used by NAT Gateway
resource "aws_subnet" "public_subnet" {
  cidr_block = "10.0.3.0/24"
  vpc_id = aws_vpc.lambda_vpc.id
  availability_zone = "us-east-1a"

  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  cidr_block = "10.0.4.0/24"
  vpc_id = aws_vpc.lambda_vpc.id
  availability_zone = "us-east-1b"

  tags = {
    Name = "public-subnet-2"
  }
}

resource "aws_subnet" "public_subnet_3" {
  cidr_block = "10.0.5.0/24"
  vpc_id = aws_vpc.lambda_vpc.id
  availability_zone = "us-east-1c"

  tags = {
    Name = "public-subnet-3"
  }
}

resource "aws_subnet" "public_subnet_4" {
  cidr_block = "10.0.6.0/24"
  vpc_id = aws_vpc.lambda_vpc.id
  availability_zone = "us-east-1d"

  tags = {
    Name = "public-subnet-4"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.lambda_vpc.id
}

resource "aws_eip" "nat" {
  vpc      = true
}

resource "aws_nat_gateway" "lambda_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet.id

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.lambda_vpc.id

  route {
    cidr_block = var.external_ip
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_3" {
  subnet_id      = aws_subnet.public_subnet_3.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_4" {
  subnet_id      = aws_subnet.public_subnet_4.id
  route_table_id = aws_route_table.public_rt.id
}

# Configuration for private resources - subnets and RT used by Lambda
resource "aws_subnet" "private_subnet" {
  cidr_block = "10.0.1.0/24"
  vpc_id = aws_vpc.lambda_vpc.id
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  cidr_block = "10.0.2.0/24"
  vpc_id = aws_vpc.lambda_vpc.id
  availability_zone = "us-east-1c"

  tags = {
    Name = "private-subnet-2"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.lambda_vpc.id

  route {
    cidr_block = var.external_ip
    gateway_id = aws_nat_gateway.lambda_nat.id
  }
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "lambda_sg" {
  name_prefix = "lambda-project-sg"
  vpc_id = aws_vpc.lambda_vpc.id

  ingress {
    description = "Communication with APIs"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [var.external_ip]
  }
  ingress {
    description = "Communication with AD via LDAP"
    from_port = 389
    to_port = 389
    protocol = "tcp"
    cidr_blocks = [var.external_ip]
  }
  ingress {
    description = "Communication with AD via LDAP"
    from_port = 389
    to_port = 389
    protocol = "udp"
    cidr_blocks = [var.external_ip]
  }
  egress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    cidr_blocks = [var.external_ip]
  }
}

###Create a Secrets Manager to retrieve username/password from Managed AD administrator
# Creating a random admin password 
resource "random_password" "password_admin" {
  length           = 9
  special          = true
  min_upper        = 1
}

# Creating a AWS secret for AWS Microsoft AD admin
resource "aws_secretsmanager_secret" "ad_admin" {
   name = "dev/ADcredential-${random_password.randomstring.result}"
}
 
# Creating a AWS secret versions for AWS Microsoft AD admin
resource "aws_secretsmanager_secret_version" "sversion" {
  secret_id = aws_secretsmanager_secret.ad_admin.id
  secret_string = <<EOF
   {
    "username": "Admin",
    "password": "${random_password.password_admin.result}"
   }
EOF
}

## Password and username field must be aligned with an administrator AD user
#  "password": "${random_password.ad_admin.result}"

## Creating a AWS Managed MicrosoftAD
resource "aws_directory_service_directory" "aws_ad" {
  name     = "corp.educa${random_password.randomstring.result}.com"
  password = "${random_password.password_admin.result}"
  edition  = "Standard"
  type     = "MicrosoftAD"

  vpc_settings {
    vpc_id     = aws_vpc.lambda_vpc.id
    subnet_ids = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]
  }
}

resource "aws_workspaces_directory" "example" {
  directory_id = aws_directory_service_directory.aws_ad.id
  subnet_ids = [
    aws_subnet.public_subnet_3.id, aws_subnet.public_subnet_4.id
  ]

  self_service_permissions {
    change_compute_type  = false
    increase_volume_size = false
    rebuild_workspace    = false  
    restart_workspace    = true
    switch_running_mode  = false
  }

  workspace_access_properties {
    device_type_android    = "ALLOW"
    device_type_chromeos   = "ALLOW"
    device_type_ios        = "ALLOW"
    device_type_linux      = "ALLOW"
    device_type_osx        = "ALLOW"
    device_type_web        = "ALLOW"
    device_type_windows    = "ALLOW"
    device_type_zeroclient = "DENY"
  }

  workspace_creation_properties {
    #custom_security_group_id            = aws_security_group.example.id
    #default_ou                          = "OU=AWS,DC=Computers,DC=educa${random_password.randomstring.result},DC=com"
    enable_internet_access              = true
    #enable_maintenance_mode             = true
    #user_enabled_as_local_administrator = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.workspaces_default_service_access,
    aws_iam_role_policy_attachment.workspaces_default_self_service_access
  ]
}

data "aws_iam_policy_document" "workspaces" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["workspaces.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workspaces_default" {
  name               = "WorkspacesAD_DefaultRole"
  assume_role_policy = data.aws_iam_policy_document.workspaces.json
}

resource "aws_iam_role_policy_attachment" "workspaces_default_service_access" {
  role       = aws_iam_role.workspaces_default.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonWorkSpacesServiceAccess"
}

resource "aws_iam_role_policy_attachment" "workspaces_default_self_service_access" {
  role       = aws_iam_role.workspaces_default.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonWorkSpacesSelfServiceAccess"
}