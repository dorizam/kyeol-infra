# KYEOL Saleor 배포 트러블슈팅 로그

**프로젝트:** KYEOL E-commerce (Saleor 기반)
**작성일:** 2025-12-24
**업데이트:** 진행 중

---

## 현재 세션 (2025-12-24)

### 1. Storefront 빌드 실패 - NEXT_PUBLIC_SALEOR_API_URL 누락

**발생 시점:** Docker 이미지 빌드 단계 (`02-build-and-push.sh`)

**증상:**
```
> saleor-storefront@0.1.0 generate /app
> graphql-codegen --config .graphqlrc.ts

Before GraphQL types can be generated, you need to set NEXT_PUBLIC_SALEOR_API_URL environment variable.
```

**원인:**
- Storefront의 GraphQL codegen이 빌드 시 스키마를 가져오려면 `NEXT_PUBLIC_SALEOR_API_URL` 환경변수가 필요
- 기존 Dockerfile에 `ARG`로 받도록 되어 있었으나, 빌드 스크립트에서 값을 전달하지 않음

**해결:**
```bash
# scripts/02-build-and-push.sh 수정
docker build \
    --build-arg NEXT_PUBLIC_SALEOR_API_URL="$DUMMY_API_URL" \
    --build-arg NEXT_PUBLIC_STOREFRONT_URL="$DUMMY_STOREFRONT_URL" \
    --build-arg NEXT_PUBLIC_DEFAULT_CHANNEL="default-channel" \
    -t $STOREFRONT_ECR:latest .
```

---

### 2. 빌드 스크립트 경로 오류 - SCRIPT_DIR 미정의

**발생 시점:** Storefront 빌드 단계

**증상:**
```
./scripts/02-build-and-push.sh: line 73: cd: /../terraform: No such file or directory
```

**원인:**
- 스크립트에서 `$SCRIPT_DIR` 변수를 사용했으나 정의하지 않음
- `cd`로 디렉토리 이동 후 상대 경로가 꼬임

**해결:**
```bash
# scripts/02-build-and-push.sh 상단에 추가
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

# CloudFront 도메인 가져올 때 서브셸 사용
CLOUDFRONT_DOMAIN=$(cd "$TERRAFORM_DIR" && terraform output -raw cloudfront_domain_name 2>/dev/null || echo "localhost")
```

---

### 3. GraphQL Codegen 503 에러 - Backend 미배포 상태에서 스키마 Fetch 실패

**발생 시점:** Docker 이미지 빌드 단계 (`02-build-and-push.sh`)

**증상:**
```
[FAILED] Failed to load schema from https://d1fl6vtd8wvy6m.cloudfront.net/graphql/:
[FAILED] Unexpected response: "<html>...<title>503 Service Temporarily Unavailable</title>..."
```

**원인:**
- GraphQL codegen이 빌드 시 원격 URL에서 스키마를 가져오려고 시도
- 하지만 Backend가 아직 배포되지 않아 503 에러 발생
- `.graphqlrc.ts`에서 `GITHUB_ACTION === "generate-schema-from-file"` 일 때 로컬 파일 사용 가능

**해결:**
1. **Backend의 schema.graphql을 Storefront로 복사:**
   ```bash
   # scripts/02-build-and-push.sh
   cp "$SOURCE_DIR/saleor/saleor/graphql/schema.graphql" ./schema.graphql
   ```

2. **Dockerfile에 GITHUB_ACTION ARG 추가:**
   ```dockerfile
   # Kyeol_sourcecode1/storefront/Dockerfile
   ARG GITHUB_ACTION
   ENV GITHUB_ACTION=${GITHUB_ACTION}
   ```

3. **빌드 시 환경변수 전달:**
   ```bash
   docker build \
       --build-arg GITHUB_ACTION="generate-schema-from-file" \
       ...
   ```

---

### 4. Next.js SSG 빌드 실패 - generateStaticParams API 호출 503 에러

**발생 시점:** Docker 이미지 빌드 단계 (`pnpm build` 중 "Collecting page data")

**증상:**
```
Collecting page data using 7 workers ...
HTTP error 503: Service Temporarily Unavailable
Error: Failed to collect page data for /[channel]/products/[slug]
```

**원인:**
- GraphQL codegen은 성공했지만, Next.js 빌드 중 SSG 단계에서 `generateStaticParams` 함수가 API 호출
- Backend가 아직 배포되지 않아 503 에러 발생
- 기존 코드에 예외 처리가 없어 빌드 전체가 실패

**해결:**
`products/[slug]/page.tsx`의 `generateStaticParams` 함수에 try-catch 추가:
```typescript
export async function generateStaticParams({ params }: { params: { channel: string } }) {
  try {
    const { products } = await executeGraphQL(ProductListDocument, {
      revalidate: 60,
      variables: { first: 20, channel: params.channel },
      withAuth: false,
    });
    const paths = products?.edges.map(({ node: { slug } }) => ({ slug })) || [];
    return paths;
  } catch (error) {
    console.warn("generateStaticParams: Failed to fetch products, returning empty array", error);
    return [];  // API 실패 시 빈 배열 반환 → SSR로 fallback
  }
}
```

---

### 5. Kubernetes Secrets 생성 실패 - Namespace not found

**발생 시점:** Secrets 생성 스크립트 실행 (`03-create-secrets.sh`)

**증상:**
```
Error from server (NotFound): namespaces "kyeol-dev" not found
```

**원인:**
- Secrets 생성 전에 네임스페이스가 먼저 존재해야 함
- 스크립트 실행 순서 문제

**해결:**
스크립트에 네임스페이스 자동 생성 단계 추가:
```bash
# scripts/03-create-secrets.sh 상단에 추가
kubectl apply -f "$SCRIPT_DIR/../kubernetes/01-namespace.yaml"
```

---

### 6. TargetGroupBinding 배포 실패 - IRSA Trust Policy OIDC 조건 오류

**발생 시점:** TargetGroupBinding 배포 시

**증상:**
```
admission webhook "mtargetgroupbinding.elbv2.k8s.aws" denied the request: 
operation error STS: AssumeRoleWithWebIdentity, api error AccessDenied: 
Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**원인:**
- IAM Role Trust Policy의 OIDC Condition 키가 잘못 설정됨
- 스크립트에서 OIDC ID만 추출하여 사용 (`C9E7CC...`)
- 올바른 형식: 전체 OIDC Provider URL (`oidc.eks.ap-northeast-2.amazonaws.com/id/C9E7CC...`)

**해결:**
```bash
# Trust Policy 수정
OIDC_PROVIDER="oidc.eks.ap-northeast-2.amazonaws.com/id/C9E7CC484A81959E22B66423AA6EBC28"

# 잘못된 Condition:
"C9E7CC...:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"

# 올바른 Condition:
"${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
```

수정 후 ALB Controller 재시작:
```bash
aws iam update-assume-role-policy --role-name aws-load-balancer-controller-kyeol-dev-eks --policy-document file://trust-policy-fixed.json
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

---

### 7. 마이그레이션 Job 실패 - ALLOWED_CLIENT_HOSTS 환경변수 누락

**발생 시점:** Django 마이그레이션 Job 실행

**증상:**
```
django.core.exceptions.ImproperlyConfigured: 
ALLOWED_CLIENT_HOSTS environment variable must be set when DEBUG=False.
```

**원인:**
- Saleor Backend는 `DEBUG=false` 일 때 `ALLOWED_CLIENT_HOSTS` 환경변수 필수
- ConfigMap에 해당 변수가 설정되지 않음

**해결:**
```bash
# ConfigMap 패치
kubectl patch configmap backend-config -n kyeol-dev --type merge \
  -p '{"data":{"ALLOWED_CLIENT_HOSTS":"d1fl6vtd8wvy6m.cloudfront.net"}}'
```

또는 `kubernetes/02-configmap.yaml` 수정:
```yaml
data:
  ALLOWED_CLIENT_HOSTS: "YOUR_CLOUDFRONT_DOMAIN"
```

---

### 8. Storefront Pod CrashLoopBackOff - Liveness Probe 실패

**발생 시점:** Storefront Pod 시작

**증상:**
```
Liveness probe failed: HTTP probe failed with statuscode: 500
Readiness probe failed: HTTP probe failed with statuscode: 500
```

**원인:**
- Storefront가 시작 시 Backend GraphQL API에 데이터를 요청
- Backend가 아직 마이그레이션되지 않았거나 환경 변수 문제로 500 에러 반환
- Probe가 `/` 경로를 체크하는데, 이 경로가 API 의존성이 있음

**해결:**
1. 먼저 Backend 환경변수 및 마이그레이션 문제 해결
2. Backend Pod가 정상 동작하면 Storefront도 자동 복구됨
3. 필요시 Probe 경로를 API 의존성 없는 경로로 변경 (예: `/api/health`)

---

### 9. 마이그레이션 Job 실패 - RSA_PRIVATE_KEY 환경변수 누락

**발생 시점:** Django 마이그레이션 Job 실행 (환경변수 수정 후 두 번째 시도)

**증상:**
```
django.core.exceptions.ImproperlyConfigured: 
Variable RSA_PRIVATE_KEY is not provided. It is required for running in not DEBUG mode.
```

**원인:**
- Job의 `envFrom`에서 ConfigMap만 참조하고 Secrets를 참조하지 않음
- `RSA_PRIVATE_KEY`는 Secrets에 저장되어 있음

**해결:**
`kubernetes/05-migration-job.yaml` 수정:
```yaml
spec:
  containers:
  - name: migrate
    envFrom:
    - configMapRef:
        name: backend-config
    - secretRef:                    # 추가!
        name: backend-secrets
    env:
    - name: RSA_PRIVATE_KEY         # 추가!
      valueFrom:
        secretKeyRef:
          name: backend-secrets
          key: RSA_PRIVATE_KEY
```

---

### 10. Dashboard 빌드 실패 - @material-ui/icons 패키지 누락

**발생 시점:** Dashboard 빌드 스크립트 실행 (`06-upload-dashboard.sh`)

**증상:**
```
[vite]: Rollup failed to resolve import "@material-ui/icons/Check" from 
"/home/.../node_modules/@saleor/macaw-ui/dist/esm/index.js".
```

