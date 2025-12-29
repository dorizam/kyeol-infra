#!/bin/bash
# 05-run-migrations.sh
# Database 마이그레이션 실행

set -e

SCRIPT_DIR="$(dirname "$0")"
K8S_DIR="$SCRIPT_DIR/../kubernetes"
NAMESPACE="kyeol-dev"

echo "=== Database 마이그레이션 ==="

# Terraform output에서 ECR URL 가져오기
cd "$SCRIPT_DIR/../terraform"
ECR_BACKEND_URL=$(terraform output -raw ecr_backend_url)
cd - > /dev/null

# 기존 Job 삭제 (존재하는 경우)
echo "1. 기존 마이그레이션 Job 정리..."
kubectl delete job db-migration -n $NAMESPACE 2>/dev/null || true
kubectl delete job create-superuser -n $NAMESPACE 2>/dev/null || true

# 환경변수 치환 및 마이그레이션 Job만 먼저 실행 (Superuser는 마이그레이션 완료 후)
echo "2. 마이그레이션 Job 실행..."
cat "$K8S_DIR/05-migration-job.yaml" | \
    sed "s|\${ECR_BACKEND_URL}|$ECR_BACKEND_URL|g" | \
    awk '/^---/{n++} n==0' | \
    kubectl apply -f -

# 마이그레이션 완료 대기 (최대 10분)
# 주의: 첫 배포 시 마이그레이션 시간이 길 수 있음 (트러블슈팅 3-4)
echo "3. 마이그레이션 완료 대기 (최대 10분)..."
echo "   (시간이 오래 걸릴 수 있습니다. 로그 확인: kubectl logs -f job/db-migration -n $NAMESPACE)"

if kubectl wait --for=condition=complete job/db-migration -n $NAMESPACE --timeout=600s 2>/dev/null; then
    echo "   - 마이그레이션 완료!"
else
    echo "   - 타임아웃! 하지만 마이그레이션이 백그라운드에서 진행 중일 수 있습니다."
    echo "   - 로그 확인: kubectl logs job/db-migration -n $NAMESPACE"
    echo "   - 상태 확인: kubectl get jobs -n $NAMESPACE"
    exit 1
fi

# 마이그레이션 완료 후 Superuser Job 생성 (트러블슈팅: 동시 생성 시 테이블 미생성 에러)
echo "4. Superuser Job 생성..."
cat "$K8S_DIR/05-migration-job.yaml" | \
    sed "s|\${ECR_BACKEND_URL}|$ECR_BACKEND_URL|g" | \
    awk '/^---/{n++} n==1' | \
    kubectl apply -f -

# Superuser 생성 대기
echo "5. Superuser 생성 완료 대기..."
if kubectl wait --for=condition=complete job/create-superuser -n $NAMESPACE --timeout=120s 2>/dev/null; then
    echo "   - Superuser 생성 완료!"
    
    # Superuser 비밀번호 설정 (createsuperuser --noinput은 비밀번호가 없음)
    echo "6. Admin 비밀번호 설정..."
    kubectl run set-admin-password \
      --image="$ECR_BACKEND_URL:latest" \
      --restart=Never \
      --namespace=$NAMESPACE \
      --rm -i \
      --env="DATABASE_URL=$(kubectl get secret backend-secrets -n $NAMESPACE -o jsonpath='{.data.DATABASE_URL}' | base64 -d)" \
      --env="SECRET_KEY=$(kubectl get secret backend-secrets -n $NAMESPACE -o jsonpath='{.data.SECRET_KEY}' | base64 -d)" \
      --command -- python -c "
import django, os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'saleor.settings')
django.setup()
from saleor.account.models import User
user = User.objects.get(email='admin@kyeol.com')
user.set_password('admin123!')
user.save()
print('Password set successfully!')
" 2>/dev/null && echo "   - 비밀번호 설정 완료!" || echo "   - 비밀번호 설정 실패 (수동 설정 필요)"
else
    echo "   - Superuser 생성 중... 나중에 확인해주세요."
fi

echo ""
echo "=== 완료! ==="
echo "마이그레이션 상태: kubectl get jobs -n $NAMESPACE"
echo "Admin 계정: admin@kyeol.com / admin123!"
