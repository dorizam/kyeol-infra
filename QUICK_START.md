# KYEOL E-commerce AWS 인프라 빠른 시작 가이드

이 가이드를 따라 Saleor 기반 E-commerce 사이트를 AWS에 배포할 수 있습니다.

> ⚠️ **중요**: 트러블슈팅 내용은 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) 참고

---

## 📋 사전 요구사항

### 필수 도구

```bash
# 필수 도구 확인
aws --version        # aws-cli/2.x 이상
terraform --version  # 1.5.0 이상
kubectl version      # 1.28 이상
docker --version     # 24.x 이상
helm version         # 3.x 이상
node --version       # v20 또는 v22 권장 (Dashboard 빌드용)

# AWS 자격증명 확인
aws sts get-caller-identity
```

### 레포지토리 Clone

```bash
# 레포지토리 clone
git clone https://github.com/selffish234/dev-saleor.git
cd dev-saleor
```

### 디렉토리 구조 (clone 후)

```
dev-saleor/
├── infrastructure/          # 인프라 코드 (이 가이드에서 사용)
│   ├── terraform/
│   ├── kubernetes/
│   └── scripts/
├── source/                  # Saleor 소스코드
│   ├── saleor/              # Backend (Django)
│   ├── saleor-dashboard/    # Admin Dashboard (React)
│   └── storefront/          # Storefront (Next.js)
├── QUICK_START.md           # 이 가이드
└── TROUBLESHOOTING.md       # 트러블슈팅 문서
```

---

## 🚀 배포 단계

### 1단계: 스크립트 권한 설정

```bash
cd ./infrastructure

# 스크립트 실행 권한 부여
chmod +x scripts/*.sh
```

### 2단계: Terraform State Backend 설정

```bash
# State Backend 생성 (S3 + DynamoDB)
./scripts/01-setup-state-backend.sh
```

### 2.5단계: 도메인 및 HTTPS 설정 ⭐ 중요

커스텀 도메인과 HTTPS를 사용하려면 `terraform/terraform.tfvars` 파일을 생성해야 합니다.

**1) terraform.tfvars.example 복사:**
```bash
cd terraform
# cp terraform.tfvars.example terraform.tfvars
```

**2) 자신의 환경에 맞게 수정:**
```hcl
# terraform/terraform.tfvars

# 프로젝트 설정 (필수 - 자신의 이름으로 변경)
project_name = "your-project"  # 예: "saleor-joon"
environment  = "dev"

# 커스텀 도메인 설정 (선택 - 자신의 도메인으로 변경)
create_custom_domain           = true
domain_name                    = "dev.your-domain.com"  # 예: "dev.joon.shop"
route53_zone_id                = "YOUR_ROUTE53_ZONE_ID"
acm_certificate_arn_cloudfront = "arn:aws:acm:us-east-1:YOUR_ACCOUNT:certificate/xxx"
acm_certificate_arn_alb        = "arn:aws:acm:ap-northeast-3:YOUR_ACCOUNT:certificate/xxx"
```

> **💡 도메인 없이 테스트하려면:**
> `create_custom_domain = false`로 설정하면 CloudFront 기본 도메인이 사용됩니다.
> (단, 일부 기능이 제한될 수 있음)

**3) 도메인 설정 방법** (Route53 + ACM):

| 단계 | 작업 | 설명 |
|------|------|------|
| 1 | Route53 Hosted Zone 생성 | AWS Console → Route53 → Create Hosted Zone |
| 2 | 네임서버 설정 | 도메인 등록 업체에서 NS 레코드를 Route53 값으로 변경 |
| 3 | ACM 인증서 생성 (us-east-1) | CloudFront용 - `*.your-domain.com` |
| 4 | ACM 인증서 생성 (ap-northeast-3) | ALB용 - `*.your-domain.com` |
| 5 | DNS 검증 완료 | ACM에서 제공하는 CNAME 레코드 추가 |

### 3단계: Terraform 인프라 배포

```bash
cd terraform

# 초기화
terraform init

# 계획 확인
terraform plan

# 배포 (약 15-20분 소요)
terraform apply
```

**생성되는 리소스:**
- VPC (10.10.0.0/16) + 서브넷 + NAT Gateway
- EKS 클러스터 (K8s 1.33, AL2023, t3.large x2)
- RDS PostgreSQL 15.10 (db.m5.large)
- ALB + Target Groups
- CloudFront + S3
- ECR 레포지토리

### 4단계: kubectl 설정

```bash
# kubeconfig 업데이트 (Terraform output 활용)
$(terraform output -raw kubeconfig_command)

# 또는 직접 실행:
# aws eks update-kubeconfig --name $(terraform output -raw eks_cluster_name) --region ap-northeast-3

# 연결 확인
kubectl get nodes
```

