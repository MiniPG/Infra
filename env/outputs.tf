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
    pg    = { id = aws_instance.pg.id, private_ip = aws_instance.pg.private_ip }
    pg_db = { id = aws_instance.pg_db.id, private_ip = aws_instance.pg_db.private_ip }
    card  = { id = aws_instance.card.id, private_ip = aws_instance.card.private_ip }
  }
}
