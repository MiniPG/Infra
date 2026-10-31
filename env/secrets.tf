# ─────────────────────────────────────────────
# DB 비밀번호: Terraform이 무작위로 만들어 SSM Parameter Store(SecureString, 암호화)에 저장
#   EC2는 켜질 때 IAM 권한으로 꺼내 쓴다 → 코드·user_data·Git에 평문 비밀번호가 남지 않음
#   ※ 무작위 값 자체는 로컬 tfstate에는 기록된다 (tfstate는 Git 제외, 맥에만 존재)
#   env를 destroy하면 DB와 함께 비밀번호도 사라지고, 다음 apply 때 새로 만들어진다
# ─────────────────────────────────────────────
locals {
  db_secrets = {
    "pg-db/root-password"    = "PG DB root 계정"
    "pg-db/app-password"     = "PG DB 애플리케이션 계정(pg)"
    "card-db/root-password"  = "카드사 DB root 계정"
    "card-db/app-password"   = "카드사 DB 애플리케이션 계정(card)"
    "exporter-password"      = "mysqld_exporter 읽기 전용 계정"
    "grafana-admin-password" = "Grafana admin 계정"
  }
}

resource "random_password" "db" {
  for_each = local.db_secrets
  length   = 24
  special  = false # 셸·SQL·JDBC URL에서 이스케이프 문제가 없도록 영문+숫자만
}

resource "aws_ssm_parameter" "db" {
  for_each    = local.db_secrets
  name        = "/${var.project}/${each.key}"
  description = each.value
  type        = "SecureString"
  value       = random_password.db[each.key].result
}
