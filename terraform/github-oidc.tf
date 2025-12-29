# GitHub Actions OIDC Provider for CI/CD
# GitHub Actions에서 AWS 리소스에 접근하기 위한 Keyless 인증 설정

# 기존 OIDC Provider 참조 (이미 AWS에 존재)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# GitHub Actions용 IAM Role
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-${var.environment}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # 레포지토리 목록 (Monorepo 및 각 모듈별 리포지토리 허용)
          "token.actions.githubusercontent.com:sub" = [
            "repo:dorizam/kyeol-infra:*",
            "repo:dorizam/saleor-backend:*",
            "repo:dorizam/saleor-dashboard:*",
            "repo:dorizam/saleor-storefront:*"
          ]
        }
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-github-actions-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ECR Push/Pull 권한
resource "aws_iam_role_policy_attachment" "github_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# (선택) EKS 접근 권한이 필요한 경우
# resource "aws_iam_role_policy_attachment" "github_eks" {
#   role       = aws_iam_role.github_actions.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
# }

# Output: GitHub Repository Secrets에 설정할 값
output "github_actions_role_arn" {
  description = "GitHub Actions에서 사용할 IAM Role ARN"
  value       = aws_iam_role.github_actions.arn
}
