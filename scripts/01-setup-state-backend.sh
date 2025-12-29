#!/bin/bash
# 01-setup-state-backend.sh
# Terraform State용 S3 버킷 및 DynamoDB 테이블 생성

set -e

AWS_REGION="ap-northeast-3"
BUCKET_NAME="kyeol-terraform-state-sol"
TABLE_NAME="kyeol-terraform-locks-sol"

echo "=== Terraform State Backend 설정 ==="

# S3 버킷 생성
echo "1. S3 버킷 생성 중..."
if aws s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null; then
    echo "   - 버킷이 이미 존재합니다: $BUCKET_NAME"
else
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $AWS_REGION \
        --create-bucket-configuration LocationConstraint=$AWS_REGION
    
    # 버전 관리 활성화
    aws s3api put-bucket-versioning \
        --bucket $BUCKET_NAME \
        --versioning-configuration Status=Enabled
    
    # 암호화 활성화
    aws s3api put-bucket-encryption \
        --bucket $BUCKET_NAME \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    echo "   - 버킷 생성 완료: $BUCKET_NAME"
fi

# DynamoDB 테이블 생성
echo "2. DynamoDB 테이블 생성 중..."
if aws dynamodb describe-table --table-name $TABLE_NAME --region $AWS_REGION 2>/dev/null; then
    echo "   - 테이블이 이미 존재합니다: $TABLE_NAME"
else
    aws dynamodb create-table \
        --table-name $TABLE_NAME \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region $AWS_REGION
    
    echo "   - 테이블 생성 완료: $TABLE_NAME"
fi

echo ""
echo "=== 완료! ==="
echo "이제 terraform init을 실행할 수 있습니다."
