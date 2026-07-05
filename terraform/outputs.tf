output "vpc_id" {
  value       = aws_vpc.main.id
  description = "מזהה ה-VPC שהוקם עבור הפרויקט"
}

output "wordpress_public_ip" {
  value       = aws_instance.wordpress_public.public_ip
  description = "כתובת ה-IP הציבורית של שרת הוורדפרס"
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.endpoint
  description = "נקודת החיבור הפנימית (Endpoint) של שרת ה-PostgreSQL"
}

output "geojson_bucket_name" {
  value       = aws_s3_bucket.ingest.id
  description = "שם באקט ה-S3 שנוצר לקליטת קבצי ה-GeoJSON"
}

output "public_docs_bucket_url" {
  value       = "https://${aws_s3_bucket.public_docs.bucket}.s3.amazonaws.com"
  description = "כתובת ה-URL הציבורית לגישה למסמכי התיעוד וה-Half-Pager"
}

# 🌟 תוספת קריטית עבור סקריפט ה-deploy.sh החכם שלנו:
output "public_docs_bucket_name" {
  value       = aws_s3_bucket.public_docs.id
  description = "שם הבאקט הציבורי עבור העלאת מסמך ה-Half-Pager בסקריפט הפריסה"
}
