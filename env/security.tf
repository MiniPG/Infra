# ─────────────────────────────────────────────
# 보안 그룹: "누가 어느 포트로 들어올 수 있는가"
#   기본은 전부 막힘. 필요한 것만 연다.
#   나가는 트래픽(egress)은 모두 허용 (이미지 받기, 카드사 호출, 로그 전송 등)
# ─────────────────────────────────────────────

# ALB: 내 노트북에서만 HTTPS(443), HTTP(80 → 443 리다이렉트용)
resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "ALB - my IP only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from my IP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "HTTP from my IP (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-alb" }
}

# 모니터링: Grafana(3000)는 내 IP만, Loki(3100)·Prometheus(9090)는 VPC 내부(앱 서버의 Alloy)만
resource "aws_security_group" "monitoring" {
  name        = "${var.project}-monitoring"
  description = "Monitoring - Grafana for my IP, Loki/Prometheus for VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Grafana from my IP"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Loki push from agents in VPC"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Prometheus remote write from agents in VPC"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-monitoring" }
}

# PG 서버: 앱(8080)은 ALB와 모니터링(지표 수집)에서만
resource "aws_security_group" "pg" {
  name        = "${var.project}-pg"
  description = "PG server - from ALB and monitoring"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Actuator scrape from monitoring"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-pg" }
}

# PG DB: MySQL(3306)은 PG 서버에서만, mysqld_exporter(9104)는 모니터링에서만
resource "aws_security_group" "pg_db" {
  name        = "${var.project}-pg-db"
  description = "PG MySQL - from PG server and monitoring"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from PG server"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.pg.id]
  }

  ingress {
    description     = "mysqld_exporter from monitoring"
    from_port       = 9104
    to_port         = 9104
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-pg-db" }
}

# 카드사: 앱(8081)은 PG 서버와 모니터링에서만, mysqld_exporter(9104)는 모니터링에서만
# (카드사 MySQL은 같은 서버 안에서만 쓰므로 3306은 열지 않음)
resource "aws_security_group" "card" {
  name        = "${var.project}-card"
  description = "Card server - from PG server and monitoring"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Card API from PG server"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.pg.id]
  }

  ingress {
    description     = "Actuator scrape from monitoring"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  ingress {
    description     = "mysqld_exporter from monitoring"
    from_port       = 9104
    to_port         = 9104
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-card" }
}