**원인:**
- Node.js 버전 호환성 문제 (v24 vs 필요 ^20 || ^22)
- 의존성 패키지 `@material-ui/icons`가 제대로 설치되지 않음

**해결:**
```bash
cd ~/workspace/Kyeol_sourcecode1/saleor-dashboard
npm install @material-ui/icons --legacy-peer-deps
npm run build
```

---

### 11. Dashboard S3 업로드 실패 - Terraform Output 이름 불일치

**발생 시점:** Dashboard S3 업로드 시

**증상:**
```
Dashboard S3 버킷을 찾을 수 없습니다.
```

**원인:**
- 스크립트에서 `dashboard_s3_bucket_name` output 참조
- 실제 output 이름은 `s3_static_bucket_name`

**해결:**
```bash
# 올바른 버킷 이름 확인
terraform output s3_static_bucket_name
# 수동 업로드
aws s3 sync ~/workspace/Kyeol_sourcecode1/saleor-dashboard/build/dashboard/ s3://kyeol-dev-s3-static/dashboard/ --delete
```

---

### 12. Dashboard JS 로딩 실패 - MIME type text/html 오류

**발생 시점:** Dashboard 웹 접속 시

**증상:**
```
Failed to load module script: Expected a JavaScript-or-Wasm module script 
but the server responded with a MIME type of "text/html".
```

**원인:**
- Dashboard 빌드 시 `STATIC_URL` 환경변수가 설정되지 않음
- `vite.config.js`의 `base` 값이 기본값 `/`로 설정됨
- 브라우저가 `/index-xxx.js` 요청 → 파일 없음 → S3가 index.html(HTML) 반환

**해결:**
```bash
cd ~/workspace/Kyeol_sourcecode1/saleor-dashboard
rm -rf build
export STATIC_URL="/dashboard/"
export APP_MOUNT_URI="/dashboard/"
npm run build
# S3에 재업로드
aws s3 sync build/dashboard/ s3://kyeol-dev-s3-static/dashboard/ --delete
aws cloudfront create-invalidation --distribution-id E2SSJDK6IHQPKG --paths "/dashboard/*"
```

---

### 13. Dashboard 로그인 실패 - GraphQL 404 에러

**발생 시점:** Dashboard 로그인 시도

**증상:**
```
POST https://xxx.cloudfront.net/graphql 404 (Not Found)
Login went wrong. Please try again.
```

**원인:**
- Dashboard 빌드 시 `API_URL` 환경변수 누락
- index.html에 `API_URL: ""`로 빈 문자열 설정됨
- Dashboard가 빈 URL로 GraphQL 요청 시도

**해결:**
```bash
cd ~/workspace/Kyeol_sourcecode1/saleor-dashboard
rm -rf build
export API_URL="https://${CLOUDFRONT_DOMAIN}/graphql/"  # API_URI가 아닌 API_URL!
export STATIC_URL="/dashboard/"
export APP_MOUNT_URI="/dashboard/"
npm run build
# S3에 재업로드
aws s3 sync build/dashboard/ s3://kyeol-dev-s3-static/dashboard/ --delete
```

**중요**: 환경변수명이 `API_URI`가 아니라 `API_URL`입니다!

---

### 14. 상품 이미지 URL이 localhost:8000으로 표시

**발생 시점:** Storefront 상품 목록 확인

**증상:**
```
GET https://xxx.cloudfront.net/_next/image?url=http%3A%2F%2Flocalhost%3A8000%2Fthumbnail%2F...
```

**원인:**
- 상품 이미지가 로컬 파일 시스템에 저장됨
- Backend가 `localhost:8000` URL을 DB에 기록
- S3 미디어 스토리지 미설정

**해결:**
1. **Terraform에 S3 미디어 버킷 추가**
   ```hcl
   resource "aws_s3_bucket" "media" {
     bucket = "${var.project_name}-${var.environment}-s3-media"
   }
   ```

