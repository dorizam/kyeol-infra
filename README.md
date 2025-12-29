# KYEOL E-commerce (Saleor 기반)

AWS EKS 기반 Saleor E-commerce 플랫폼 배포 프로젝트입니다.

## 🚀 빠른 시작

```bash
# 레포지토리 Clone
git clone https://github.com/selffish234/dev-saleor.git
cd dev-saleor

# 상세 배포 가이드 따라하기
cat QUICK_START.md
```

## 📁 구조

```
dev-saleor/
├── infrastructure/     # Terraform + K8s + Scripts
├── source/             # Saleor Backend, Dashboard, Storefront
├── QUICK_START.md      # 상세 배포 가이드
└── TROUBLESHOOTING.md  # 트러블슈팅 문서
```

## 📋 사전 요구사항

- AWS CLI, Terraform, kubectl, Docker, Helm, Node.js v20+
- AWS 계정 및 자격 증명
- (선택) 커스텀 도메인 및 Route53 Hosted Zone

## 🔗 배포 후 URL

| 서비스 | URL |
|--------|-----|
| Storefront | `https://<your-domain>/` |
| Dashboard | `https://<your-domain>/dashboard/` |
| GraphQL API | `https://<your-domain>/graphql/` |

## 📚 문서

- [QUICK_START.md](./QUICK_START.md) - 단계별 배포 가이드
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - 문제 해결 가이드
- [DASHBOARD_GUIDE.md](./DASHBOARD_GUIDE.md) - dashboard 간단 가이드
