#!/bin/bash
set -e

REGION=${1:-"us-east-1"}
ENVIRONMENT="asterra-prod"
IAC_STATE_BUCKET="${ENVIRONMENT}-terraform-state-bucket-2026"

echo "========================================================="
echo "⚠️  CRITICAL PROTOCOL: STARTING TOTAL ENVIRONMENT DESTRUCTION IN REGION: $REGION"
echo "========================================================="

cd ../terraform

# אתחול התיקייה מול ה-Backend כדי לוודא שטרפורם מכיר את ה-State הנוכחי גם בטרמינל חדש
terraform init -reconfigure \
    -backend-config="bucket=$IAC_STATE_BUCKET" \
    -backend-config="key=prod/terraform.tfstate" \
    -backend-config="region=$REGION"

# הרצת ה-Destroy עם כל המשתנים הנדרשים (כולל ערך דאמי ל-RDP) כדי למנוע בקשת קלט ידנית מהמשתמש
terraform destroy \
    -var="aws_region=$REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="allowed_rdp_ip=0.0.0.0/0" \
    -auto-approve

echo "========================================================="
echo "🧹 CLEANUP FINALIZED! All allocated cloud resources have been completely removed."
echo "========================================================="
