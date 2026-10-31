# ─────────────────────────────────────────────
# EC2 인스턴스 역할 (모든 인스턴스 공통)
#   - SSM Session Manager 접속 (SSH 키·22번 포트 없이 접속)
#   - ECR에서 이미지 받기 (읽기 전용)
#   - SSM Parameter Store에서 /minipg/* 비밀번호 읽기
# ─────────────────────────────────────────────
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project}-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "read_secrets" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"]
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  name   = "read-db-secrets"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2"
  role = aws_iam_role.ec2.name
}

# ─────────────────────────────────────────────
# 모니터링 인스턴스 역할
#   앱 역할과 같은 권한 + Prometheus EC2 서비스 디스커버리용 조회 권한(ec2:Describe*)
#   앱 서버에는 EC2 조회 권한을 주지 않기 위해 역할을 분리
# ─────────────────────────────────────────────
resource "aws_iam_role" "monitoring" {
  name               = "${var.project}-monitoring"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring_ssm_core" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "monitoring_read_secrets" {
  name   = "read-secrets"
  role   = aws_iam_role.monitoring.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

data "aws_iam_policy_document" "ec2_discovery" {
  statement {
    actions   = ["ec2:DescribeInstances", "ec2:DescribeAvailabilityZones"]
    resources = ["*"] # Describe 계열은 리소스 단위 제한을 지원하지 않음
  }
}

resource "aws_iam_role_policy" "monitoring_ec2_discovery" {
  name   = "ec2-discovery"
  role   = aws_iam_role.monitoring.id
  policy = data.aws_iam_policy_document.ec2_discovery.json
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project}-monitoring"
  role = aws_iam_role.monitoring.name
}
