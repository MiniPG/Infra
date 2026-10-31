#!/bin/bash
# PG DB(AWS)에 가맹점 시드 데이터를 넣는다.
#   SSH·DB 포트 없이 SSM Run Command로 pg-db 인스턴스의 MySQL 컨테이너에서 실행
#   root 비밀번호는 컨테이너 안의 환경 변수(MYSQL_ROOT_PASSWORD)를 사용 → 맥·명령·로그에 평문이 남지 않음
#
# 사용 (Infra 레포 루트에서):
#   ./scripts/seed-pg-merchants.sh                       # 기본: m_test 1개 + 부하용 1,000개
#   ./scripts/seed-pg-merchants.sh ../PG-Server/scripts/seed-merchants.sql   # 특정 파일만
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
PG_SCRIPTS="$(cd "$(dirname "$0")/../../PG-Server/scripts" && pwd)"
FILES=("$@")
[ ${#FILES[@]} -eq 0 ] && FILES=("$PG_SCRIPTS/seed-merchants.sql" "$PG_SCRIPTS/seed-load-merchants.sql")

INSTANCE_ID=$(aws ec2 describe-instances --region "$REGION" \
  --filters Name=tag:Project,Values=minipg Name=tag:Role,Values=pg-db Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)
[ -z "$INSTANCE_ID" ] && { echo "실행 중인 pg-db 인스턴스가 없습니다 (terraform apply 했나요?)"; exit 1; }
echo "pg-db: $INSTANCE_ID"

# SQL 파일들을 합쳐 base64로 전달 (따옴표·한글이 명령 문자열을 깨뜨리지 않게)
SQL_B64=$(cat "${FILES[@]}" | base64 | tr -d '\n')

PARAMS=$(mktemp)
trap 'rm -f "$PARAMS"' EXIT
cat > "$PARAMS" <<JSON
{"commands": [
  "echo $SQL_B64 | base64 -d | docker exec -i mysql sh -c 'exec mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" --default-character-set=utf8mb4 pg'",
  "docker exec mysql sh -c 'exec mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" pg -e \"SELECT COUNT(*) AS merchants FROM merchant\"'"
]}
JSON

CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript --parameters "file://$PARAMS" \
  --query Command.CommandId --output text)

aws ssm wait command-executed --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" || true
aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query '[Status, StandardOutputContent, StandardErrorContent]' --output text
