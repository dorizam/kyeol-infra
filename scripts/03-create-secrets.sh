#!/bin/bash
# 03-create-secrets.sh
# Kubernetes Secrets 생성
# RSA_PRIVATE_KEY, DATABASE_URL, AUTH_SECRET 등

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="kyeol-dev"

echo "=== Kubernetes Secrets 생성 ==="

# 네임스페이스가 없으면 생성
echo "0. 네임스페이스 확인/생성..."
kubectl apply -f "$SCRIPT_DIR/../kubernetes/01-namespace.yaml"

# Terraform output에서 값 가져오기
cd "$(dirname "$0")/../terraform"
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
RDS_DB_NAME=$(terraform output -raw rds_database_name)
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name)
CUSTOM_DOMAIN=$(terraform output -raw custom_domain_name 2>/dev/null || echo "")
RDS_SECRET_ARN=$(terraform output -raw rds_secret_arn)
cd - > /dev/null

# 도메인 결정
if [ -n "$CUSTOM_DOMAIN" ] && [ "$CUSTOM_DOMAIN" != "No outputs found" ]; then
    FINAL_DOMAIN="$CUSTOM_DOMAIN"
    echo "Custom Domain ($CUSTOM_DOMAIN)을 사용합니다."
else
    FINAL_DOMAIN="$CLOUDFRONT_DOMAIN"
    echo "CloudFront Domain ($CLOUDFRONT_DOMAIN)을 사용합니다."
fi

# Secrets Manager에서 RDS 비밀번호 가져오기
echo "1. RDS 비밀번호 가져오는 중..."
RDS_SECRET=$(aws secretsmanager get-secret-value --secret-id $RDS_SECRET_ARN --query SecretString --output text)
RDS_USERNAME=$(echo $RDS_SECRET | jq -r '.username')
RDS_PASSWORD=$(echo $RDS_SECRET | jq -r '.password')

# DATABASE_URL 생성
DATABASE_URL="postgresql://${RDS_USERNAME}:${RDS_PASSWORD}@${RDS_ENDPOINT}/${RDS_DB_NAME}"

# Django SECRET_KEY 생성
echo "2. SECRET_KEY 생성 중..."
SECRET_KEY=$(openssl rand -hex 32)

# RSA_PRIVATE_KEY 생성 (트러블슈팅 3-1)
echo "3. RSA_PRIVATE_KEY 생성 중..."
RSA_PRIVATE_KEY=$(openssl genrsa 2048 2>/dev/null)

# AUTH_SECRET 생성 (Storefront용)
echo "4. AUTH_SECRET 생성 중..."
AUTH_SECRET=$(openssl rand -hex 32)

# Backend Secrets
echo "5. Backend Secrets 생성 중..."
kubectl create secret generic backend-secrets \
    --namespace=$NAMESPACE \
    --from-literal=DATABASE_URL="$DATABASE_URL" \
    --from-literal=SECRET_KEY="$SECRET_KEY" \
    --from-literal=RSA_PRIVATE_KEY="$RSA_PRIVATE_KEY" \
    --from-literal=CSRF_TRUSTED_ORIGINS="https://${FINAL_DOMAIN},https://${CLOUDFRONT_DOMAIN}" \
    --from-literal=ALLOWED_CLIENT_HOSTS="${FINAL_DOMAIN},${CLOUDFRONT_DOMAIN}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Storefront Secrets
echo "6. Storefront Secrets 생성 중..."
kubectl create secret generic storefront-secrets \
    --namespace=$NAMESPACE \
    --from-literal=AUTH_SECRET="$AUTH_SECRET" \
    --from-literal=SALEOR_API_URL="https://${FINAL_DOMAIN}/graphql/" \
    --from-literal=NEXT_PUBLIC_SALEOR_API_URL="https://${FINAL_DOMAIN}/graphql/" \
    --from-literal=NEXTAUTH_URL="https://${FINAL_DOMAIN}" \
    --from-literal=AUTH_TRUST_HOST="true" \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=== 완료! ==="
echo "CloudFront Domain: $CLOUDFRONT_DOMAIN"
echo "Secrets가 생성되었습니다."
