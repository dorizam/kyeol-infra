#!/bin/bash
# 02-build-and-push.sh
# Docker 이미지 빌드 및 ECR Push
# 소스코드: ../source (레포지토리 기준)

set -e

AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
# 소스코드 경로 (스크립트 위치 기준 상대 경로)
SOURCE_DIR="$SCRIPT_DIR/../../source"

echo "=== Docker 이미지 빌드 및 ECR Push ==="
echo "AWS Account: $AWS_ACCOUNT_ID"
echo "소스코드 경로: $SOURCE_DIR"

# ECR 로그인
echo "1. ECR 로그인..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Terraform output에서 ECR URL 가져오기
cd "$(dirname "$0")/../terraform"
BACKEND_ECR=$(terraform output -raw ecr_backend_url)
STOREFRONT_ECR=$(terraform output -raw ecr_storefront_url)
cd - > /dev/null

echo "Backend ECR: $BACKEND_ECR"
echo "Storefront ECR: $STOREFRONT_ECR"

# Backend 빌드
echo "2. Backend 이미지 빌드..."
cd "$SOURCE_DIR/saleor"

# Dockerfile이 없으면 생성
if [ ! -f "Dockerfile" ]; then
    echo "   - Dockerfile 생성 중..."
    cat > Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

# 시스템 의존성 설치
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Python 의존성 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 소스코드 복사
COPY . .

# 정적 파일 수집
RUN python manage.py collectstatic --noinput

EXPOSE 8000

# 중요: proxy-headers 옵션 (트러블슈팅 6-2)
CMD ["uvicorn", "saleor.asgi:application", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*"]
EOF
fi

docker build -t $BACKEND_ECR:latest .
docker push $BACKEND_ECR:latest
echo "   - Backend 이미지 Push 완료"

# Storefront 빌드
echo "3. Storefront 이미지 빌드..."
cd "$SOURCE_DIR/storefront"

# 중요: Backend의 schema.graphql을 Storefront로 복사
# GraphQL codegen이 원격 서버 대신 로컬 스키마 파일을 사용하도록 함
# 트러블슈팅: Backend가 아직 배포 안됐으면 원격 URL에서 503 에러 발생
echo "   - Backend 스키마 복사 중..."
cp "$SOURCE_DIR/saleor/saleor/graphql/schema.graphql" ./schema.graphql

# Terraform output에서 도메인 가져오기 (Custom Domain 우선)
cd "$TERRAFORM_DIR"
CUSTOM_DOMAIN=$(terraform output -raw custom_domain_name 2>/dev/null || echo "")
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name 2>/dev/null || echo "localhost")
cd - > /dev/null

if [ -n "$CUSTOM_DOMAIN" ]; then
    FINAL_DOMAIN="$CUSTOM_DOMAIN"
else
    FINAL_DOMAIN="$CLOUDFRONT_DOMAIN"
fi

# 빌드 시 사용할 GraphQL URL (런타임용, 빌드 시에는 로컬 스키마 사용)
DUMMY_API_URL="https://${FINAL_DOMAIN}/graphql/"
DUMMY_STOREFRONT_URL="https://${FINAL_DOMAIN}"

echo "   - 로컬 스키마 파일 사용 (GITHUB_ACTION=generate-schema-from-file)"
echo "   - 런타임 GraphQL URL: $DUMMY_API_URL"

# GITHUB_ACTION 환경변수로 로컬 스키마 파일 사용하도록 설정
docker build \
    --build-arg NEXT_PUBLIC_SALEOR_API_URL="$DUMMY_API_URL" \
    --build-arg NEXT_PUBLIC_STOREFRONT_URL="$DUMMY_STOREFRONT_URL" \
    --build-arg NEXT_PUBLIC_DEFAULT_CHANNEL="default-channel" \
    --build-arg GITHUB_ACTION="generate-schema-from-file" \
    -t $STOREFRONT_ECR:latest .
docker push $STOREFRONT_ECR:latest
echo "   - Storefront 이미지 Push 완료"

echo ""
echo "=== 완료! ==="
echo "이미지가 ECR에 Push되었습니다."
