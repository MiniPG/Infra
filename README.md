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

## Grafana 접속
```
./scripts/grafana.sh
```
주소, 내 IP가 허용됐는지, 접속 가능한지 확인하고 비밀번호를 클립보드에 복사한 뒤 브라우저로 연다.

## PG 서버 여러 대
```
# env/terraform.tfvars
pg_count = 2
```
PG 서버가 모두 같은 AZ(private[0])에 뜨고 ALB 대상 그룹에 붙는다. 이름 태그는 `minipg-pg-1`, `minipg-pg-2`이고, 호스트 지표의 `host` 라벨은 `pg-1`, `pg-2`다. `fetch-pg-jfr.sh`, `swap-pg-image.sh`는 모든 PG 인스턴스에 대해 실행한다.

## JFR 녹화 (필요할 때만)
기본은 꺼져 있다. 켜면 PG 서버가 뜨는 순간부터 녹화하고, 회수할 때 컨테이너를 멈춰 파일로 남긴다.
```
# env/terraform.tfvars
pg_jfr_enabled = true

cd env && terraform apply             # PG 인스턴스가 다시 만들어지고 녹화용 S3 버킷이 생김

# 부하 테스트가 끝난 뒤, Infra 루트에서
./scripts/fetch-pg-jfr.sh ../LoadTest/results
jfr view hot-methods ../LoadTest/results/pg-<시각>.jfr
```
- 회수하는 동안 PG 서버가 잠깐 멈췄다가 다시 켜진다. 측정이 모두 끝난 뒤에 실행한다
- 녹화는 서버가 떠 있던 전체 구간이다. 특정 단계만 보려면 JMC에서 시간 구간을 고른다
- 끄려면 `pg_jfr_enabled`를 지우고 `terraform apply` (PG 인스턴스가 다시 만들어지고 버킷은 지워짐)

### PG DB 진단

부하를 유지하는 구간 한가운데에서 실행하면, PG DB 서버에서 30초 동안 CPU 모드별 비율(`mpstat`), 초당 쿼리 종류(MySQL 상태 변수), 쿼리 종류별 누적 시간(`performance_schema`), mysqld가 CPU를 쓴 함수(`perf`)를 모아 출력하고 파일로 남긴다. 설정 변경이나 재시작은 없다.
```
# Infra 루트에서
./scripts/diagnose-pg-db.sh ../LoadTest/results          # 30초
SEC=60 ./scripts/diagnose-pg-db.sh ../LoadTest/results   # 60초
```
- 처음 실행할 때 DB 서버에 `sysstat`, `perf`를 설치한다(수십 초)
- 시작할 때 `performance_schema` 쿼리 요약 테이블을 비우므로, Grafana 쿼리별 패널이 잠깐 끊긴다
- `perf`가 mysqld 표본을 찍는 비용이 있어 그 30초의 지표는 비교에 쓰지 않는다

## 주의
- `*.tfstate`, `terraform.tfvars`, 키 파일은 Git에 올리지 않는다 (.gitignore)
- 집 IP가 바뀌면 `terraform.tfvars`의 `my_ip_cidr`를 고치고 `terraform apply`
