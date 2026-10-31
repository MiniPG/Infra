variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project" {
  type    = string
  default = "minipg"
}

variable "github_org" {
  description = "GitHub 조직 이름"
  type        = string
  default     = "MiniPG"
}

variable "app_repos" {
  description = "이미지를 만드는 앱 레포 이름 → ECR 저장소 이름"
  type        = map(string)
  default = {
    "PG-Server"   = "pg-server"
    "Card-Server" = "card-server"
  }
}
