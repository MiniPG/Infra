output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "instances" {
  description = "인스턴스 ID와 private IP (SSM 접속, 포트 포워딩에 사용)"
  value = {
    pg         = { id = aws_instance.pg.id, private_ip = aws_instance.pg.private_ip }
    pg_db      = { id = aws_instance.pg_db.id, private_ip = aws_instance.pg_db.private_ip }
    card       = { id = aws_instance.card.id, private_ip = aws_instance.card.private_ip }
    monitoring = { id = aws_instance.monitoring.id, private_ip = aws_instance.monitoring.private_ip }
  }
}

output "grafana_url" {
  description = "Grafana 주소 (내 IP에서만 접속 가능, 계정 admin / 비밀번호는 아래 명령으로 확인)"
  value       = "http://${aws_instance.monitoring.public_ip}:3000"
}

output "grafana_password_command" {
  value = "aws ssm get-parameter --name /${var.project}/grafana-admin-password --with-decryption --query Parameter.Value --output text"
}

output "pg_url" {
  description = "PG API 주소 (내 IP에서만 접근 가능)"
  value       = "https://${local.pg_fqdn}"
}
