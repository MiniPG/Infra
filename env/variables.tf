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
