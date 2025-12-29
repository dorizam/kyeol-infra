# 트러블슈팅 가이드 2 (오사카 리전 마이그레이션 & 배포 이슈)

이 문서는 `ap-northeast-2`(서울)에서 `ap-northeast-3`(오사카)로 리전을 변경하고 배포하는 과정에서 발생한 이슈들과 해결 방법을 정리한 문서입니다.

## 목차

1. [Terraform 초기화 오류 (State Lock)](#1-terraform-초기화-오류-state-lock)
2. [GitHub Actions OIDC 정책 오류](#2-github-actions-oidc-정책-오류)
3. [AWS Load Balancer Controller (TargetGroupBinding) 오류](#3-aws-load-balancer-controller-targetgroupbinding-오류)
4. [빌드 스크립트 경로 오류 (중첩 디렉토리)](#4-빌드-스크립트-경로-오류-중첩-디렉토리)
5. [Kubernetes 이미지 태그 오류 (ImagePullBackOff)](#5-kubernetes-이미지-태그-오류-imagepullbackoff)
6. [S3 업로드 및 ConfigMap 설정 오류 (버킷 이름 불일치)](#6-s3-업로드-및-configmap-설정-오류-버킷-이름-불일치)
7. [Storefront 500 에러 (DYNAMIC_SERVER_USAGE)](#7-storefront-500-에러-dynamic_server_usage)
8. [메인 페이지 상품 미노출 (컬렉션 설정)](#8-메인-페이지-상품-미노출-컬렉션-설정)

---

### 1. Terraform 초기화 오류 (State Lock)

**증상:**
`terraform init` 실행 시 "State data in S3 does not have the expected content" 에러 발생.

**원인:**
기존 리전(`ap-northeast-2`)에서 사용하던 DynamoDB Lock 테이블의 데이터가 남아있어서, 새로운 리전(`ap-northeast-3`)의 빈 S3 버킷 상태와 불일치함.

**해결:**
- DynamoDB 콘솔에서 Lock 테이블(`kyeol-terraform-locks-sol`)의 항목을 삭제하거나, 테이블을 재생성.
- 로컬의 `.terraform` 디렉토리 삭제 후 `terraform init -reconfigure` 실행.

---

### 2. GitHub Actions OIDC 정책 오류

**증상:**
Terraform Apply 시 `MalformedPolicyDocument` 에러 발생. "StringLike" 조건이 잘못되었다는 메시지.

**원인:**
`github-oidc.tf` 파일에서 `StringLike` 조건문이 주석 처리되어 있거나, 리포지토리 이름이 하드코딩되어 있어 실제 IAM 정책 생성 조건(보안상 `sub` 필드 제한 필수)을 충족하지 못함.

**해결:**
`github-oidc.tf`의 `assume_role_policy` 내 `StringLike` 주석을 해제하고, 올바른 리포지토리 경로 포맷으로 수정.
```hcl
"token.actions.githubusercontent.com:sub": [
  "repo:dorizam/kyeol-infra:*",
  "repo:dorizam/saleor-backend:*",
  // ... 기타 리포지토리 추가
]
```

---

### 3. AWS Load Balancer Controller (TargetGroupBinding) 오류

**증상:**
`04-deploy-apps.sh` 실행 시 `TargetGroupNotFound` 에러 발생. "admission webhook denied the request".

**원인:**
1. AWS Load Balancer Controller가 이전 리전(`ap-northeast-2`) 설정으로 실행 중이어서 오사카 리전의 타겟 그룹을 찾지 못함.
2. 설정을 업데이트(`scripts/07-setup-alb-controller.sh`)했음에도 불구하고, 컨트롤러의 Webhook 파드가 캐시된 설정을 유지하고 있어서 에러 지속.

**해결:**
1. `scripts/07-setup-alb-controller.sh`를 실행하여 헬름 차트를 `ap-northeast-3` 리전 설정으로 업데이트.
2. Webhook 설정 강제 초기화 및 파드 재시작:
   ```bash
   kubectl delete validatingwebhookconfiguration aws-load-balancer-controller-webhook
   kubectl delete mutatingwebhookconfiguration aws-load-balancer-controller-webhook
   kubectl rollout restart deployment -n kube-system aws-load-balancer-controller
   ```

---

### 4. 빌드 스크립트 경로 오류 (중첩 디렉토리)

**증상:**
`02-build-and-push.sh` 또는 `06-upload-dashboard.sh` 실행 시 `Dockerfile`이나 `package.json`을 찾을 수 없다는 에러.

**원인:**
실제 프로젝트 구조가 `saleor-backend/saleor`, `saleor-storefront/storefront`와 같이 한 단계 더 깊은 중첩 구조로 되어 있었으나, 스크립트는 상위 폴더를 바라보고 있었음.

**해결:**
스크립트 내 `SOURCE_DIR` 이동 경로 수정.
- Backend: `cd "$SOURCE_DIR/saleor-backend/saleor"`
- Storefront: `cd "$SOURCE_DIR/saleor-storefront/storefront"` (대시보드도 동일한 패턴 적용)

---

### 5. Kubernetes 이미지 태그 오류 (ImagePullBackOff)

**증상:**
배포 후 파드 상태가 `ImagePullBackOff` 또는 `ErrImagePull`이 되고, `kubectl describe` 확인 시 이미지 태그가 알 수 없는 해시값(`ff863...`)으로 되어 있음.

**원인:**
Kubernetes 매니페스트(`03-backend-deployment.yaml` 등)에 예제용 하드코딩된 이미지 태그가 남아있었고, 실제로 빌드해서 올린 `:latest` 태그와 일치하지 않음.

**해결:**
모든 Deployment 및 Job YAML 파일의 `image` 필드를 `:latest`로 수정.
```yaml
image: 827913617839.dkr.ecr.ap-northeast-3.amazonaws.com/sol-dev-backend:latest
```

---

### 6. S3 업로드 및 ConfigMap 설정 오류 (버킷 이름 불일치)

**증상:**
관리자 페이지에서 이미지 업로드 시 `500 Internal Server Error` 발생.

**원인:**
Terraform은 `sol-dev-s3-media`라는 이름으로 버킷을 생성했으나, `02-configmap.yaml`에는 `saleor-sol-dev-s3-media`(`saleor-` 접두어 포함)로 잘못 설정되어 있어서 권한/경로 오류 발생.

**해결:**
`02-configmap.yaml`의 `AWS_MEDIA_BUCKET_NAME`, `AWS_STORAGE_BUCKET_NAME` 값을 실제 생성된 버킷 이름(`sol-dev-s3-media`)으로 수정.

---

### 7. Storefront 500 에러 (DYNAMIC_SERVER_USAGE)

**증상:**
메인 페이지는 잘 뜨지만, 상품 상세 페이지 접속 시 `500 Internal Server Error` 발생. 로그에 `DYNAMIC_SERVER_USAGE` 에러 기록됨.

**원인:**
Next.js가 페이지를 정적(Static)으로 생성하려 시도했으나, 코드 내부에서 쿠키(`cookies()`)나 헤더 같은 동적 데이터를 사용하는 로직(장바구니 세션 등)이 포함되어 있어 빌드/런타임 충돌 발생.

**해결:**
해당 페이지(`src/app/[channel]/(main)/products/[slug]/page.tsx`) 최상단에 동적 렌더링 강제 옵션 추가.
```typescript
export const dynamic = "force-dynamic";
```

---

### 8. 메인 페이지 상품 미노출 (컬렉션 설정)

**증상:**
상품을 등록하고 채널에 공개했음에도 메인 페이지(`default-channel`)에 상품이 보이지 않음.

**원인:**
Storefront 메인 페이지 코드는 `featured-products`라는 **Slug**를 가진 컬렉션의 상품만 필터링해서 보여주도록 설계되어 있음. 단순 상품 등록만으로는 노출되지 않음.

**해결:**
관리자 대시보드에서:
1. **Products > Collections** 메뉴 이동.
2. 컬렉션 생성: 이름은 자유, **Slug는 반드시 `featured-products`**로 설정.
3. 해당 컬렉션에 노출할 상품들을 할당(`Assign products`).
