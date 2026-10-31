# ─────────────────────────────────────────────
# EC2 인스턴스
#   - 전부 private 서브넷(같은 AZ) → 외부에서 직접 접근 불가, AZ 간 지연·데이터 전송 비용 없음
#   - 접속은 SSM Session Manager로만 (SSH 키 없음)
#   - 켜질 때 user_data가 Docker를 설치하고 컨테이너를 실행
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
  ecr_registry = split("/", data.terraform_remote_state.global.outputs.ecr_repository_urls["PG-Server"])[0]

  common_instance = {
    ami                  = data.aws_ssm_parameter.al2023_arm64.value
    instance_type        = var.app_instance_type
    subnet_id            = aws_subnet.private[0].id
    iam_instance_profile = aws_iam_instance_profile.ec2.name
  }

  # 모든 user_data 앞에 붙는 공통 준비 스크립트
  bootstrap = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    region   = var.region
    project  = var.project
    registry = local.ecr_registry
  })
}

resource "aws_instance" "pg_db" {
  ami                    = local.common_instance.ami
  instance_type          = local.common_instance.instance_type
  subnet_id              = local.common_instance.subnet_id
  iam_instance_profile   = local.common_instance.iam_instance_profile
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

  user_data = join("\n", [local.bootstrap, templatefile("${path.module}/templates/pg-db.sh.tftpl", {})])

  tags = { Name = "${var.project}-pg-db" }
}

resource "aws_instance" "card" {
  ami                    = local.common_instance.ami
  instance_type          = local.common_instance.instance_type
  subnet_id              = local.common_instance.subnet_id
  iam_instance_profile   = local.common_instance.iam_instance_profile
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

  user_data = join("\n", [local.bootstrap, templatefile("${path.module}/templates/card.sh.tftpl", {
    image = data.terraform_remote_state.global.outputs.ecr_repository_urls["Card-Server"]
  })])

  tags = { Name = "${var.project}-card" }
}

resource "aws_instance" "pg" {
  ami                    = local.common_instance.ami
  instance_type          = local.common_instance.instance_type
  subnet_id              = local.common_instance.subnet_id
  iam_instance_profile   = local.common_instance.iam_instance_profile
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

  user_data = join("\n", [local.bootstrap, templatefile("${path.module}/templates/pg.sh.tftpl", {
    image       = data.terraform_remote_state.global.outputs.ecr_repository_urls["PG-Server"]
    pg_db_host  = aws_instance.pg_db.private_ip
    card_host   = aws_instance.card.private_ip
  })])

  tags = { Name = "${var.project}-pg" }
}
