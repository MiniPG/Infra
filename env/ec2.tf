# ─────────────────────────────────────────────
# EC2 인스턴스
#   - 앱·DB: private 서브넷(같은 AZ) → 외부에서 직접 접근 불가, AZ 간 지연·데이터 전송 비용 없음
#   - 모니터링: public 서브넷(같은 AZ) → Grafana(3000)만 내 IP에서 접근
#   - 접속은 SSM Session Manager로만 (SSH 키 없음)
#   - 켜질 때 user_data가 Docker를 설치하고 컨테이너를 실행
#   - user_data가 바뀌면 인스턴스를 새로 만든다 (user_data는 최초 부팅에만 실행되므로)
#   - 태그 Role/Db: Prometheus가 수집 대상을 찾는 기준 (Monitoring 레포 aws/prometheus.yml)
# ─────────────────────────────────────────────

# Amazon Linux 2023 arm64 최신 AMI (AWS가 관리하는 SSM 공개 파라미터에서 조회)
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "terraform_remote_state" "global" {
  backend = "local"
  config = {
    path = "${path.module}/../global/terraform.tfstate"
  }
}

locals {
  ami          = data.aws_ssm_parameter.al2023_arm64.value
  ecr_repos    = data.terraform_remote_state.global.outputs.ecr_repository_urls
  ecr_registry = split("/", local.ecr_repos["PG-Server"])[0]

  # 모든 user_data 앞에 붙는 공통 준비 스크립트
  bootstrap = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    region   = var.region
    project  = var.project
    registry = local.ecr_registry
  })

  # 앱·DB 서버 뒤에 붙는 관측 에이전트(Alloy) 스크립트
  agent = {
    for host in ["pg", "pg-db", "card"] : host => templatefile("${path.module}/templates/agent.sh.tftpl", {
      repo            = var.monitoring_repo
      monitoring_host = aws_instance.monitoring.private_ip
      host_name       = host
    })
  }

  # private 서브넷의 인스턴스는 NAT을 거쳐야 인터넷(dnf, Docker Hub, ECR)에 나갈 수 있다
  # → NAT과 라우팅이 준비된 뒤에 만들도록 의존성을 명시
}

resource "aws_instance" "monitoring" {
  ami                    = local.ami
  instance_type          = var.monitoring_instance_type
  subnet_id              = aws_subnet.public[0].id
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name
  vpc_security_group_ids = [aws_security_group.monitoring.id]

  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_tokens = "required"
    # Prometheus 컨테이너(Docker 브리지 네트워크)가 IMDS로 역할 자격 증명을 받으려면 홉이 1 더 필요
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }

  user_data = join("\n", [local.bootstrap, templatefile("${path.module}/templates/monitoring.sh.tftpl", {
    repo = var.monitoring_repo
  })])
  user_data_replace_on_change = true

  depends_on = [aws_route_table_association.public]

  tags = { Name = "${var.project}-monitoring", Role = "monitoring" }
}

resource "aws_instance" "pg_db" {
  ami                    = local.ami
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private[0].id
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  vpc_security_group_ids = [aws_security_group.pg_db.id]

  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 강제
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  user_data = join("\n", [
    local.bootstrap,
    templatefile("${path.module}/templates/pg-db.sh.tftpl", {}),
    local.agent["pg-db"],
  ])
  user_data_replace_on_change = true

  depends_on = [aws_nat_gateway.main, aws_route_table_association.private]

  tags = { Name = "${var.project}-pg-db", Role = "pg-db", Db = "pg" }
}

resource "aws_instance" "card" {
  ami                    = local.ami
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private[0].id
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  vpc_security_group_ids = [aws_security_group.card.id]

  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  user_data = join("\n", [
    local.bootstrap,
    templatefile("${path.module}/templates/card.sh.tftpl", { image = local.ecr_repos["Card-Server"] }),
    local.agent["card"],
  ])
  user_data_replace_on_change = true

  depends_on = [aws_nat_gateway.main, aws_route_table_association.private]

  tags = { Name = "${var.project}-card", Role = "card", Db = "card" }
}

resource "aws_instance" "pg" {
  ami                    = local.ami
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private[0].id
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  vpc_security_group_ids = [aws_security_group.pg.id]

  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  user_data = join("\n", [
    local.bootstrap,
    templatefile("${path.module}/templates/pg.sh.tftpl", {
      image       = local.ecr_repos["PG-Server"]
      pg_db_host  = aws_instance.pg_db.private_ip
      card_host   = aws_instance.card.private_ip
      jfr_enabled = var.pg_jfr_enabled
    }),
    local.agent["pg"],
  ])
  user_data_replace_on_change = true

  depends_on = [aws_nat_gateway.main, aws_route_table_association.private]

  tags = { Name = "${var.project}-pg", Role = "pg" }
}
