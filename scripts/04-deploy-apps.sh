#!/bin/bash
# 04-deploy-apps.sh
# Kubernetes 애플리케이션 배포

set -e

SCRIPT_DIR="$(dirname "$0")"
K8S_DIR="$SCRIPT_DIR/../kubernetes"
NAMESPACE="kyeol-dev"

echo "=== Kubernetes 애플리케이션 배포 ==="

# Terraform output에서 값 가져오기
cd "$SCRIPT_DIR/../terraform"
ECR_BACKEND_URL=$(terraform output -raw ecr_backend_url)
ECR_STOREFRONT_URL=$(terraform output -raw ecr_storefront_url)
BACKEND_TG_ARN=$(terraform output -raw backend_target_group_arn)
STOREFRONT_TG_ARN=$(terraform output -raw storefront_target_group_arn)
S3_MEDIA_BUCKET=$(terraform output -raw s3_media_bucket_name 2>/dev/null || echo "kyeol-dev-s3-media")
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name)
CUSTOM_DOMAIN=$(terraform output -raw custom_domain_name 2>/dev/null || echo "")
BACKEND_S3_ROLE_ARN=$(terraform output -raw backend_s3_role_arn 2>/dev/null || echo "")

if [ -n "$CUSTOM_DOMAIN" ] && [ "$CUSTOM_DOMAIN" != "No outputs found" ]; then
    FINAL_DOMAIN="$CUSTOM_DOMAIN"
else
    FINAL_DOMAIN="$CLOUDFRONT_DOMAIN"
fi
cd - > /dev/null

# 환경변수 치환 함수
substitute_and_apply() {
    local file=$1
    echo "   - 배포: $(basename $file)"
    cat $file | \
        sed "s|\${ECR_BACKEND_URL}|$ECR_BACKEND_URL|g" | \
        sed "s|\${ECR_STOREFRONT_URL}|$ECR_STOREFRONT_URL|g" | \
        sed "s|\${BACKEND_TARGET_GROUP_ARN}|$BACKEND_TG_ARN|g" | \
        sed "s|\${STOREFRONT_TARGET_GROUP_ARN}|$STOREFRONT_TG_ARN|g" | \
        sed "s|\${S3_MEDIA_BUCKET}|$S3_MEDIA_BUCKET|g" | \
        sed "s|\${CLOUDFRONT_DOMAIN}|$FINAL_DOMAIN|g" | \
        sed "s|\${BACKEND_S3_ROLE_ARN}|$BACKEND_S3_ROLE_ARN|g" | \
        kubectl apply -f -
}

# 1. Namespace 생성
echo "1. Namespace 생성..."
kubectl apply -f "$K8S_DIR/01-namespace.yaml"

# 2. ConfigMap 생성 (S3/CloudFront 변수 치환)
echo "2. ConfigMap 생성..."
substitute_and_apply "$K8S_DIR/02-configmap.yaml"

# 3. Backend 배포
echo "3. Backend 배포..."
substitute_and_apply "$K8S_DIR/03-backend-deployment.yaml"

# 4. Storefront 배포
echo "4. Storefront 배포..."
substitute_and_apply "$K8S_DIR/04-storefront-deployment.yaml"

# 4-1. Storefront Secrets 업데이트 (CloudFront 도메인 변경 대응)
echo "4-1. Storefront Secrets 업데이트..."
if kubectl get secret storefront-secrets -n $NAMESPACE &>/dev/null; then
    NEW_API_URL=$(echo -n "https://$FINAL_DOMAIN/graphql/" | base64)
    NEW_NEXTAUTH_URL=$(echo -n "https://$FINAL_DOMAIN" | base64)
    kubectl patch secret storefront-secrets -n $NAMESPACE --type merge -p "{
      \"data\": {
        \"SALEOR_API_URL\": \"$NEW_API_URL\",
        \"NEXTAUTH_URL\": \"$NEW_NEXTAUTH_URL\"
      }
    }"
    echo "   - storefront-secrets 업데이트 완료 (Domain: $FINAL_DOMAIN)"
else
    echo "   - storefront-secrets 없음 (05-run-migrations.sh에서 생성됨)"
fi

# 5. TargetGroupBinding 배포
echo "5. TargetGroupBinding 배포..."
substitute_and_apply "$K8S_DIR/06-target-group-binding.yaml"

# 배포 상태 확인
echo ""
echo "6. 배포 상태 확인..."
kubectl get pods -n $NAMESPACE
kubectl get svc -n $NAMESPACE

echo ""
echo "=== 완료! ==="
echo "Pod가 Running 상태가 될 때까지 기다려주세요."
echo "확인: kubectl get pods -n $NAMESPACE -w"
