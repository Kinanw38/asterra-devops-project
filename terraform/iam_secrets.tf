# יצירת סיסמה רנדומלית מאובטחת ללא תווים מיוחדים למניעת שבירת סקריפטים ומחרוזות חיבור
resource "random_password" "db_password" {
  length  = 16
  special = false
}

# שמירת הסיסמה ב-AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "${var.environment}-db-credentials-v5"
  recovery_window_in_days = 0 # מאפשר מחיקה מיידית ב-Destroy ללא המתנה של 7 ימים
}

resource "aws_secretsmanager_secret_version" "db_secret_val" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = "asterra_admin"
    password = random_password.db_password.result
    dbname   = "asterrageodb"
  })
}

# IAM Role עבור מכונת ה-EC2
resource "aws_iam_role" "app_role" {
  name = "${var.environment}-app-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "://amazonaws.com" }
      }
    ]
  })
}

# פוליסי מורחב הכולל הרשאות קריאה מ-ECR כדי שהמכונה תוכל למשוך את ה-Docker Image של ה-SaaS
resource "aws_iam_policy" "app_policy" {
  name = "${var.environment}-app-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        # תוקן ל-HCL2 Expressions (הורדו הגרשיים והסוגריים המיותרים)
        Resource = [aws_s3_bucket.ingest.arn, "${aws_s3_bucket.ingest.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.db_secret.arn]
      },
      {
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*" # ECR GetAuthorizationToken דורש סימון כללי לפי חוקי AWS
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["arn:aws:logs:*:*:*"]
      }
    ]
  })
}

# שיוך הפוליסי ל-Role של האפליקציה
resource "aws_iam_role_policy_attachment" "app_attach" {
  role       = aws_iam_role.app_role.name
  policy_arn = aws_iam_policy.app_policy.arn
}

# יצירת ה-Instance Profile המקשר את ה-Role למכונת ה-EC2
resource "aws_iam_instance_profile" "app_profile" {
  name = "${var.environment}-app-profile"
  role = aws_iam_role.app_role.name
}

# יצירת ECR Repository לאחסון אימג' ה-Docker של האפליקציה
resource "aws_ecr_repository" "saas_app" {
  name                 = "asterra-saas-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # תוקן חזרה ל-force_delete כדי להתאים ל-AWS Provider העדכני
}
