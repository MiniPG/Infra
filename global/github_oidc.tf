# ─────────────────────────────────────────────
# GitHub Actions → AWS 인증 (OIDC)
#   GitHub에 AWS 액세스 키를 저장하지 않는다.
#   Actions가 실행될 때마다 GitHub이 발급한 토큰으로 임시 권한(최대 1시간)을 받는다.
#   GitHub OIDC 공급자는 계정당 URL별로 1개만 만들 수 있다.
#   ON:ME에서 이미 만들어 둔 공급자가 있으므로 새로 만들지 않고 기존 것을 참조한다.
# ─────────────────────────────────────────────
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# 이 역할은 "MiniPG 조직의 PG-Server, Card-Server 레포의 main 브랜치"에서 실행된 Actions만 맡을 수 있다
data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for repo in keys(var.app_repos) : "repo:${var.github_org}/${repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_ecr_push" {
  name               = "${var.project}-github-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

# 권한은 "우리 ECR 저장소 2개에 이미지 올리기"만
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for repo in aws_ecr_repository.app : repo.arn]
  }
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
