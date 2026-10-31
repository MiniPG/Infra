# ─────────────────────────────────────────────
# ECR: 앱 Docker 이미지 저장소 (비공개)
#   GitHub Actions가 main에 머지될 때마다 이미지를 올리고,
#   env/의 EC2가 켜질 때 여기서 이미지를 받아 실행한다.
#   실험 환경(env/)을 destroy해도 사라지면 안 되므로 global에 둔다.
# ─────────────────────────────────────────────
resource "aws_ecr_repository" "app" {
  for_each = var.app_repos

  name                 = "${var.project}/${each.value}"
  image_tag_mutability = "MUTABLE" # latest 태그를 새 이미지로 덮어쓰기 위함

  image_scanning_configuration {
    scan_on_push = true # 올릴 때 알려진 취약점 검사
  }

  # 실수로 destroy해도 저장소(와 이미지)가 지워지지 않게 막는다
  lifecycle {
    prevent_destroy = true
  }
}

# 오래된 이미지는 자동 정리 (최근 10개만 유지) → 저장 비용이 계속 쌓이지 않게
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