### 5단계: Docker 이미지 빌드 & Push

```bash
cd ~/workspace/dev-saleor/infrastructure
./scripts/02-build-and-push.sh
```

> **참고**: 
> - 소스코드는 `../source` 디렉토리에서 가져옵니다.
> - Backend 스키마를 Storefront로 자동 복사합니다.
> - GraphQL codegen은 로컬 스키마 파일을 사용합니다.

> ✅ **소스코드 수정사항은 이미 반영되어 있습니다** (트러블슈팅 #31, #32 참조)

### 6단계: AWS Load Balancer Controller 설치

```bash
./scripts/07-setup-alb-controller.sh
```

### 7단계: Kubernetes Secrets 생성

```bash
./scripts/03-create-secrets.sh
```

> **참고**: 스크립트가 Terraform Output(`terraform.tfvars` 설정값)을 자동으로 감지하여 커스텀 도메인 또는 CloudFront 주소를 설정합니다.

### 8단계: 애플리케이션 배포

```bash
./scripts/04-deploy-apps.sh
```

### 9단계: Database 마이그레이션

```bash
./scripts/05-run-migrations.sh
```

> ⚠️ **주의**: 첫 마이그레이션은 3-5분 걸릴 수 있습니다.

```bash
# 마이그레이션 상태 확인
kubectl get jobs -n kyeol-dev

# 마이그레이션 로그 확인
kubectl logs job/db-migration -n kyeol-dev
```

### 10단계: Pod 재시작 (환경변수 적용)

```bash
kubectl rollout restart deployment backend storefront -n kyeol-dev

# 상태 확인
kubectl get pods -n kyeol-dev
```

> ⚠️ **중요**: Pod 재시작 후 S3 설정이 적용되었는지 반드시 확인하세요!
> ```bash
> kubectl exec deployment/backend -n kyeol-dev -- env | grep DEFAULT_FILE_STORAGE
> # 결과: DEFAULT_FILE_STORAGE=saleor.core.storages.S3MediaStorage
> ```
> 이 확인 없이 Dashboard에서 이미지를 업로드하면 `localhost:8000` URL로 저장됩니다!


### 11단계: Dashboard 업로드

```bash
./scripts/06-upload-dashboard.sh
```

> ✅ **자동 처리되는 항목:**
> - pnpm 미설치 시 자동 설치
> - CI=true 설정으로 husky 에러 방지
> - `.env.production` 파일 자동 생성 (API_URL, STATIC_URL 설정)
> - Dashboard 빌드 및 S3 업로드
> - CloudFront 캐시 무효화

> ⚠️ **Node.js 버전 주의**: v20 또는 v22 필요.
> ```bash
> # Node 버전 확인 후 v22로 변경 (nvm 사용 시)
> nvm install 22 && nvm use 22
> ```

> 💡 **수동 빌드 방법** (스크립트 실패 시):
> ```bash
> cd source/saleor-dashboard
> CI=true pnpm install
> pnpm run build
> 
> # S3 업로드
> aws s3 sync build/dashboard s3://$(cd ../../infrastructure/terraform && terraform output -raw s3_static_bucket_name)/dashboard/ --delete
> 
> # CloudFront 캐시 무효화
> aws cloudfront create-invalidation --distribution-id $(cd ../../infrastructure/terraform && terraform output -raw cloudfront_distribution_id) --paths "/dashboard/*"
> ```


### 12단계: S3 미디어 스토리지 확인 (자동 설정됨)

> ✅ **S3 미디어 설정이 자동화되었습니다!**
> 
> `04-deploy-apps.sh` 스크립트가 다음을 자동으로 처리합니다:
> - Backend ServiceAccount에 S3 IAM Role ARN 설정
> - ConfigMap에 S3 버킷명, CloudFront 도메인 설정

이미 8단계에서 `./scripts/04-deploy-apps.sh`를 실행했다면 완료된 상태입니다.

```bash
# 설정 확인
kubectl get configmap backend-config -n kyeol-dev -o yaml | grep -E "(PUBLIC_URL|AWS_MEDIA)"
kubectl exec deployment/backend -n kyeol-dev -- env | grep PUBLIC_URL
```

> ⚠️ **중요**: 이 설정 이전에 업로드한 이미지는 `localhost:8000` URL로 저장됩니다.
> Dashboard에서 상품 이미지를 다시 업로드해야 합니다.

### 13단계: CloudFront 문제 발생 시 (트러블슈팅 29, 30)

S3 Media 버킷에서 404 에러 발생 시 CloudFront Distribution을 재생성합니다:
```bash
cd terraform
terraform taint 'module.cloudfront.aws_cloudfront_distribution.main'
terraform apply
```

**⚠️ CloudFront 재생성 후 필수 작업 (도메인 변경됨!):**

1. **ConfigMap 및 Secret 업데이트:**
```bash
./scripts/04-deploy-apps.sh
kubectl rollout restart deployment backend storefront -n kyeol-dev
```

2. **Dashboard 재빌드 및 S3 업로드:**
```bash
cd ../source/saleor-dashboard
export API_URI="https://$(cd ../infrastructure/terraform && terraform output -raw cloudfront_domain_name)/graphql/"
export STATIC_URL="/dashboard/"
npm run build
aws s3 sync build/dashboard s3://$(terraform output -raw s3_static_bucket_name)/dashboard/ --delete
```

3. **Storefront 이미지 재빌드:**
```bash
cd ../infrastructure
./scripts/02-build-and-push.sh
kubectl rollout restart deployment storefront -n kyeol-dev
```

---

## ✅ 검증

### Pod 상태 확인

```bash
kubectl get pods -n kyeol-dev

# 예상 결과:
# NAME                          READY   STATUS      RESTARTS   AGE
# backend-xxx                   1/1     Running     0          5m
# backend-xxx                   1/1     Running     0          5m
# storefront-xxx                1/1     Running     0          5m
# storefront-xxx                1/1     Running     0          5m
# db-migration-xxx              0/1     Completed   0          5m
# create-superuser-xxx          0/1     Completed   0          5m
```

### 서비스 URL 확인

```bash
cd terraform && terraform output cloudfront_domain_name
```

| 서비스 | URL |
|--------|-----|
| 🛒 Storefront | `https://<cloudfront>/` |
| ⚙️ Dashboard | `https://<cloudfront>/dashboard/` |
| 🔌 GraphQL API | `https://<cloudfront>/graphql/` |

### Admin 계정

- **Email**: `admin@kyeol.com`
- **Password**: `admin123!`

---

## 🔧 자주 발생하는 문제

### 1. Storefront 빌드 실패 (503 에러)

```
Failed to load schema from https://xxx/graphql/: 503 Service Temporarily Unavailable
```

**해결**: 스크립트가 자동으로 로컬 스키마 파일을 사용합니다.

### 2. Pod CrashLoopBackOff

```bash
# 로그 확인
kubectl logs -f deployment/backend -n kyeol-dev
kubectl logs -f deployment/storefront -n kyeol-dev
```

**일반적인 원인**:
- 마이그레이션 미완료 → Job 상태 확인
- 환경변수 누락 → ConfigMap/Secret 확인

### 3. TargetGroupBinding 권한 오류

```
Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**해결**: ALB Controller 재시작
```bash
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

### 4. 마이그레이션 환경변수 오류

```
ALLOWED_CLIENT_HOSTS environment variable must be set
RSA_PRIVATE_KEY is not provided
```

**해결**: ConfigMap 및 Job YAML이 이미 수정되어 있습니다.

### 5. Dashboard 빌드 실패

```
Rollup failed to resolve import "@material-ui/icons/Check"
```

**해결**:
```bash
cd ../source/saleor-dashboard
npm install @material-ui/icons --legacy-peer-deps
npm run build
```

---

## 🗑️ 리소스 정리

```bash
cd dev-saleor/infrastructure/terraform

# 모든 리소스 삭제
terraform destroy

# S3 버킷 강제 삭제가 필요한 경우 (버킷명은 terraform output으로 확인)
aws s3 rb s3://$(terraform output -raw s3_static_bucket_name) --force
```

---

## 📁 디렉토리 구조

```
kyeol-infra-new/
├── terraform/              # Terraform 코드
│   ├── modules/            # 재사용 가능한 모듈
│   │   ├── vpc/
│   │   ├── security-groups/
│   │   ├── eks/
│   │   ├── rds/
│   │   ├── ecr/
│   │   ├── alb/
│   │   └── cloudfront-s3/
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   └── outputs.tf
├── kubernetes/             # K8s 매니페스트
│   ├── 01-namespace.yaml
│   ├── 02-configmap.yaml
│   ├── 03-backend-deployment.yaml
│   ├── 04-storefront-deployment.yaml
│   ├── 05-migration-job.yaml
│   └── 06-target-group-binding.yaml
└── scripts/                # 자동화 스크립트
    ├── 01-setup-state-backend.sh
    ├── 02-build-and-push.sh
    ├── 03-create-secrets.sh
    ├── 04-deploy-apps.sh
    ├── 05-run-migrations.sh
    ├── 06-upload-dashboard.sh
    └── 07-setup-alb-controller.sh
```

---

## 📚 관련 문서

- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - 배포 중 발생한 모든 이슈 및 해결 방법
- [README.md](./README.md) - 프로젝트 개요
