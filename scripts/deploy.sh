#!/bin/bash
set -e

REGION=${1:-"us-east-1"}
ENVIRONMENT="asterra-prod"
IAC_STATE_BUCKET="${ENVIRONMENT}-terraform-state-bucket-2026"

echo "========================================================="
echo "🚀 INITIATING AUTOMATED DEPLOYMENT PROTOCOL IN REGION: $REGION"
echo "========================================================="

# יצירת סיסמאות רנדומליות בזיכרון (לא נשמרות בקבצים!)
GENERATED_RDP_PASS=$(openssl rand -base64 12 | tr -d '/+=')
GENERATED_WP_PASS=$(openssl rand -base64 12 | tr -d '/+=')
RDP_USER="asterra_dev"

echo "🔑 GENERATED SECRETS FOR THIS DEPLOYMENT:"
echo "   RDP Username: $RDP_USER"
echo "   RDP Password: $GENERATED_RDP_PASS"
echo "   (Make sure to copy these for your RDP connection!)"
echo "========================================================="

echo "[STEP 1] Validating and initializing remote Terraform State isolated S3 bucket..."
if ! aws s3api head-bucket --bucket "$IAC_STATE_BUCKET" --region "$REGION" 2>/dev/null; then
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$IAC_STATE_BUCKET" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$IAC_STATE_BUCKET" --region "$REGION" --create-bucket-configuration LocationConstraint=$REGION
    fi
fi

CURRENT_IP=$(curl -s https://checkip.amazonaws.com)
ALLOWED_RDP="${CURRENT_IP}/32"
echo "[INFO] Detected current host IP: $ALLOWED_RDP"

echo "[STEP 2] Launching infrastructure layer deployment utilizing Terraform manifests..."
cd ../terraform

terraform init -reconfigure \
    -backend-config="bucket=$IAC_STATE_BUCKET" \
    -backend-config="key=prod/terraform.tfstate" \
    -backend-config="region=$REGION"

# הזרקת המשתנים החדשים לטרהפורם
terraform apply \
    -var="aws_region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="allowed_rdp_ip=$ALLOWED_RDP" \
    -var="rdp_username=$RDP_USER" \
    -var="rdp_password=$GENERATED_RDP_PASS" \
    -var="wp_db_password=$GENERATED_WP_PASS" \
    -auto-approve

PUBLIC_DOCS_BUCKET=$(terraform output -raw public_docs_bucket_name 2>/dev/null || terraform output -raw public_docs_bucket_url | sed 's/https:\/\///' | sed 's/\.s3\.amazonaws\.com//')

echo "[STEP 3] Deploying project half-pager overview document..."
cd ..
if [ -f "half-pager.md" ]; then
    aws s3 cp half-pager.md "s3://$PUBLIC_DOCS_BUCKET/half-pager.md" --region "$REGION"
elif [ -f "README.md" ]; then
    aws s3 cp README.md "s3://$PUBLIC_DOCS_BUCKET/half-pager.md" --region "$REGION"
fi

echo "========================================================="
echo "🎉 DEPLOYMENT COMPLETE!"
echo "   RDP ACCESS: Use username '$RDP_USER' and password '$GENERATED_RDP_PASS'"
echo "========================================================="