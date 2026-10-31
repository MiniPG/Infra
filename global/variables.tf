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

variable "github_org_id" {
  description = "GitHub 조직의 숫자 ID (이름이 바뀌어도 변하지 않음, OIDC sub 클레임에 포함됨)"
  type        = string
  default     = "349692158"
}

variable "app_repos" {
  description = "이미지를 만드는 앱 레포 이름 → ECR 저장소 이름"
  type        = map(string)
  default = {
    "PG-Server"   = "pg-server"
    "Card-Server" = "card-server"
  }
}
