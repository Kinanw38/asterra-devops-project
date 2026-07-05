#!/bin/bash
set -e

REGION=${1:-"us-east-1"}
ENVIRONMENT="asterra-prod"
IAC_STATE_BUCKET="${ENVIRONMENT}-terraform-state-bucket-2026"

echo "========================================================="
echo "🚀 INITIATING AUTOMATED DEPLOYMENT PROTOCOL IN REGION: $REGION"
echo "========================================================="

echo "[STEP 1] Validating and initializing remote Terraform State isolated S3 bucket..."
if ! aws s3api head-bucket --bucket "$IAC_STATE_BUCKET" --region "$REGION" 2>/dev/null; then
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$IAC_STATE_BUCKET" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$IAC_STATE_BUCKET" --region "$REGION" --create-bucket-configuration LocationConstraint=$REGION
    fi
fi

# 🔥 תיקון באג 1: שליפת ה-IP הציבורי הנוכחי שלך והפיכתו ל-CIDR תקין (/32) לטובת ה-RDP המאובטח
CURRENT_IP=$(curl -s https://checkip.amazonaws.com)
ALLOWED_RDP="${CURRENT_IP}/32"
echo "[INFO] Detected current host IP: $ALLOWED_RDP (Injecting to RDP Security Group safely)"

echo "[STEP 2] Launching infrastructure layer deployment utilizing Terraform manifests..."
cd ../terraform

terraform init -reconfigure \
    -backend-config="bucket=$IAC_STATE_BUCKET" \
    -backend-config="key=prod/terraform.tfstate" \
    -backend-config="region=$REGION"

# 🔥 הזרקת ה-Region, הסביבה ומשתנה ה-RDP כדי למנוע עצירה לבקשת קלט מהמשתמש
terraform apply \
    -var="aws_region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="allowed_rdp_ip=$ALLOWED_RDP" \
    -auto-approve

# 🔥 תיקון באג 2: קריאת שם הבאקט ישירות מה-Output החדש והנקי שיצרנו ב-outputs.tf ללא מניפולציות טקסט מסוכנות
PUBLIC_DOCS_BUCKET=$(terraform output -raw public_docs_bucket_name 2>/dev/null || terraform output -raw public_docs_bucket_url | sed 's/https:\/\///' | sed 's/\.s3\.amazonaws\.com//')

echo "[STEP 3] Deploying project half-pager overview document directly into the public delivery S3 bucket..."
cd ..
if [ -f "half-pager.md" ]; then
    aws s3 cp half-pager.md "s3://$PUBLIC_DOCS_BUCKET/half-pager.md" --region "$REGION"
elif [ -f "README.md" ]; then
    # מנגנון הגנה: אם שכחת וקראת לקובץ README.md, הוא עדיין יעלה אותו בהצלחה כקובץ התיעוד הנדרש
    aws s3 cp README.md "s3://$PUBLIC_DOCS_BUCKET/half-pager.md" --region "$REGION"
fi

echo "========================================================="
echo "🎉 INFRASTRUCTURE AND PLATFORMS DEPLOYED AND SYNCHRONIZED SUCCESSFULLY!"
echo "========================================================="
