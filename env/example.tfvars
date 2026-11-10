# 이 파일을 terraform.tfvars로 복사해서 실제 값을 채운다. (terraform.tfvars는 Git에 올라가지 않음)
#   cp example.tfvars terraform.tfvars
#   내 IP 확인: curl -s https://checkip.amazonaws.com

my_ip_cidr = "1.2.3.4/32"

# PG 서버를 JFR 녹화를 켠 채 띄울 때만 true (회수: ../scripts/fetch-pg-jfr.sh)
# pg_jfr_enabled = true
# pg_count = 2
