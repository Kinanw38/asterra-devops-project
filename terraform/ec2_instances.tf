# שליפת ה-AMI העדכני ביותר עבור Amazon Linux 2023
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# קבוצת אבטחה עבור שרת ה-WordPress הציבורי
resource "aws_security_group" "wordpress_sg" {
  name        = "${var.environment}-wordpress-sg"
  vpc_id      = aws_vpc.main.id
  description = "Open standard HTTP access for the public WordPress web server"

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

# קבוצת אבטחה עבור שירותי העיבוד וסביבת ה-GIS הפרטית
resource "aws_security_group" "private_services_sg" {
  name        = "${var.environment}-private-services-sg"
  vpc_id      = aws_vpc.main.id
  description = "Isolate internal service communication and provide secure restricted RDP access"

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

# 1. שרת WordPress ציבורי (PaaS)
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
                    MYSQL_ROOT_PASSWORD: wp_root_secure_pass_2026
                    MYSQL_DATABASE: wordpress
                wordpress:
                  image: wordpress:latest
                  ports:
                    - "80:80"
                  environment:
                    WORDPRESS_DB_HOST: db:3306
                    WORDPRESS_DB_USER: root
                    WORDPRESS_DB_PASSWORD: wp_root_secure_pass_2026
                    WORDPRESS_DB_NAME: wordpress
              COMPOSE
              /usr/local/bin/docker-compose up -d
              EOF

  tags = { Name = "${var.environment}-wordpress-public-server" }
}

# 2. שרת פיתוח ועיבוד GIS פרטי + הרצת ה-SaaS Ingestion מתוך ה-ECR Docker Image
resource "aws_instance" "gis_private" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = "t3.micro"
  subnet_id            = aws_subnet.private_1.id
  vpc_security_group_ids = [aws_security_group.private_services_sg.id]
  iam_instance_profile = aws_iam_instance_profile.app_profile.name

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker awscli xrdp python3-pip gcc python3-devel

              # התקנת ממשק גרפי (XFCE) ושרת XRDP לעמידה בדרישת ה-RDP לתחנת העבודה
              dnf groupinstall -y "Xfce" || true
              systemctl start xrdp
              systemctl enable xrdp
              echo "asterra_dev:SecurePass2026!" | chpasswd

              # התקנת חבילות פיתוח מקומיות (GDAL & GeoPandas) על המכונה עבור השרת הפרטי
              dnf install -y gdal gdal-devel || true
              pip3 install geopandas shapely psycopg2-binary

              systemctl start docker
              systemctl enable docker

              # יצירת סקריפט הפעלה שממתין באופן חכם לעליית ה-Image ב-ECR (פותר מרוץ זמנים מול ה-CI/CD)
              mkdir -p /opt/asterra-runtime
              cat <<'LAUNCHER' > /opt/asterra-runtime/run-container.sh
              #!/bin/bash
              while ! docker info >/dev/null 2>&1; do sleep 2; done

              # לולאת ניסיון משיכה מ-ECR עד שהפייפליין מסיים לדחוף את ה-Image בפעם הראשונה
              while true; do
                aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.saas_app.repository_url}
                if docker pull ${aws_ecr_repository.saas_app.repository_url}:latest; then
                  echo "Image pulled successfully from ECR!"
                  break
                fi
                echo "Waiting for initial CI/CD pipeline image to block and land in ECR..."
                sleep 30
              done

              docker rm -f asterra-saas-container || true
              docker run -d \
                --name asterra-saas-container \
                --restart always \
                --log-driver=awslogs \
                --log-opt awslogs-group=/asterra/saas-engine-logs \
                --log-opt awslogs-create-group=true \
                --log-opt awslogs-region="${var.aws_region}" \
                -e INGEST_BUCKET_NAME="${aws_s3_bucket.ingest.id}" \
                -e DB_ENDPOINT="${aws_db_instance.postgres.endpoint}" \
                -e SECRET_NAME="${aws_secretsmanager_secret.db_secret.id}" \
                -e AWS_REGION="${var.aws_region}" \
                ${aws_ecr_repository.saas_app.repository_url}:latest
              LAUNCHER

              chmod +x /opt/asterra-runtime/run-container.sh

              # יצירת שירות מערכת (Systemd) שיריץ את סקריפט המשיכה וההפעלה אוטומטית ברקע
              cat <<'SERVICE' > /etc/systemd/system/asterra-saas.service
              [Unit]
              Description=Asterra SaaS Container Orchestrator Lifecycle Service
              After=network.target docker.service

              [Service]
              Type=simple
              ExecStart=/bin/bash /opt/asterra-runtime/run-container.sh
              Restart=on-failure
              RestartSec=10

              [Install]
              WantedBy=multi-user.target
              SERVICE

              systemctl daemon-reload
              systemctl start asterra-saas
              systemctl enable asterra-saas
              EOF

  tags = { Name = "${var.environment}-gis-private-workspace" }
}