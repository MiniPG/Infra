#!/bin/bash
# PG DB의 결제 데이터만 비운다. 가맹점(merchant)은 남긴다
#   인프라를 다시 만들지 않고 같은 조건(빈 결제 테이블)에서 부하 테스트를 다시 할 때 쓴다
#   PG 서버를 재시작하지 않으므로 JVM 예열 상태가 유지된다
#
# 사용 (Infra 레포 루트에서):
#   ./scripts/reset-pg-data.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"

INSTANCE_ID=$(aws ec2 describe-instances --region "$REGION" \
  --filters Name=tag:Project,Values=minipg Name=tag:Role,Values=pg-db Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)
[ -z "$INSTANCE_ID" ] && { echo "실행 중인 pg-db 인스턴스가 없습니다"; exit 1; }

SQL="SET FOREIGN_KEY_CHECKS=0; TRUNCATE payment_transaction; TRUNCATE payment; TRUNCATE settlement; TRUNCATE reconciliation_mismatch; SET FOREIGN_KEY_CHECKS=1; SELECT (SELECT COUNT(*) FROM payment) AS payments, (SELECT COUNT(*) FROM merchant) AS merchants;"
SQL_B64=$(printf '%s' "$SQL" | base64 | tr -d '\n')

PARAMS=$(mktemp)
trap 'rm -f "$PARAMS"' EXIT
cat > "$PARAMS" <<JSON
{"commands": [
  "echo $SQL_B64 | base64 -d | docker exec -i mysql sh -c 'exec mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" pg'"
]}
JSON

CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript --parameters "file://$PARAMS" \
  --query Command.CommandId --output text)

aws ssm wait command-executed --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" || true
aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query '[Status, StandardOutputContent, StandardErrorContent]' --output text
