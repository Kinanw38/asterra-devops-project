# קבוצת סאבנטים עבור בסיס הנתונים - חובה להגדיר לפחות שני אזורי זמינות שונים ב-VPC לקיום ה-RDS
resource "aws_db_subnet_group" "rds_subnets" {
  name       = "${var.environment}-rds-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  tags       = { Name = "${var.environment}-rds-subnet-group" }
}

# קבוצת אבטחה המאבטחת את ה-RDS ומאפשרת גישה פנימית בלבד מרכיבי ה-VPC
resource "aws_security_group" "rds_sg" {
  name        = "${var.environment}-rds-sg"
  description = "Restrict inbound PostgreSQL traffic to VPC internal components only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL port access from inside VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # חוסם לחלוטין כל תעבורה שלא מגיעה מתוך הרשת הפנימית של הפרויקט
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# הגדרת בסיס הנתונים המנוהל PostgreSQL RDS - מותאם בצורה מלאה למסגרת ה-Free Tier החינמית
resource "aws_db_instance" "postgres" {
  identifier             = "${var.environment}-postgres-db"
  allocated_storage      = 20 # הניפוח המינימלי הנדרש להרצה במסגרת ה-Free Tier
  max_allocated_storage  = 20
  engine                 = "postgres"
  engine_version         = "15" # גרסה יציבה ומומלצת התומכת באופן מובנה בהרחבות גיאוגרפיות (PostGIS)
  instance_class         = "db.t3.micro" # שימוש באינסטנס החינמי הזמין ביותר
  db_name                = "asterrageodb"
  username               = "asterra_admin"
  password               = jsondecode(aws_secretsmanager_secret_version.db_secret_val.secret_string)["password"]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true # קריטי כדי לאפשר הרצה חלקה של סקריפט ה-Destroy ללא תלות או המתנה לגיבוי סופי בתשלום
  publicly_accessible    = false # בידוד מוחלט מהאינטרנט החיצוני
}