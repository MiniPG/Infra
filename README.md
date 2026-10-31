# Infra

MiniPG(PG-Server, Card-Server, Monitoring)의 AWS 인프라를 Terraform으로 관리한다.

## 구조
| 폴더 | 수명 | 내용 |
|---|---|---|
| `global/` | **항상 유지** (거의 0원) | ECR 저장소, GitHub Actions용 OIDC 역할 |
| `env/` | **실험할 때만** apply / destroy | VPC, 서브넷, NAT, 보안 그룹, EC2, ALB |

폴더마다 state가 따로라서 `env/`에서 destroy해도 `global/`은 영향을 받지 않는다.
ECR은 `prevent_destroy`로 실수로 지워지지 않게 막아 두었다.

## 처음 한 번 (global)
```
cd global
terraform init
terraform apply
```

## 실험할 때마다 (env)
```
cd env
cp example.tfvars terraform.tfvars   # 처음 한 번, 내 IP 입력 (x.x.x.x/32)
terraform init                       # 처음 한 번
terraform plan
terraform apply                      # 시작
terraform destroy                    # 끝나면 반드시 (NAT Gateway·ALB는 켜둔 시간만큼 과금)
```

## 주의
- `*.tfstate`, `terraform.tfvars`, 키 파일은 Git에 올리지 않는다 (.gitignore)
- 집 IP가 바뀌면 `terraform.tfvars`의 `my_ip_cidr`를 고치고 `terraform apply`