2. **CloudFront에 /media/*, /thumbnail/* 경로 추가**
   ```hcl
   ordered_cache_behavior {
     path_pattern     = "/media/*"
     target_origin_id = "s3-media"
   }
   ```

3. **Backend ConfigMap 설정**
   ```yaml
   AWS_STORAGE_BUCKET_NAME: "kyeol-dev-s3-media"
   AWS_S3_REGION_NAME: "ap-northeast-2"
   AWS_S3_CUSTOM_DOMAIN: "YOUR_CLOUDFRONT_DOMAIN"
   DEFAULT_FILE_STORAGE: "saleor.core.storages.S3MediaStorage"
   ```

4. **Dashboard에서 상품 이미지 재업로드**
   - 기존 이미지는 localhost URL이 DB에 저장됨
   - 새로 업로드해야 S3 URL로 저장됨

---

### 15. ALB Controller TargetGroupBinding 생성 실패 (AccessDenied)

**발생 시점:** `terraform destroy` → `terraform apply` 후 재배포

**증상:**
```
Error: admission webhook "mtargetgroupbinding.elbv2.k8s.aws" denied the request: 
unable to get target group IP address type: operation error STS: AssumeRoleWithWebIdentity, 
api error AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**원인:**
- EKS 클러스터 재생성 시 OIDC Provider ID가 변경됨
- 기존 ALB Controller IAM Role의 Trust Policy가 이전 OIDC ID 사용

**해결:**
`scripts/07-setup-alb-controller.sh`에서 Role 존재 시 Trust Policy 업데이트 로직 추가:

```bash
else
    # OIDC ID가 변경되었을 수 있으므로 Trust Policy 항상 업데이트
    aws iam update-assume-role-policy \
        --role-name $ROLE_NAME \
        --policy-document file:///tmp/trust-policy.json
fi
```

---

### 16. Pod CreateContainerConfigError - Secrets 미생성

**발생 시점:** `./scripts/04-deploy-apps.sh` 실행 후 Pod 상태 확인

**증상:**
```
backend-65c8bbfd5b-2x7sf      0/1     CreateContainerConfigError   0
storefront-77c6d7744f-6zmh4   0/1     CreateContainerConfigError   0
Error: secret "backend-secrets" not found
Error: secret "storefront-secrets" not found
```

**원인:**
- 배포 순서 오류
- `./scripts/03-create-secrets.sh`가 실행되지 않은 상태에서 Pod 배포

**해결:**
```bash
./scripts/03-create-secrets.sh
kubectl rollout restart deployment backend storefront -n kyeol-dev
```

---

### 17. Storefront CrashLoopBackOff - 마이그레이션 미실행

**발생 시점:** Pod 배포 후 상태 확인

**증상:**
```
storefront-77c6d7744f-6zmh4   0/1     CrashLoopBackOff   7 (42s ago)
```
로그 확인 시:
```
Internal Server Error
relation "menu_menu" does not exist
```

**원인:**
- 마이그레이션(`./scripts/05-run-migrations.sh`)이 실행되지 않음
- DB 테이블이 없어서 Backend가 500 에러 반환
- Storefront가 Backend GraphQL 호출 실패 → 비정상 종료 → 재시작 반복

**해결:**
```bash
./scripts/05-run-migrations.sh
kubectl rollout restart deployment storefront -n kyeol-dev
```

---

### 18. Superuser Job InvalidImageName 에러

**발생 시점:** 마이그레이션 Job 확인

**증상:**
```
create-superuser-d6zn5       0/1     Error
container "create-superuser" in pod "create-superuser-z77ms" is waiting to start: InvalidImageName
```

**원인:**
- `kubectl apply -f kubernetes/05-migration-job.yaml` 직접 실행 시 `${ECR_BACKEND_URL}` placeholder가 치환되지 않음
- 스크립트를 통하지 않고 직접 apply 시 발생

**해결:**
직접 kubectl run으로 Superuser 생성:
```bash
ECR_BACKEND_URL=$(terraform output -raw ecr_backend_url)
kubectl run create-superuser-manual \
  --image="$ECR_BACKEND_URL:latest" \
  --restart=Never \
  --namespace=kyeol-dev \
  --env="DATABASE_URL=$(kubectl get secret backend-secrets -n kyeol-dev -o jsonpath='{.data.DATABASE_URL}' | base64 -d)" \
  --command -- python manage.py createsuperuser --noinput --email admin@kyeol.com
```

---

### 19. Dashboard S3 Access Denied - 파일 미업로드

**발생 시점:** Dashboard URL 접속

**증상:**
```xml
<Error>
<Code>AccessDenied</Code>
<Message>Access Denied</Message>
</Error>
```

**원인:**
- S3 버킷에 Dashboard 파일이 업로드되지 않음 (`Total Objects: 0`)
- `./scripts/06-upload-dashboard.sh`가 실행되지 않음

**해결:**
```bash
./scripts/06-upload-dashboard.sh
```

---

### 20. Dashboard API_URL이 localhost로 설정됨

**발생 시점:** Dashboard 빌드 후 접속

**증상:**
Dashboard HTML 소스 확인 시:
```javascript
window.__SALEOR_CONFIG__ = {
    API_URL: "https://localhost/graphql/",
    ...
}
```

**원인:**
- `scripts/06-upload-dashboard.sh`에서 CloudFront 도메인을 가져오는 경로가 잘못됨
- `SCRIPT_DIR` 변수가 정의되지 않아 `cd /../terraform`으로 해석되어 실패
- fallback 값인 `localhost` 사용

**해결:**
`scripts/06-upload-dashboard.sh` 상단에 추가:
```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
```

CloudFront 도메인 가져오는 부분 수정:
```bash
CLOUDFRONT_DOMAIN=$(cd "$SCRIPT_DIR/../terraform" && terraform output -raw cloudfront_domain_name 2>/dev/null || echo "localhost")
```

---

### 21. Dashboard HTML 파일 다운로드됨 (Content-Type 오류)

**발생 시점:** Dashboard URL 접속

**증상:**
- 페이지가 렌더링되지 않고 `index.html` 파일이 자동 다운로드됨

**원인:**
- S3에 업로드된 `index.html`의 Content-Type이 `binary/octet-stream`으로 설정됨
- 브라우저가 HTML로 인식하지 못하고 파일 다운로드로 처리

**확인:**
```bash
aws s3api head-object --bucket kyeol-dev-s3-static --key dashboard/index.html --query 'ContentType'
# 결과: "binary/octet-stream"
```

**해결:**
1. **수동 수정:**
```bash
aws s3 cp s3://kyeol-dev-s3-static/dashboard/index.html s3://kyeol-dev-s3-static/dashboard/index.html \
    --content-type "text/html; charset=utf-8" \
    --cache-control "max-age=0,no-cache,no-store,must-revalidate" \
    --metadata-directive REPLACE
aws cloudfront create-invalidation --distribution-id E1213DYU9NKM70 --paths "/dashboard/*"
```

2. **스크립트 수정** (`scripts/06-upload-dashboard.sh`):
```bash
# HTML 파일 업로드 (Content-Type 명시적 설정)
aws s3 cp "$SOURCE_DIR/build/dashboard/index.html" "s3://${S3_BUCKET}/dashboard/index.html" \
    --content-type "text/html; charset=utf-8" \
    --cache-control "max-age=0,no-cache,no-store,must-revalidate"
```

---

### 22. Backend S3 업로드 권한 없음 (IRSA 설정)

**발생 시점:** 상품 이미지 업로드 시 (예상)

**증상:**
- Backend Pod가 S3에 이미지 업로드 시 권한 에러 발생 예상

**원인:**
- Backend Pod에 S3 접근 IAM 권한이 없음

**해결:**
1. **Terraform에 IRSA 추가** (`terraform/main.tf`):
```hcl
# Backend S3 업로드용 IAM Policy
resource "aws_iam_policy" "backend_s3_media" {
  name = "${var.project_name}-${var.environment}-backend-s3-media"
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [module.cloudfront.s3_media_bucket_arn, "${module.cloudfront.s3_media_bucket_arn}/*"]
    }]
  })
}

# Backend Service Account용 IAM Role (IRSA)
resource "aws_iam_role" "backend_s3_media" {
  name = "${var.project_name}-${var.environment}-role-backend-s3"
  assume_role_policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:kyeol-dev:backend-sa"
        }
      }
    }]
  })
}
```

2. **Kubernetes ServiceAccount 추가** (`kubernetes/03-backend-deployment.yaml`):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-sa
  namespace: kyeol-dev
  annotations:
    eks.amazonaws.com/role-arn: "${BACKEND_S3_ROLE_ARN}"
```

3. **Deployment에 serviceAccountName 추가:**
```yaml
spec:
  template:
    spec:
      serviceAccountName: backend-sa
```

---

### 23. 상품 이미지 URL이 localhost:8000으로 저장됨 (S3 미적용 상태에서 업로드)

**발생 시점:** Dashboard에서 상품 이미지 업로드 후 Storefront 확인

**증상:**
```
요청 URL: https://xxx.cloudfront.net/_next/image?url=http%3A%2F%2Flocalhost%3A8000%2Fthumbnail%2F...
상태 코드: 400 Bad Request
```
Storefront에서 상품 상세 페이지 접근 시 `500 Internal Server Error` 발생.

**원인:**
- S3 미디어 설정이 ConfigMap에 있지만, 해당 설정이 적용된 **Pod 재시작 전에** 이미지 업로드
- 이미지 URL이 `localhost:8000`으로 DB에 저장됨
- Next.js Image 컴포넌트가 localhost URL을 처리하지 못함

**확인 방법:**
```bash
# S3 설정 적용 여부 확인
kubectl exec deployment/backend -n kyeol-dev -- env | grep DEFAULT_FILE_STORAGE
# 결과: DEFAULT_FILE_STORAGE=saleor.core.storages.S3MediaStorage ← 정상
```

**해결:**
1. **기존 이미지 삭제 후 재업로드:**
   - Dashboard에서 해당 상품의 이미지 삭제
   - 새로 이미지 업로드
   - 저장

2. **QUICK_START.md 10단계 확인:**
   - Pod 재시작 후 S3 설정이 적용되었는지 **반드시** 확인
   ```bash
   kubectl exec deployment/backend -n kyeol-dev -- env | grep DEFAULT_FILE_STORAGE
   ```

**예방:**
- QUICK_START.md 10단계에서 S3 설정 확인 단계가 추가됨
- Pod 재시작 후 `DEFAULT_FILE_STORAGE=saleor.core.storages.S3MediaStorage` 확인 필수

---

### 24. S3 이미지 업로드 안됨 - AWS_MEDIA_BUCKET_NAME 환경변수 누락

**발생 시점:** Dashboard에서 상품 이미지 업로드 후 S3 버킷 확인 (2025-12-26)

**증상:**
- Dashboard에서 이미지 업로드해도 S3 버킷에 파일이 없음 (`Total Objects: 0`)
- 이미지 URL이 여전히 `localhost:8000`으로 저장됨

**확인:**
```bash
# S3 버킷 파일 확인
aws s3 ls s3://kyeol-dev-s3-media/ --recursive
# 결과: Total Objects: 0

# Django STORAGES 설정 확인
kubectl exec deployment/backend -n kyeol-dev -- python -c "
from django.conf import settings
import os, django, json
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'saleor.settings')
django.setup()
print(json.dumps(settings.STORAGES, indent=2))
"
# 결과: "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"} ← 문제!
```

**원인:**
- ConfigMap에 `AWS_STORAGE_BUCKET_NAME`을 설정했지만
- Saleor `settings.py`는 **`AWS_MEDIA_BUCKET_NAME`**을 확인하여 S3 스토리지를 활성화함
- 572번 줄: `if AWS_MEDIA_BUCKET_NAME: STORAGES["default"] = S3MediaStorage`

**해결:**
ConfigMap에 올바른 환경변수 추가:
```bash
kubectl patch configmap backend-config -n kyeol-dev --type merge -p '{
  "data": {
    "AWS_MEDIA_BUCKET_NAME": "kyeol-dev-s3-media",
    "AWS_MEDIA_CUSTOM_DOMAIN": "<CLOUDFRONT_DOMAIN>"
  }
}'
kubectl rollout restart deployment backend -n kyeol-dev
```

**코드 수정:**
`kubernetes/02-configmap.yaml`에 올바른 환경변수 추가:
```yaml
# 중요: Saleor은 AWS_MEDIA_BUCKET_NAME을 사용함 (AWS_STORAGE_BUCKET_NAME 아님!)
AWS_MEDIA_BUCKET_NAME: "${S3_MEDIA_BUCKET}"
AWS_MEDIA_CUSTOM_DOMAIN: "${CLOUDFRONT_DOMAIN}"
```

---

### 25. 썸네일 URL이 localhost:8000으로 생성됨 - PUBLIC_URL 환경변수 누락

**발생 시점:** S3 이미지 업로드 성공 후 GraphQL API 확인 (2025-12-26)

**증상:**
- S3에 이미지 파일이 정상 업로드됨 (`aws s3 ls`로 확인)
- 하지만 GraphQL API 응답의 썸네일 URL이 여전히 `localhost:8000`
```json
{
  "thumbnail": {
    "url": "http://localhost:8000/thumbnail/UHJvZHVjdE1lZGlhOjU=/256/"
  }
}
```

**확인:**
```bash
kubectl exec deployment/backend -n kyeol-dev -- python -c "
from django.conf import settings
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'saleor.settings')
django.setup()
print('PUBLIC_URL:', settings.PUBLIC_URL)
"
# 결과: PUBLIC_URL: None ← 문제!
```

**원인:**
- Saleor은 썸네일 URL 생성 시 `PUBLIC_URL` 환경변수를 사용
- `PUBLIC_URL`이 없으면 기본값 `http://localhost:8000` 사용
- S3 업로드는 성공하지만, API 응답의 URL이 잘못됨

**해결:**
ConfigMap에 `PUBLIC_URL` 환경변수 추가:
```bash
kubectl patch configmap backend-config -n kyeol-dev --type merge -p '{
  "data": {
    "PUBLIC_URL": "https://<CLOUDFRONT_DOMAIN>"
  }
}'
kubectl rollout restart deployment backend -n kyeol-dev
```

**코드 수정:**
`kubernetes/02-configmap.yaml`에 추가:
```yaml
# PUBLIC_URL - 썸네일 URL 생성에 필수! (트러블슈팅 25)
# 이 설정이 없으면 썸네일 URL이 localhost:8000으로 생성됨
PUBLIC_URL: "https://${CLOUDFRONT_DOMAIN}"
```

---

### 26. PUBLIC_URL https 설정 시 무한 리다이렉트 발생 (ERR_TOO_MANY_REDIRECTS)

**발생 시점:** PUBLIC_URL을 https로 설정 후 Dashboard/Storefront 접속 (2025-12-26)

**증상:**
- Dashboard: `ERR_TOO_MANY_REDIRECTS` 에러, 무한 로딩
- Storefront: "Something went wrong" 에러 페이지
- 브라우저 콘솔: `net::ERR_TOO_MANY_REDIRECTS`

**확인:**
```bash
kubectl exec deployment/backend -n kyeol-dev -- python -c "
from django.conf import settings
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'saleor.settings')
django.setup()
print('PUBLIC_URL:', settings.PUBLIC_URL)
print('ENABLE_SSL:', settings.ENABLE_SSL)
print('SECURE_SSL_REDIRECT:', getattr(settings, 'SECURE_SSL_REDIRECT', False))
"
# 결과:
# PUBLIC_URL: https://...
# ENABLE_SSL: True ← 문제!
# SECURE_SSL_REDIRECT: True ← 문제!
```

**원인:**
Saleor `settings.py`에서:
```python
if PUBLIC_URL:
    ENABLE_SSL = urlparse(PUBLIC_URL).scheme.lower() == "https"
if ENABLE_SSL:
    SECURE_SSL_REDIRECT = not DEBUG
```
- `PUBLIC_URL`이 `https://`이면 `ENABLE_SSL=True`가 됨
- `ENABLE_SSL=True`이면 `SECURE_SSL_REDIRECT=True`가 됨
- CloudFront→ALB→Backend 구조에서 Backend는 HTTP로 요청을 받음
- Backend가 HTTPS로 리다이렉트 → ALB가 다시 HTTP로 전달 → 무한 루프

**해결:**
`PUBLIC_URL`을 `http://`로 설정:
```bash
kubectl patch configmap backend-config -n kyeol-dev --type merge -p '{
  "data": {
    "PUBLIC_URL": "http://<CLOUDFRONT_DOMAIN>"
  }
}'
kubectl rollout restart deployment backend -n kyeol-dev
```

**코드 수정:**
`kubernetes/02-configmap.yaml`에서:
```yaml
# 중요: http로 설정해야 함! https로 하면 ENABLE_SSL=True가 되어 무한 리다이렉트 발생
PUBLIC_URL: "http://${CLOUDFRONT_DOMAIN}"
```

---

### 27. 썸네일 이미지 403 Forbidden (CloudFront 라우팅 오류)

**발생 시점:** 상품 이미지 업로드 후 썸네일 접근 시 (2025-12-26)

**증상:**
```
GET https://.../thumbnail/UHJvZHVjdE1lZGlhOjY=/1024/ 403 (Forbidden)
Mixed Content: The page ... requested an insecure element 'http://.../thumbnail/...'
```

**원인:**
- CloudFront에서 `/thumbnail/*` 경로가 S3로 라우팅되어 있었음
- 하지만 **Saleor 썸네일은 Backend에서 동적으로 생성**됨
- S3에는 썸네일 파일이 없으므로 403 에러 발생

**해결:**
`terraform/modules/cloudfront-s3/main.tf`에서 `/thumbnail/*` 경로를 ALB로 변경:
```hcl
# Thumbnail 동작: ALB (Backend에서 동적 생성)
ordered_cache_behavior {
  path_pattern     = "/thumbnail/*"
  target_origin_id = "alb"  # s3-media → alb 로 변경
  ...
}
```

2. **ALB에 `/thumbnail/*` 규칙 추가 (필수!):**
`terraform/modules/alb/main.tf`에 추가:
```hcl
resource "aws_lb_listener_rule" "http_backend_thumbnail" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 130
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
  condition {
    path_pattern { values = ["/thumbnail/*"] }
  }
}
```

적용:
```bash
cd terraform
terraform apply
```

---

### 28. 썸네일 캐시 파일 500 에러 (/thumbnails/* 경로 미설정)

**발생 시점:** 상품 이미지 업로드 후 썸네일 표시 시 (2025-12-26)

**증상:**
```
GET https://.../thumbnails/products/test3_product_xxx_thumbnail_1024.png 500 (Internal Server Error)
```
- `/thumbnail/*` 요청은 정상 (302 리다이렉트)
- 리다이렉트된 `/thumbnails/*` 경로에서 500 에러

**원인:**
- Backend가 썸네일 생성 후 **S3에 캐시**하고 `/thumbnails/*` 경로로 리다이렉트
- CloudFront에 `/thumbnails/*` behavior가 없어서 **Storefront(default)**로 전달됨
- Storefront는 해당 경로를 처리하지 못해 500 에러

**S3 확인:**
```bash
aws s3 ls s3://kyeol-dev-s3-media/thumbnails/ --recursive
# 결과: thumbnails/products/xxx_thumbnail_1024.png (파일 존재함)
```

**해결:**
`terraform/modules/cloudfront-s3/main.tf`에 추가:
```hcl
# /thumbnails/* -> S3 미디어 버킷
ordered_cache_behavior {
  path_pattern     = "/thumbnails/*"
  target_origin_id = "s3-media"
  ...
}
```

적용:
```bash
cd terraform
terraform apply
```

---

### 29. CloudFront OAC S3 Media 버킷 404 에러 (미해결 - 조사 중)

**발생 시점:** CloudFront /thumbnails/* 및 /media/* 경로 접근 시 (2025-12-26)

**증상:**
```
GET https://.../thumbnails/products/xxx_thumbnail_1024.png 404 (Not Found)
server: AmazonS3
```
- S3에 파일은 존재함 (`aws s3 ls`, `head-object` 성공)
- `aws s3 cp`로 다운로드 성공
- CloudFront를 통한 접근만 404 반환

**확인된 사항:**

| 항목 | 결과 |
|------|------|
| S3 파일 존재 | ✅ 파일 확인됨 |
| S3 Static 버킷 (Dashboard) | ✅ 200 OK - 정상 작동 |
| S3 Media 버킷 (썸네일) | ❌ 404 Not Found |
| CloudFront OAC 설정 | ✅ sigv4, always |
| S3 버킷 정책 | ✅ CloudFront 허용 |
| Origin 도메인 | ✅ 일치 |
| CloudFront 캐시 무효화 | ✅ 실행했으나 변화 없음 |

**이상한 점:**
- S3 Static 버킷은 동일한 OAC 설정으로 정상 작동
- S3 Media 버킷만 문제 발생
- API 응답에서 `S3OriginConfig`가 빈 값으로 존재 (레거시 충돌 가능성)

**추정 원인:**
1. CloudFront Distribution과 S3 Origin 연결 오류
2. OAC 서명 과정 문제
3. Terraform state와 실제 AWS 리소스 불일치

**해결 방법:**
```bash
cd terraform
terraform taint 'module.cloudfront.aws_cloudfront_distribution.main'
terraform apply
```

CloudFront Distribution 재생성으로 OAC 설정이 깨끗하게 적용됨 (5-10분 소요)

**⚠️ 중요: CloudFront 재생성 후 추가 작업 필요!**

CloudFront 도메인이 변경되므로 Backend ConfigMap 업데이트 필수:
```bash
# 방법 1: 스크립트 실행
./scripts/04-deploy-apps.sh

# 방법 2: 수동 패치
NEW_DOMAIN=$(terraform output -raw cloudfront_domain_name)
kubectl patch configmap backend-config -n kyeol-dev --type merge -p '{
  "data": {
    "PUBLIC_URL": "http://'$NEW_DOMAIN'",
    "AWS_MEDIA_CUSTOM_DOMAIN": "'$NEW_DOMAIN'",
    "AWS_S3_CUSTOM_DOMAIN": "'$NEW_DOMAIN'"
  }
}'
kubectl rollout restart deployment backend -n kyeol-dev
```

**해결 확인: ✅ 2025-12-26**
```
HTTP/2 200 
content-type: image/png
server: AmazonS3
```

---

### 30. CloudFront 도메인 변경 후 Dashboard/Storefront 오류

**발생 시점:** CloudFront Distribution 재생성 후 (2025-12-26)

**증상:**
```
Dashboard: POST https://d26n5vskhpamah.cloudfront.net/graphql/ net::ERR_NAME_NOT_RESOLVED
Storefront: An error occurred in the Server Components render
```
- API 요청이 **이전 CloudFront 도메인**으로 전송됨
- Dashboard 로그인 실패, Storefront 500 에러

**원인:**
1. **Dashboard**: S3에 업로드된 빌드 파일에 API_URI가 하드코딩됨
2. **Storefront**: Next.js의 `NEXT_PUBLIC_*` 환경변수는 **빌드타임**에만 적용됨
3. **Secret**: `storefront-secrets`에 이전 도메인 저장됨

**해결 방법:**

1. **스크립트 실행 (ConfigMap + Secret 업데이트):**
```bash
./scripts/04-deploy-apps.sh
kubectl rollout restart deployment backend storefront -n kyeol-dev
```

2. **Dashboard 재빌드 및 S3 업로드:**
```bash
cd ~/workspace/Kyeol_sourcecode1/saleor-dashboard
export API_URI="https://$(cd ~/workspace/kyeol-infra-new/terraform && terraform output -raw cloudfront_domain_name)/graphql/"
export STATIC_URL="/dashboard/"
npm run build
aws s3 sync build/dashboard s3://kyeol-dev-s3-static/dashboard/ --delete
```

3. **Storefront Docker 이미지 재빌드:**
```bash
cd ~/workspace/saleor_storefront/storefront
NEW_DOMAIN=$(cd ~/workspace/kyeol-infra-new/terraform && terraform output -raw cloudfront_domain_name)
docker build --no-cache \
  --build-arg NEXT_PUBLIC_SALEOR_API_URL="https://$NEW_DOMAIN/graphql/" \
  -t 827913617839.dkr.ecr.ap-northeast-2.amazonaws.com/kyeol-dev-storefront:latest .
docker push 827913617839.dkr.ecr.ap-northeast-2.amazonaws.com/kyeol-dev-storefront:latest
kubectl rollout restart deployment storefront -n kyeol-dev
```

**반영된 코드 수정:**
- `scripts/04-deploy-apps.sh`: storefront-secrets 자동 업데이트 로직 추가

**해결 확인: ✅ 2025-12-26**

---

### 31. Storefront Pod CrashLoopBackOff (Redirect Loop)

**발생 시점:** CloudFront 도메인 변경 및 Storefront 재배포 후 (2025-12-26)

**증상:**
```
Liveness probe failed: Get "/": stopped after 10 redirects
Readiness probe failed: Get "/": stopped after 10 redirects
```
- Pod가 `CrashLoopBackOff` 상태로 계속 재시작
- Liveness/Readiness probe 실패

**원인:**
- Storefront의 루트 페이지(`/`)가 `/${channel}` 경로로 리다이렉트
- Kubernetes probe가 `/` 경로를 체크할 때 무한 리다이렉트 발생
- `src/app/page.tsx`에 `redirect(`/${DefaultChannelSlug}`)` 코드가 있음

**해결 방법:**

1. **Health Check API 엔드포인트 생성:**
```typescript
// src/app/api/health/route.ts
export async function GET() {
  return new Response(JSON.stringify({ status: 'ok' }), { status: 200 });
}
```

2. **Kubernetes Deployment Probe 경로 변경:**
```yaml
# kubernetes/04-storefront-deployment.yaml
livenessProbe:
  httpGet:
    path: /api/health  # 변경: / -> /api/health
    port: 3000
readinessProbe:
  httpGet:
    path: /api/health  # 변경: / -> /api/health
    port: 3000
```

3. **Docker 이미지 재빌드 및 배포:**
```bash
cd ~/workspace/saleor_storefront/storefront
docker build --no-cache \
  --build-arg NEXT_PUBLIC_SALEOR_API_URL="https://$CLOUDFRONT_DOMAIN/graphql/" \
  -t $ECR_REPO:latest .
docker push $ECR_REPO:latest
kubectl delete pods -n kyeol-dev -l app=storefront
```

**반영된 코드:**
- `saleor_storefront/storefront/src/app/api/health/route.ts` (신규)
- `kubernetes/04-storefront-deployment.yaml` (Probe 경로 변경)

**해결 확인: ✅ 2025-12-26**

---

### 32. Storefront 500 Error (DYNAMIC_SERVER_USAGE)

**발생 시점:** Storefront 접속 시 (2025-12-26)

**증상:**
```
HTTP/2 500
[Error: An error occurred in the Server Components render...]
digest: 'DYNAMIC_SERVER_USAGE'
```
- Storefront 페이지 접속 시 500 Internal Server Error
- 로그에 `DYNAMIC_SERVER_USAGE` 에러 반복

**원인:**
- Next.js App Router에서 **정적 렌더링** 중에 **동적 함수**(cookies, headers 등) 호출
- 페이지나 레이아웃에 `dynamic` 설정이 없으면 기본적으로 정적 렌더링 시도
- Saleor Storefront가 채널/세션 정보를 위해 동적 데이터에 의존

**해결 방법:**

1. **Root Layout에 force-dynamic 추가:**
```typescript
// src/app/layout.tsx
export const dynamic = 'force-dynamic';

import { Inter } from "next/font/google";
// ... 나머지 코드
```

2. **Main Page에도 force-dynamic 추가:**
```typescript
// src/app/[channel]/(main)/page.tsx
export const dynamic = 'force-dynamic';

import { ProductListByCollectionDocument } from "@/gql/graphql";
// ... 나머지 코드
```

3. **Docker 이미지 재빌드 및 강제 배포:**
```bash
cd ~/workspace/saleor_storefront/storefront
docker build --no-cache \
  --build-arg NEXT_PUBLIC_SALEOR_API_URL="https://$CLOUDFRONT_DOMAIN/graphql/" \
  -t $ECR_REPO:latest .
docker push $ECR_REPO:latest
# 이미지 강제 갱신을 위해 Pod 삭제
kubectl delete pods -n kyeol-dev -l app=storefront
```

> ⚠️ **중요**: `kubectl rollout restart`만으로는 이미지가 갱신되지 않을 수 있음!
> `imagePullPolicy: Always`가 설정되어 있어도, 같은 태그(`latest`)일 경우 캐시된 이미지를 사용할 수 있습니다.
> 확실한 갱신을 위해 `kubectl delete pods`로 Pod를 삭제하세요.

**반영된 코드:**
- `saleor_storefront/storefront/src/app/layout.tsx` (force-dynamic 추가)
- `saleor_storefront/storefront/src/app/[channel]/(main)/page.tsx` (force-dynamic 추가)

**해결 확인: ✅ 2025-12-26**
```
HTTP/2 200
content-type: text/html; charset=utf-8
x-powered-by: Next.js
```

---

### 33. Dashboard GraphQL 404 Error (API_URL 미설정)

**발생 시점:** Dashboard 접속 시 (2025-12-26)

**증상:**
```
graphql:1 Failed to load resource: the server responded with a status of 404
Login went wrong. Please try again.
```
- Dashboard 로그인 페이지는 표시되지만 로그인 실패
- GraphQL API 요청이 상대 경로 `/graphql/`로 전송됨

**원인:**
- Saleor Dashboard는 **Vite** 기반 프로젝트
- Vite는 `export` 환경변수가 아닌 **`.env` 파일**에서 환경변수를 읽음
- `npm run build` 실행 전에 `.env.production` 파일이 있어야 함
- 빌드 결과물 `index.html`의 `__SALEOR_CONFIG__`에 `API_URL: ""`가 비어있으면 발생

**해결 방법:**

1. **`.env.production` 파일 생성:**
```bash
cd ~/workspace/Kyeol_sourcecode1/saleor-dashboard
CLOUDFRONT_DOMAIN=$(cd ~/workspace/kyeol-infra-new/terraform && terraform output -raw cloudfront_domain_name)
cat > .env.production << EOF
API_URL=https://$CLOUDFRONT_DOMAIN/graphql/
STATIC_URL=/dashboard/
APP_MOUNT_URI=/dashboard/
EOF
```

2. **Dashboard 재빌드:**
```bash
npm run build
```

3. **S3 업로드:**
```bash
aws s3 sync build/dashboard s3://kyeol-dev-s3-static/dashboard/ --delete
```

**반영된 코드:**
- `scripts/06-upload-dashboard.sh`: `.env.production` 자동 생성 로직 추가

**해결 확인: ✅ 2025-12-26**
```
API_URL: "https://d14m8g2ugmpwbc.cloudfront.net/graphql/"
```

---

### 34. Storefront 썸네일 이미지 403/508 에러 (Next.js Image Optimization)

**발생 시점:** Storefront 상품 페이지 접속 시 (2025-12-26)

**증상:**
```
GET /_next/image?url=http%3A%2F%2Fcloudfront.net%2Fthumbnail%2F... 403 Forbidden
⨯ upstream image response failed for http://cloudfront.net/thumbnail/... 403
```
- 상품 이미지가 표시되지 않음
- Next.js 로그에 `upstream image response failed` 에러

**원인:**
1. **Saleor Backend의 `PUBLIC_URL`이 `http://`로 설정됨** (무한 리다이렉트 방지를 위해 필수)
2. 썸네일 URL이 `http://cloudfront.net/thumbnail/...`로 생성됨
3. **CloudFront의 `/thumbnail/*` behavior가 `https-only`로 설정되어 HTTP 요청 거부**
4. Next.js Image Optimization이 HTTP URL을 fetch할 때 CloudFront가 거부

**해결 방법:**

1. **Terraform: CloudFront `/thumbnail/*` behavior 수정:**
```hcl
# terraform/modules/cloudfront-s3/main.tf
ordered_cache_behavior {
  path_pattern = "/thumbnail/*"
  # ...
  # 중요: allow-all로 설정해야 Next.js Image Optimization이 http:// URL을 fetch할 수 있음
  viewer_protocol_policy = "allow-all"
}
```

2. **Next.js: remotePatterns에 http 프로토콜 허용:**
```javascript
// next.config.js
images: {
  remotePatterns: [
    { protocol: "https", hostname: "*" },
    { protocol: "http", hostname: "*" },
  ],
},
```

3. **적용:**
```bash
cd ~/workspace/kyeol-infra-new/terraform
terraform apply -auto-approve

# Storefront 이미지 재빌드 및 배포
cd ~/workspace/saleor_storefront/storefront
docker build --no-cache \
  --build-arg NEXT_PUBLIC_SALEOR_API_URL="https://$CLOUDFRONT_DOMAIN/graphql/" \
  -t $ECR_REPO:latest .
docker push $ECR_REPO:latest
kubectl delete pods -n kyeol-dev -l app=storefront
```

**반영된 코드:**
- `terraform/modules/cloudfront-s3/main.tf`: `/thumbnail/*` viewer_protocol_policy = "allow-all"
- `saleor_storefront/storefront/next.config.js`: http 프로토콜 허용

**해결 확인: ✅ 2025-12-26**
```
HTTP/2 200
content-type: image/jpeg
x-nextjs-cache: MISS
```

---

### 35. Checkout Payment Methods 미표시 - Gateway ID 불일치

**발생 시점:** Checkout 페이지 접속 시 (2025-12-26)

**증상:**
- Checkout 페이지에서 Payment methods 섹션이 비어있음
- 로그인/배송주소 설정 후에도 결제 방법 선택 불가

**확인:**
```bash
# GraphQL로 availablePaymentGateways 확인
curl -s -X POST "https://<CLOUDFRONT>/graphql/" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { checkout(id: \"<CHECKOUT_ID>\") { availablePaymentGateways { id name } } }"}' \
  | python3 -m json.tool

# 결과: id: "mirumee.payments.dummy" (Backend 반환)
```

**원인:**
- **Backend가 반환하는 Gateway ID:** `mirumee.payments.dummy`
- **Storefront 코드에 정의된 ID:** `saleor.io.dummy-payment-app`
- ID 불일치로 Storefront가 결제 방법을 인식하지 못함

**해결:**
`storefront/src/checkout/sections/PaymentSection/DummyDropIn/types.ts` 수정:
```typescript
// Before
export const dummyGatewayId = "saleor.io.dummy-payment-app";

// After
export const dummyGatewayId = "mirumee.payments.dummy";
```

**반영된 코드:**
- `storefront/src/checkout/sections/PaymentSection/DummyDropIn/types.ts`

---

### 36. No available payment gateways 에러 - supportedPaymentGateways 배열 누락

**발생 시점:** Checkout 페이지에서 결제 시도 시 (2025-12-26)

**증상:**
```
Error: No available payment gateways
```
- Payment methods 섹션이 표시되지 않거나 에러 발생
- 콘솔에 "No available payment gateways" 에러

**원인:**
`utils.ts`의 `getFilteredPaymentGateways()` 함수가 `supportedPaymentGateways` 배열에 포함된 게이트웨이만 반환함:
```typescript
export const supportedPaymentGateways = [adyenGatewayId, stripeV2GatewayId] as const;
// dummyGatewayId가 포함되지 않아 Dummy Payment가 필터링됨
```

**해결:**
`storefront/src/checkout/sections/PaymentSection/utils.ts` 수정:
```typescript
import { dummyGatewayId } from "./DummyDropIn/types";

// Before
export const supportedPaymentGateways = [adyenGatewayId, stripeV2GatewayId] as const;

// After
export const supportedPaymentGateways = [adyenGatewayId, stripeV2GatewayId, dummyGatewayId] as const;
```

**반영된 코드:**
- `storefront/src/checkout/sections/PaymentSection/utils.ts`

---

### 37. Provided payment methods can not cover total amount - Transaction API 호환성 문제

**발생 시점:** Checkout 결제 버튼 클릭 시 (2025-12-26)

**증상:**
```
Provided payment methods can not cover the checkout's total amount
```
- "Make payment and create order" 버튼 클릭 시 에러
- 결제가 처리되지 않음

**원인:**
- **Saleor Dummy Plugin** (`mirumee.payments.dummy`): **구 Payment API** 사용
- **Storefront DummyComponent**: **새 Transaction API** (`transactionInitialize`) 사용
- 두 API가 **호환되지 않음**

Storefront 코드:
```typescript
// DummyComponent에서 Transaction API 사용
void transactionInitialize({
  checkoutId: checkout.id,
  paymentGateway: { id: dummyGatewayId, data: {...} }
})
```

**해결 방법 (2가지):**

**방법 1: Dashboard에서 Transaction Flow 비활성화**
1. Dashboard → Configuration → Channels → default-channel
2. **"Use Transaction flow when marking order as paid"** 토글 비활성화
3. Save

**방법 2: Allow unpaid orders 활성화**
1. 동일한 채널 설정 페이지
2. **"Allow unpaid orders"** 토글 활성화
3. 체크아웃 완료 후 나중에 결제 처리

**참고:**
- Saleor 공식 Dummy Payment App(Transaction API 지원)은 별도 설치 필요
- Stripe/Adyen 등 실제 결제 게이트웨이 사용 시 Transaction API 정상 작동

---

## 사전 반영된 트러블슈팅 (기존 로그 기반)

아래 이슈들은 기존 `TROUBLESHOOTING_LOG.md`, `troubleshoot2.md`를 분석하여 인프라 코드에 미리 반영되었습니다.
### 31. Storefront 로그인 세션 미유지 (JWT iss 불일치)
- **증상:** 로그인 성공 후 리다이렉트되지만 상단 유저 아이콘이 로그인 상태로 변경되지 않음. Backend 로그에 `Token's iss and request URL do not match` 에러 발생.
- **원인:**
  - Backend `PUBLIC_URL`이 `http://`로 설정되어 있어 JWT `iss`가 `http`로 발급됨.
  - Storefront는 `https://`로 API를 호출하여 `iss` 불일치 발생.
  - `PUBLIC_URL`을 `https`로 변경 시 `SECURE_SSL_REDIRECT` 자동 활성화로 무한 리다이렉트 발생.
- **해결:**
  - **커스텀 도메인 (dev.selffish234.cloud) 도입**: 안정적인 HTTPS 환경 구성.
  - **CloudFront Origin Protocol Policy "https-only" 설정**: CloudFront -> ALB 구간을 HTTPS로 암호화.
  - **ALB HTTPS Listener (443) 생성**: 백엔드와 안전한 통신 지원.
  - `PUBLIC_URL`을 `https://dev.selffish234.cloud`로 설정하여 JWT `iss` 일치시킴.

### 32. Storefront 로그인 버튼 무반응
- **증상:** 로그인 버튼 클릭 후 아무 반응 없음 (네트워크 탭에서는 200 OK).
- **원인:** `LoginForm.tsx`에 로그인 성공 후 페이지 이동 로직(`redirect`)이 없음.
- **해결:** `src/ui/components/LoginForm.tsx`에 `redirect("/default-channel")` 및 세션 동기화를 위한 `revalidatePath("/", "layout")` 추가.

### 33. API URL 301 무한 리다이렉트
- **증상:** `https://dev.selffish234.cloud/graphql/` 호출 시 301 리다이렉트가 반복됨.
- **원인:**
  - CloudFront(HTTPS) -> ALB(HTTP) -> Backend(HTTP) 구조에서 Backend가 `https`로 리다이렉트 시도.
  - `SECURE_PROXY_SSL_HEADER` 설정이 ALB의 헤더 처리 방식과 맞지 않거나 ALB가 헤더를 덮어씀.
- **해결:**
  - **CloudFront Origin Protocol Policy**를 `https-only`로 변경.
  - **ALB**에 ACM 인증서를 적용한 **HTTPS Listener (443)** 추가.
  - Backend는 `PUBLIC_URL=https://...` 설정만 유지 (`SECURE_PROXY_SSL_HEADER` 불필요).

### 34. Payment "Make payment and create order" 에러
- **증상:** Checkout에서 결제 시 "Provided payment methods can not cover the checkout's total amount" 에러 발생.
- **원인:** Storefront Dummy Plugin은 **Transaction flow**를 사용하려 하나, Saleor Backend의 Dummy Plugin(mirumee.payments.dummy)은 구형 Payment API를 사용함.
- **해결:** Saleor Dashboard -> Configuration -> Channels -> default-channel 설정에서 **"Allow unpaid orders" (미결제 주문 허용)** 활성화. (또는 Transaction flow 비활성화)

---

## 사전 반영된 트러블슈팅 내역 (Terraform/Code)

이 프로젝트(`kyeol-infra-new`) 및 `saleor_storefront`에는 위 트러블슈팅의 결과가 이미 반영되어 있습니다.

| # | 이슈 | 해결 방법 | 반영 파일 |
|---|------|----------|----------|
| 1 | EKS Node에 RDS SG 미부착 | Launch Template에 SG 명시적 지정 | `terraform/modules/eks/main.tf` |
| 2 | Amazon Linux 2 EOL | `AL2023_x86_64_STANDARD` AMI 사용 | `terraform/modules/eks/main.tf` |
| 3 | ALB-CloudFront 무한 루프 | HTTP Forward, `ENABLE_SSL=false` | `terraform/modules/alb/main.tf`, `kubernetes/02-configmap.yaml` |
| 4 | CloudFront SSL Mismatch | `origin_protocol_policy = http-only` | `terraform/modules/cloudfront-s3/main.tf` |
| 5 | Dashboard S3 Access Denied | CloudFront Function으로 index.html 추가 | `terraform/modules/cloudfront-s3/main.tf` |
| 6 | RSA_PRIVATE_KEY 누락 | Secrets 생성 스크립트에 포함 | `scripts/03-create-secrets.sh` |
| 7 | RDS db_name 누락 (503 에러) | `db_name = "saleor"` 필수 설정 | `terraform/modules/rds/main.tf` |
| 8 | Uvicorn Proxy Headers | `--proxy-headers --forwarded-allow-ips=*` | Backend Dockerfile |
| 9 | CSRF 신뢰 도메인 | `CSRF_TRUSTED_ORIGINS` 환경변수 | `scripts/03-create-secrets.sh` |
| 10 | NextAuth localhost 리다이렉트 | `NEXTAUTH_URL`, `AUTH_TRUST_HOST=true` | `kubernetes/04-storefront-deployment.yaml` |
| 11 | Storefront Probe Redirect Loop | `/api/health` 엔드포인트 사용 | `kubernetes/04-storefront-deployment.yaml`, `storefront/src/app/api/health/route.ts` |
| 12 | Storefront DYNAMIC_SERVER_USAGE | `force-dynamic` 설정 추가 | `storefront/src/app/layout.tsx`, `storefront/src/app/[channel]/(main)/page.tsx` |
| 13 | Dashboard API_URL 미설정 | `.env.production` 자동 생성 | `scripts/06-upload-dashboard.sh` |
| 14 | Storefront 썸네일 403 에러 | CloudFront allow-all + Next.js http 허용 | `terraform/modules/cloudfront-s3/main.tf`, `storefront/next.config.js` |
| 15 | Checkout Payment Gateway ID 불일치 | dummyGatewayId 수정 | `storefront/src/checkout/sections/PaymentSection/DummyDropIn/types.ts` |
| 16 | Checkout supportedPaymentGateways 누락 | supportedPaymentGateways에 dummyGatewayId 추가 | `storefront/src/checkout/sections/PaymentSection/utils.ts` |
| 17 | Storefront Login Session | redirect/revalidatePath 추가 | `storefront/src/ui/components/LoginForm.tsx` |
| 18 | 커스텀 도메인 설정 | CloudFront Alias, ACM, Route53, ALB HTTPS | `terraform/modules/cloudfront-s3`, `terraform/modules/alb` |
| 19 | Dashboard SPA 라우팅 | CloudFront Function (`/dashboard/index.html` Rewrite) | `terraform/modules/cloudfront-s3` |
| 20 | S3 Bucket 삭제 실패 | `force_destroy = true` | `terraform/modules/cloudfront-s3` |
| 21 | Terraform Import 필요 | `terraform import` (Listener/Record 충돌 시) | 문서 가이드 (36, 37번) |
| 22 | Checkout 계정 생성 실패 | Dummy Payment 로직에 `setShouldRegisterUser` 추가 | `src/checkout/sections/PaymentSection/DummyDropIn/dummyComponent.tsx` |
| 23 | Payment Methods 미표시 | Gateway ID 수정, Supported List 추가 | `src/checkout/sections/PaymentSection/DummyDropIn/types.ts`, `utils.ts` |
| 24 | Storefront 500 에러 / Pod 재시작 | Custom Domain 사용, Health API 추가 | `scripts/02-build-and-push.sh`, `src/app/api/health/route.ts` |


---

## 참고 문서

- [TROUBLESHOOTING_LOG.md](./TROUBLESHOOTING_LOG.md) - 이전 프로젝트 전체 트러블슈팅 로그
- [troubleshoot2.md](./troubleshoot2.md) - kyeol-infra 배포 트러블슈팅 로그

### 35. Dashboard 새로고침 시 403 AccessDenied Error (SPA 라우팅)
- **증상:** `/dashboard/products/UHJvZHVjdDo4` 등의 상세 페이지에서 새로고침 시 `AccessDenied` XML 에러 발생 (Status 403).
- **원인:**
  1. 클라이언트 사이드 라우팅(SPA)이므로 실제 S3 버킷에는 해당 경로의 디렉토리나 파일이 없음.
  2. S3는 객체가 없으면 403을 리턴함.
  3. CloudFront Function의 기존 로직이 `uri + '/index.html'` 형태로 잘못 리라이트함. (예: `/dashboard/products/../index.html`을 찾음)
- **해결:**
  `terraform/modules/cloudfront-s3/main.tf`의 CloudFront Function을 수정하여, 확장자가 없는 모든 `/dashboard/*` 요청을 `/dashboard/index.html`로 강제 리라이트하도록 변경.

### 36. Terraform Apply 에러: DuplicateListener
- **증상:** `terraform apply` 시 `Error: creating ELBv2 Listener ... DuplicateListener: A listener already exists` 에러 발생.
- **원인:** Terraform State 파일에는 리스너가 없다고 기록되어 있으나, 실제 AWS 환경에는 리스너(주로 HTTPS 443 포트)가 이미 존재하는 경우. (수동 생성 또는 이전 배포 잔재)
- **해결:**
  1. `aws elbv2 describe-listeners --load-balancer-arn <ALB_ARN>` 명령어로 충돌하는 리스너의 ARN 확인.
  2. `terraform import module.alb.aws_lb_listener.https[0] <LISTENER_ARN>` 명령어로 리스너를 Terraform State로 가져오기.

### 37. Terraform Apply 에러: Route53 Record Exists
- **증상:** `terraform apply` 시 `InvalidChangeBatch: [Tried to create resource record set ... but it already exists]` 에러 발생.
- **원인:** Terraform이 생성하려는 DNS 레코드가 이미 존재함.
- **해결:** `terraform import aws_route53_record.alias[0] ZONEID_DOMAIN_TYPE` 명령어로 Import.

### 38. Terraform Destroy 시 S3 BucketNotEmpty 에러
- **증상:** `terraform destroy` 시 S3 버킷 삭제 실패 (`BucketNotEmpty: The bucket you tried to delete is not empty`).
- **원인:** Terraform은 기본적으로 파일이 남아있는 S3 버킷을 삭제하지 않음 (안전 장치).
- **해결:**
  `terraform/modules/cloudfront-s3/main.tf`의 `aws_s3_bucket` 리소스에 다음 옵션 추가:
  ```hcl
  force_destroy = true
  ```

### 39. Checkout 계정 생성 실패 (Dummy Payment)
- **증상:** Checkout 과정에서 "I want to create account"를 체크하고 결제를 완료해도 계정이 생성되지 않음.
- **원인:** `Dummy Payment` 게이트웨이 구현체(`dummyComponent.tsx`)에서 결제 시 계정 생성을 트리거하는 `setShouldRegisterUser(true)` 호출이 누락됨.
- **해결:**
  `src/checkout/sections/PaymentSection/DummyDropIn/dummyComponent.tsx`의 `onInitalizeClick` 함수에 다음 로직 추가:
  ```typescript
  import { useCheckoutUpdateStateActions } from "@/checkout/state/updateStateStore";
  // ...
  const { setShouldRegisterUser } = useCheckoutUpdateStateActions();
  
  const onInitalizeClick = () => {
    setShouldRegisterUser(true); // 계정 생성 플래그 활성화
    validateAllForms(authenticated);
    // ...
  }
  ```

### 40. Payment Methods 미표시
- **증상:** Checkout 페이지에 결제 수단(Dummy Payment 등)이 나타나지 않음.
- **원인:**
  1. Frontend 코드(`utils.ts`)의 지원 목록(`supportedPaymentGateways`)에 Dummy Payment ID가 빠져 있음.
  2. `types.ts`에 정의된 Gateway ID(`saleor.io.dummy-payment-app`)가 실제 Saleor 플러그인 ID(`mirumee.payments.dummy`)와 일치하지 않음.
- **해결:**
  1. `src/checkout/sections/PaymentSection/DummyDropIn/types.ts`: ID를 `mirumee.payments.dummy`로 수정.
  2. `src/checkout/sections/PaymentSection/utils.ts`: `supportedPaymentGateways` 배열에 `dummyGatewayId` 추가.

### 41. Storefront 500 에러 및 Pod 무한 재시작 (CrashLoopBackOff)
- **증상 1 (Pod 재시작):** Storefront Pod가 실행 직후 계속 재시작됨 (`Liveness probe failed: HTTP probe failed with statuscode: 404`).
- **원인 1:** Kubernetes Deployment 설정상 `/api/health`로 헬스 체크를 시도하나, Next.js 앱에 해당 라우트가 구현되어 있지 않음.
- **해결 1:** `src/app/api/health/route.ts` 파일 생성하여 `{ status: "ok" }` 반환.

- **증상 2 (500 에러):** 웹 접속 시 `500 Internal Server Error` 발생.
- **원인 2:** Storefront가 Backend API를 호출할 때 CloudFront 기본 도메인(SSL 불일치 유발)을 사용함 (빌드 스크립트가 Custom Domain을 인식하지 못함).
- **해결 2:** `scripts/02-build-and-push.sh` 스크립트를 수정하여, Terraform Output에 `custom_domain_name`이 있으면 이를 우선적으로 API URL로 사용하도록 개선.

---

## 현재 세션 (2025-12-26)

### 42. Checkout 신규 생성 계정과 주문 연결 실패

**발생 시점:** Checkout 과정에서 "I want to create account" 체크 후 결제 완료

**증상:**
- Checkout에서 "I want to create account" 옵션으로 계정 생성 및 결제 완료
- 계정은 정상 생성됨 (Dashboard → Customers에 표시)
- 주문도 정상 생성됨 (Dashboard → Orders에 표시)
- **문제:** Dashboard → Customers에서 해당 계정을 클릭하면 "Recent Orders: No orders found"로 표시
- 주문 상세에서 Customer 필드가 비어있거나 다른 사용자로 표시됨

**디버깅 과정:**

#### 1단계: 기본 흐름 분석
- `useGuestUserForm.ts`: 회원가입 처리 담당
- `dummyComponent.tsx`: 결제 처리 담당
- 원래 흐름: `useGuestUserForm`에서 `userRegister` → `signIn` → `customerAttach` → `setRegisterState("success")` → `dummyComponent`가 결제 진행

#### 2단계: Race Condition 발견
콘솔 로그를 추가하여 확인:
```
[GuestUserForm] Starting signIn for: test8@test.com
(바로 주문 완료 페이지로 이동)
```
- `signIn result` 로그가 출력되지 않음
- `await signIn()`이 완료되기 전에 페이지가 리다이렉트됨

**원인 분석:**
1. **타이밍 문제:** `dummyComponent`의 `useEffect`가 `checkoutUpdateState === "success"`를 감지하면 즉시 결제 진행
2. **상태 업데이트 배치 처리:** React의 상태 업데이트 배치로 인해 `setRegisterState("success")` 전에 다른 곳에서 `userRegister` 스코프의 상태가 "success"로 설정됨
3. **비동기 완료 시점:** `signIn`과 `customerAttach`가 완료되기 전에 결제가 시작됨

**시도한 해결책들 (실패):**

1. `signIn` 전에 `signOut` 호출 시도:
   - 결과: `signOut()`이 예상치 않은 동작 유발, 흐름 중단

2. `useGuestUserForm`에서 `signIn`/`customerAttach`를 `setRegisterState("success")` 전에 실행:
   - 결과: 여전히 `signIn`이 완료되기 전에 페이지 이동

3. `setTimeout`으로 `setRegisterState("success")` 지연:
   - 결과: React 상태 업데이트 타이밍으로 인해 효과 없음

**최종 해결책:**

#### 1. Zustand Store 생성 (`useGuestUserFormStore.ts`)

자격 증명(email, password)을 컴포넌트 간에 공유하기 위한 Store 생성:

```typescript
// src/checkout/sections/GuestUser/useGuestUserFormStore.ts
import { create } from "zustand";

interface GuestUserFormState {
	email: string;
	password: string;
	setCredentials: (email: string, password: string) => void;
	clearCredentials: () => void;
}

export const useGuestUserFormStore = create<GuestUserFormState>((set) => ({
	email: "",
	password: "",
	setCredentials: (email, password) => set({ email, password }),
	clearCredentials: () => set({ email: "", password: "" }),
}));
```

#### 2. useGuestUserForm.ts 수정

`signIn`/`customerAttach` 로직을 제거하고, Store에 자격 증명만 저장:

```typescript
// src/checkout/sections/GuestUser/useGuestUserForm.ts
import { useGuestUserFormStore } from "@/checkout/sections/GuestUser/useGuestUserFormStore";

// onSubmit 내부 (userRegister 성공 후):
setSubmitInProgress(false);
setUserRegistrationDisabled(true);

// Save credentials to store
const { setCredentials } = useGuestUserFormStore.getState();
setCredentials(data.email, data.password);
console.log("[GuestUserForm] Credentials saved to store for:", data.email);

// Signal success after a small delay
setTimeout(() => {
    console.log("[GuestUserForm] Triggering setRegisterState success");
    setRegisterState("success");
}, 100);
```

UNIQUE 에러(이미 존재하는 계정) 처리에도 동일하게 credentials 저장:
```typescript
if (uniqueError) {
    setUserRegistrationDisabled(true);
    const { setCredentials } = useGuestUserFormStore.getState();
    setCredentials(data.email, data.password);
    setTimeout(() => setRegisterState("success"), 100);
}
```

#### 3. dummyComponent.tsx 수정

결제 직전에 **폴링 로직**으로 Store에서 credentials를 읽고 `signIn`/`customerAttach` 실행:

```typescript
// src/checkout/sections/PaymentSection/DummyDropIn/dummyComponent.tsx
import { useSaleorAuthContext } from "@saleor/auth-sdk/react";
import { useGuestUserFormStore } from "@/checkout/sections/GuestUser/useGuestUserFormStore";
import { useCheckoutCustomerAttachMutation } from "@/checkout/graphql";

const { signIn } = useSaleorAuthContext();
const [, customerAttach] = useCheckoutCustomerAttachMutation();

useEffect(() => {
    if (isWaitingForRegistration && checkoutUpdateState === "success") {
        setIsWaitingForRegistration(false);

        // 폴링으로 Store에 credentials가 설정될 때까지 대기
        const waitForCredentials = async () => {
            const maxAttempts = 10;
            for (let i = 0; i < maxAttempts; i++) {
                const formData = useGuestUserFormStore.getState();
                console.log(`[DummyComponent] Polling attempt ${i + 1}:`, { 
                    email: formData?.email, 
                    password: formData?.password ? "[REDACTED]" : undefined 
                });
                if (formData?.email && formData?.password) {
                    return { email: formData.email, password: formData.password };
                }
                await new Promise(resolve => setTimeout(resolve, 100));
            }
            return null;
        };

        const proceedWithPayment = async () => {
            const credentials = await waitForCredentials();
            
            if (credentials) {
                try {
                    console.log("[DummyComponent] Starting signIn for:", credentials.email);
                    await signIn({ email: credentials.email, password: credentials.password });
                    console.log("[DummyComponent] signIn complete, attaching customer...");
                    
                    await new Promise(resolve => setTimeout(resolve, 300));
                    
                    const attachResult = await customerAttach({ 
                        checkoutId: checkout.id, 
                        languageCode: "EN_US" as any 
                    });
                    console.log("[DummyComponent] customerAttach result:", attachResult);
                    
                    if (attachResult.data?.checkoutCustomerAttach?.errors?.length) {
                        console.error("[DummyComponent] customerAttach errors:", 
                            attachResult.data.checkoutCustomerAttach.errors);
                    } else {
                        console.log("[DummyComponent] Customer attached successfully!");
                    }
                } catch (e) {
                    console.error("[DummyComponent] signIn or customerAttach failed:", e);
                }
            }

            // 결제 진행
            await transactionInitialize({...});
            await onCheckoutComplete();
        };

        void proceedWithPayment();
    }
}, [isWaitingForRegistration, checkoutUpdateState, ...]);
```

**검증 결과 로그:**
```
[DummyComponent] Polling attempt 1-7: {email: '', password: undefined}
[GuestUserForm] Credentials saved to store for: test16@test.com
[DummyComponent] Polling attempt 8: {email: 'test16@test.com', password: '[REDACTED]'}
[DummyComponent] Starting signIn for: test16@test.com
[DummyComponent] signIn complete, attaching customer...
[DummyComponent] customerAttach result: {...}
[DummyComponent] Customer attached successfully!
```

**최종 확인:**
- Dashboard → Customers → `test16@test.com` → Recent Orders에 주문이 정상 표시됨 ✅
- Dashboard → Orders → 해당 주문 → Customer 필드에 `test16@test.com` 표시됨 ✅

**수정된 파일:**
| 파일 | 변경 사항 |
|------|-----------|
| `src/checkout/sections/GuestUser/useGuestUserFormStore.ts` | **신규 생성** - Zustand store |
| `src/checkout/sections/GuestUser/useGuestUserForm.ts` | signIn/customerAttach 로직 제거, Store에 credentials 저장 |
| `src/checkout/sections/PaymentSection/DummyDropIn/dummyComponent.tsx` | 폴링으로 Store 대기, signIn/customerAttach 실행 |

**핵심 교훈:**
1. React 상태 업데이트는 비동기이며 배치 처리될 수 있음
2. 컴포넌트 간 데이터 공유 시 Zustand Store가 유용함
3. 비동기 작업의 완료를 보장하려면 폴링 또는 이벤트 기반 통신이 필요
4. `signIn`과 같은 인증 관련 작업은 결제 처리 **직전**에 수행하는 것이 가장 안전함

---

### 27. 마이그레이션 Job 실행 시 YAML 유효성 검사 에러

**발생 시점:** `./scripts/05-run-migrations.sh` 실행

**증상:**
```
=== Database 마이그레이션 ===
1. 기존 마이그레이션 Job 정리...
2. 마이그레이션 Job 실행...
error: error validating "STDIN": error validating data: [apiVersion not set, kind not set]; if you choose to ignore these errors, turn validation off with --validate=false
```

**원인:**
- 스크립트에서 `grep -A 100 "db-migration" | head -35`로 YAML을 추출
- `grep "db-migration"`이 `name: db-migration` 줄(6번 줄)부터 시작하기 때문에
- 1~5번 줄에 있는 `apiVersion: batch/v1`과 `kind: Job`이 **누락됨**

**기존 코드 (문제):**
```bash
cat "$K8S_DIR/05-migration-job.yaml" | \
    sed "s|\${ECR_BACKEND_URL}|$ECR_BACKEND_URL|g" | \
    grep -A 100 "db-migration" | head -35 | \
    kubectl apply -f -
```

**해결:**
`awk`를 사용하여 YAML 문서 구분자(`---`)를 기준으로 올바르게 분리:

```bash
# 첫 번째 YAML 문서 (db-migration Job) 추출
cat "$K8S_DIR/05-migration-job.yaml" | \
    sed "s|\${ECR_BACKEND_URL}|$ECR_BACKEND_URL|g" | \
    awk '/^---/{n++} n==0' | \
    kubectl apply -f -

# 두 번째 YAML 문서 (create-superuser Job) 추출
cat "$K8S_DIR/05-migration-job.yaml" | \
    sed "s|\${ECR_BACKEND_URL}|$ECR_BACKEND_URL|g" | \
    awk '/^---/{n++} n==1' | \
    kubectl apply -f -
```

**수정 파일:** `scripts/05-run-migrations.sh`

**교훈:**
- `grep`으로 YAML 문서를 추출하면 필수 필드(`apiVersion`, `kind`)가 누락될 수 있음
- YAML 멀티 문서 파일은 `---` 구분자를 기준으로 `awk`나 `yq`로 분리하는 것이 안전함

---

### 28. 루트 경로(/) 리다이렉트가 CloudFront에서 동작하지 않음

**발생 시점:** Next.js의 `redirects()` 설정 후 CloudFront 접속 (2025-12-27)

**증상:**
- `next.config.js`에 `/` → `/default-channel` 리다이렉트 설정 추가
- ALB 직접 접속 시 `308 Permanent Redirect` 정상 동작
- **CloudFront 통해 접속 시 리다이렉트 안되고 `200 OK` 반환**

**확인 방법:**
```bash
# ALB 직접 (리다이렉트 됨 ✅)
curl -sI -k "https://kyeol-dev-alb-xxx.elb.amazonaws.com/" | head -5
# HTTP/1.1 308 Permanent Redirect
# location: /default-channel

# CloudFront (리다이렉트 안됨 ❌)
curl -sI "https://dev.selffish234.cloud/" | head -5
# HTTP/2 200 
```

**원인:**
- CloudFront가 Origin(ALB)에서 `308` 응답을 받으면 **자동으로 리다이렉트를 따라가서** 최종 페이지를 가져옴
- CloudFront는 최종 `200` 응답만 클라이언트에 반환

**해결:**
CloudFront Function을 추가하여 Edge에서 직접 리다이렉트 반환:

```hcl
# terraform/modules/cloudfront-s3/main.tf

# CloudFront Function 생성
resource "aws_cloudfront_function" "root_redirect" {
  name    = "${var.project_name}-${var.environment}-root-redirect"
  runtime = "cloudfront-js-2.0"
  publish = true

  code = <<-EOT
    function handler(event) {
        var request = event.request;
        var uri = request.uri;
        
        if (uri === '/' || uri === '') {
            return {
                statusCode: 301,
                statusDescription: 'Moved Permanently',
                headers: {
                    'location': { value: '/default-channel' },
                    'cache-control': { value: 'max-age=3600' }
                }
            };
        }
        
        return request;
    }
  EOT
}

# 기본 캐시 동작에 Function 연결
default_cache_behavior {
  ...
  function_association {
    event_type   = "viewer-request"
    function_arn = aws_cloudfront_function.root_redirect.arn
  }
}
```

**적용:**
```bash
cd terraform && terraform apply -auto-approve
```

**교훈:**
- CloudFront는 Origin의 리다이렉트를 자동으로 따라감 (클라이언트에 리다이렉트 전달 안함)
- Edge에서 리다이렉트가 필요하면 CloudFront Function 또는 Lambda@Edge 사용

---

### 29. 로그인 성공 후 리다이렉트 안됨 (로그인 페이지에 그대로 남음)

**발생 시점:** Storefront 로그인 후 (2025-12-27)

**증상:**
- `/default-channel/login`에서 로그인 성공 (인증 완료)
- 하지만 페이지가 `/default-channel`로 이동하지 않고 로그인 폼에 그대로 남음

**원인:**
- `LoginForm.tsx`의 Server Action에서 로그인 성공 후 **리다이렉트 로직이 없음**

**기존 코드 (문제):**
```typescript
// src/ui/components/LoginForm.tsx
action={async (formData) => {
  "use server";
  const { data } = await signIn({ email, password });
  
  if (data.tokenCreate.errors.length > 0) {
    // 에러 처리만 있음
  }
  // 성공 시 아무 동작 없음!
}}
```

**해결:**
1. `LoginForm.tsx` 수정 - 로그인 성공 시 `redirect()` 호출:
```typescript
import { redirect } from "next/navigation";

export async function LoginForm({ channel }: { channel: string }) {
  return (
    <form action={async (formData) => {
      "use server";
      const { data } = await signIn({ email, password });
      
      if (data.tokenCreate.errors.length > 0) {
        console.error("Login failed:", data.tokenCreate.errors);
      } else {
        // 로그인 성공 시 채널 홈으로 리다이렉트
        redirect(`/${channel}`);
      }
    }}>
      ...
    </form>
  );
}
```

2. `login/page.tsx` 수정 - channel params 전달:
```typescript
export default async function LoginPage({
  params,
}: {
  params: Promise<{ channel: string }>;
}) {
  const { channel } = await params;
  return <LoginForm channel={channel} />;
}
```

3. `LoginForm`을 사용하는 **다른 페이지도 수정** (예: `orders/page.tsx`):
```typescript
// 빌드 에러 발생: Property 'channel' is missing
return <LoginForm channel={channel} />;
```

**수정 파일:**
- `src/ui/components/LoginForm.tsx`
- `src/app/[channel]/(main)/login/page.tsx`
- `src/app/[channel]/(main)/orders/page.tsx`

**적용:**
```bash
./scripts/02-build-and-push.sh
kubectl rollout restart deployment storefront -n kyeol-dev
```

**교훈:**
- Server Action에서 페이지 이동은 `redirect()` 함수 사용 (Next.js)
- 컴포넌트에 필수 prop 추가 시 해당 컴포넌트를 사용하는 **모든 곳** 수정 필요
- TypeScript 빌드 에러는 누락된 사용처를 알려주므로 유용함

