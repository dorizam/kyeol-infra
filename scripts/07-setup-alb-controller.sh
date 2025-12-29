#!/bin/bash
# 07-setup-alb-controller.sh
# AWS Load Balancer Controller 설치

set -e

echo "=== AWS Load Balancer Controller 설치 ==="

# Terraform output에서 값 가져오기
cd "$(dirname "$0")/../terraform"
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
OIDC_PROVIDER_ARN=$(terraform output -raw eks_oidc_provider_arn)
VPC_ID=$(terraform output -raw vpc_id)
cd - > /dev/null

AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Cluster: $CLUSTER_NAME"
echo "OIDC: $OIDC_PROVIDER_ARN"

# 1. IAM Policy 생성
echo "1. IAM Policy 생성..."
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"

# 정책이 없으면 생성
if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" 2>/dev/null; then
    curl -s -o /tmp/iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json
    aws iam create-policy \
        --policy-name $POLICY_NAME \
        --policy-document file:///tmp/iam_policy.json
fi

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
echo "   - Policy ARN: $POLICY_ARN"

# 2. IAM Role 생성 (IRSA)
echo "2. IAM Role 생성 (IRSA)..."
ROLE_NAME="aws-load-balancer-controller-${CLUSTER_NAME}"

# 중요: OIDC Provider URL 전체를 Condition 키로 사용해야 함
# 잘못된 예: C9E7CC484A81959E22B66423AA6EBC28:sub
# 올바른 예: oidc.eks.ap-northeast-2.amazonaws.com/id/C9E7CC484A81959E22B66423AA6EBC28:sub
OIDC_PROVIDER=$(echo $OIDC_PROVIDER_ARN | sed 's/arn:aws:iam::[0-9]*:oidc-provider\///')

# Trust Policy
cat > /tmp/trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "${OIDC_PROVIDER_ARN}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
                    "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
                }
            }
        }
    ]
}
EOF

# Role 생성 또는 Trust Policy 업데이트
if ! aws iam get-role --role-name $ROLE_NAME 2>/dev/null; then
    echo "   - Role 생성 중..."
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file:///tmp/trust-policy.json
    
    aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn $POLICY_ARN
else
    # 중요: OIDC ID가 변경되었을 수 있으므로 Trust Policy 항상 업데이트
    # 트러블슈팅: terraform destroy -> apply 후 OIDC ID 변경 대응
    echo "   - Role이 이미 존재함. Trust Policy 업데이트 중..."
    aws iam update-assume-role-policy \
        --role-name $ROLE_NAME \
        --policy-document file:///tmp/trust-policy.json
fi

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo "   - Role ARN: $ROLE_ARN"

# 3. Helm 설치
echo "3. Helm Chart 설치..."

# Helm repo 추가
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# AWS Load Balancer Controller 설치
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN \
    --set region=$AWS_REGION \
    --set vpcId=$VPC_ID

# 설치 확인
echo ""
echo "4. 설치 확인..."
kubectl get deployment -n kube-system aws-load-balancer-controller

echo ""
echo "=== 완료! ==="
echo "TargetGroupBinding이 이제 작동합니다."
