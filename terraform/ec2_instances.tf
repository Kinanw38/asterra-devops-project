# 1. AMI for Amazon Linux 2023 (WordPress)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 2. AMI for Ubuntu 22.04 (GIS Workspace)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Elastic IP for WordPress
resource "aws_eip" "wordpress_eip" {
  instance = aws_instance.wordpress_public.id
  domain   = "vpc"
  tags     = { Name = "${var.environment}-wordpress-eip" }
}

# Security Group for Public WordPress
resource "aws_security_group" "wordpress_sg" {
  name        = "${var.environment}-wordpress-sg"
  vpc_id      = aws_vpc.main.id
  description = "Public HTTP access"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for GIS Workspace
resource "aws_security_group" "private_services_sg" {
  name        = "${var.environment}-private-services-sg"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.allowed_rdp_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 1. WordPress Instance
resource "aws_instance" "wordpress_public" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = "t3.micro"
  subnet_id            = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker
              systemctl start docker
              systemctl enable docker
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              mkdir -p /opt/wordpress && cd /opt/wordpress
              cat <<'COMPOSE' > docker-compose.yml
              version: '3.8'
              services:
                db:
                  image: mysql:5.7
                  environment:
                    MYSQL_ROOT_PASSWORD: ${var.wp_db_password}
                    MYSQL_DATABASE: wordpress
                wordpress:
                  image: wordpress:latest
                  ports:
                    - "80:80"
                  environment:
                    WORDPRESS_DB_HOST: db:3306
                    WORDPRESS_DB_USER: root
                    WORDPRESS_DB_PASSWORD: ${var.wp_db_password}
                    WORDPRESS_DB_NAME: wordpress
              COMPOSE
              /usr/local/bin/docker-compose up -d
              EOF
  tags = { Name = "${var.environment}-wordpress-public-server" }
}

# 2. GIS Workspace Instance (Ubuntu)
resource "aws_instance" "gis_private" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t3.micro"
  subnet_id            = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.private_services_sg.id]
  iam_instance_profile = aws_iam_instance_profile.app_profile.name

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io awscli python3-pip python3-venv gdal-bin libgdal-dev xfce4 xfce4-goodies xrdp
              systemctl start xrdp
              systemctl enable xrdp
              useradd -m -s /bin/bash ${var.rdp_username}
              echo "${var.rdp_username}:${var.rdp_password}" | chpasswd
              usermod -aG docker,sudo ${var.rdp_username}
              echo "xfce4-session" > /home/${var.rdp_username}/.xsession
              chown ${var.rdp_username}:${var.rdp_username} /home/${var.rdp_username}/.xsession
              pip3 install geopandas shapely psycopg2-binary
              systemctl start docker
              systemctl enable docker

              mkdir -p /opt/asterra-runtime
              cat <<'LAUNCHER' > /opt/asterra-runtime/run-container.sh
              #!/bin/bash
              while ! docker info >/dev/null 2>&1; do sleep 2; done
              while true; do
                aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.saas_app.repository_url}
                if docker pull ${aws_ecr_repository.saas_app.repository_url}:latest; then break; fi
                sleep 30
              done
              docker run -d --name asterra-saas-container --restart always \
                -e INGEST_BUCKET_NAME="${aws_s3_bucket.ingest.id}" \
                -e DB_ENDPOINT="${aws_db_instance.postgres.endpoint}" \
                -e SECRET_NAME="${aws_secretsmanager_secret.db_secret.id}" \
                -e AWS_REGION="${var.aws_region}" \
                --log-driver=awslogs \
                --log-opt awslogs-group=/asterra/saas-engine-logs \
                --log-opt awslogs-region=${var.aws_region} \
                --log-opt awslogs-create-group=true \
                ${aws_ecr_repository.saas_app.repository_url}:latest
              LAUNCHER
              chmod +x /opt/asterra-runtime/run-container.sh

              cat <<'SERVICE' > /etc/systemd/system/asterra-saas.service
              [Unit]
              Description=Asterra SaaS Service
              After=network.target docker.service
              [Service]
              Type=simple
              ExecStart=/bin/bash /opt/asterra-runtime/run-container.sh
              Restart=on-failure
              [Install]
              WantedBy=multi-user.target
              SERVICE
              systemctl daemon-reload
              systemctl start asterra-saas
              systemctl enable asterra-saas
              EOF
  tags = { Name = "${var.environment}-gis-private-workspace" }
}