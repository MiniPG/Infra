output "ecr_repository_urls" {
  description = "앱별 ECR 주소 (GitHub Actions와 EC2에서 사용)"
  value       = { for k, repo in aws_ecr_repository.app : k => repo.repository_url }
}

output "github_actions_role_arn" {
  description = "GitHub Actions에서 assume할 역할 ARN (각 앱 레포의 워크플로에 설정)"
  value       = aws_iam_role.github_ecr_push.arn
}
