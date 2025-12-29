#!/bin/bash
# 06-upload-dashboard.sh
# Dashboard 정적 파일 S3 업로드

set -e

# nvm 로드 (비-로그인 셸에서도 npm/node 사용 가능하도록)
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    set +e  # nvm 로드 중 에러 무시
    source "$NVM_DIR/nvm.sh" --no-use
    nvm use 22 2>/dev/null || nvm use default 2>/dev/null || true
    set -e
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 소스코드 경로 (스크립트 위치 기준 상대 경로)
SOURCE_DIR="$SCRIPT_DIR/../../source/saleor-dashboard"

echo "=== Dashboard S3 업로드 ==="

# Terraform output에서 버킷명 가져오기
cd "$(dirname "$0")/../terraform"
S3_BUCKET=$(terraform output -raw s3_static_bucket_name)
CLOUDFRONT_ID=$(terraform output -raw cloudfront_distribution_id)
cd - > /dev/null

echo "S3 버킷: $S3_BUCKET"
echo "소스 경로: $SOURCE_DIR"

# Dashboard 빌드
# 중요: STATIC_URL이 올바르게 설정되어야 JS 경로가 /dashboard/...로 설정됨
echo "1. Dashboard 빌드 중..."
cd "$SOURCE_DIR"

# Terraform output에서 도메인 가져오기 (Custom Domain 우선)
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
cd "$TERRAFORM_DIR"
CUSTOM_DOMAIN=$(terraform output -raw custom_domain_name 2>/dev/null || echo "")
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name 2>/dev/null || echo "localhost")
cd - > /dev/null

if [ -n "$CUSTOM_DOMAIN" ]; then
    FINAL_DOMAIN="$CUSTOM_DOMAIN"
    echo "   - Custom Domain 감지: $FINAL_DOMAIN"
else
    FINAL_DOMAIN="$CLOUDFRONT_DOMAIN"
    echo "   - CloudFront Domain 사용: $FINAL_DOMAIN"
fi

# .env.production 파일 생성 (Vite는 .env 파일에서 환경변수 로드)
# 트러블슈팅 33: export 환경변수가 아닌 .env.production 파일 필요
cat > "$SOURCE_DIR/.env.production" << EOF
API_URL=https://${FINAL_DOMAIN}/graphql/
STATIC_URL=/dashboard/
APP_MOUNT_URI=/dashboard/
EOF

echo "   - API_URL: https://${FINAL_DOMAIN}/graphql/"
echo "   - .env.production 파일 생성 완료"

# 기존 빌드 삭제 (경로 설정이 잘못됐을 수 있음)
rm -rf build

# pnpm 설치 확인 (saleor-dashboard는 pnpm 사용)
if ! command -v pnpm &> /dev/null; then
    echo "   - pnpm 설치 중..."
    npm install -g pnpm
fi

# CI=true 설정: husky prepare 스크립트 스킵 (.git 없는 환경에서 에러 방지)
# 의존성 설치
echo "   - 의존성 설치 중 (CI=true로 husky 스킵)..."
CI=true pnpm install

# 빌드
echo "   - 빌드 중..."
pnpm run build
cd - > /dev/null

# S3 업로드
echo "2. S3에 업로드 중..."
# 중요: dashboard/dashboard 중첩 방지 (트러블슈팅 5-4)
# HTML 파일은 별도로 업로드 (Content-Type 설정 필요)
aws s3 sync "$SOURCE_DIR/build/dashboard" "s3://${S3_BUCKET}/dashboard/" \
    --delete \
    --exclude "*.html" \
    --cache-control "max-age=31536000,public"

# HTML 파일 업로드 (Content-Type 명시적 설정 - 트러블슈팅 16)
echo "   - HTML 파일 Content-Type 설정 중..."
aws s3 cp "$SOURCE_DIR/build/dashboard/index.html" "s3://${S3_BUCKET}/dashboard/index.html" \
    --content-type "text/html; charset=utf-8" \
    --cache-control "max-age=0,no-cache,no-store,must-revalidate"

# CloudFront 캐시 무효화
echo "3. CloudFront 캐시 무효화..."
aws cloudfront create-invalidation \
    --distribution-id $CLOUDFRONT_ID \
    --paths "/dashboard/*"

echo ""
echo "=== 완료! ==="
echo "Dashboard URL: https://${FINAL_DOMAIN}/dashboard/"
