variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "리소스 이름 앞에 붙는 프로젝트 이름"
  type        = string
  default     = "minipg"
}

variable "my_ip_cidr" {
  description = "내 노트북의 공인 IP (예: 1.2.3.4/32). ALB와 Grafana는 이 IP에서만 접근 가능"
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "사용할 가용 영역 2개 (ALB는 최소 2개 필요)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "app_instance_type" {
  description = "PG, PG DB, 카드사 인스턴스 타입 (t4g.small은 2026-12-31까지 월 750시간 무료 체험)"
  type        = string
  default     = "t4g.small"
}

variable "monitoring_instance_type" {
  description = "모니터링 인스턴스 타입 (Prometheus·Grafana·Loki를 함께 띄우므로 메모리 4GB)"
  type        = string
  default     = "t4g.medium"
}

variable "monitoring_repo" {
  description = "부팅 시 받아오는 Monitoring 레포 (public)"
  type        = string
  default     = "https://github.com/MiniPG/Monitoring.git"
}

variable "domain_name" {
  description = "Route 53에 이미 있는 호스팅 영역(ON:ME 도메인). MiniPG는 레코드만 추가하고 영역은 참조만 한다"
  type        = string
  default     = "on-me-app.com"
}

variable "pg_subdomain" {
  description = "PG API 주소의 서브도메인 (pg → pg.on-me-app.com)"
  type        = string
  default     = "pg"
}

variable "pg_jfr_enabled" {
  description = "true면 PG 서버를 JFR 녹화를 켠 채 띄우고, 녹화 파일을 옮길 S3 버킷을 만든다 (회수: scripts/fetch-pg-jfr.sh). 바꾸면 PG 인스턴스가 다시 만들어짐"
  type        = bool
  default     = false
}
