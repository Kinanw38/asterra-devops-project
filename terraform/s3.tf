# באקט פרטי לקליטת קבצי ה-GeoJSON (SaaS Ingestion Bucket)
resource "aws_s3_bucket" "ingest" {
  bucket        = "${var.environment}-geojson-ingest-data-2026"
  force_destroy = true # מונע מה-Destroy להיתקע ומאפשר ניקוי מלא של הבאקט גם אם יש בתוכו קבצים
}

# חסימת גישה ציבורית לחלוטין לבאקט קליטת הנתונים על פי עקרונות אבטחת המידע
resource "aws_s3_bucket_public_access_block" "ingest_block" {
  bucket                  = aws_s3_bucket.ingest.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# באקט ציבורי להגשת ה-Half-Pager והתיעוד הטכני של הפרויקט לפי דרישות המטלה
resource "aws_s3_bucket" "public_docs" {
  bucket        = "${var.environment}-public-delivery-docs-2026"
  force_destroy = true
}

# פתיחת הגישה הציבורית באופן מבוקר לבאקט המסמכים הציבורי בלבד
resource "aws_s3_bucket_public_access_block" "public_docs_block" {
  bucket                  = aws_s3_bucket.public_docs.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# מדיניות באקט (Bucket Policy) המאפשרת לכל משתמש באינטרנט לקרוא את קבצי התיעוד (Read-Only)
resource "aws_s3_bucket_policy" "public_read" {
  bucket     = aws_s3_bucket.public_docs.id
  depends_on = [aws_s3_bucket_public_access_block.public_docs_block]
  policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.public_docs.arn}/*"
      }
    ]
  })
}