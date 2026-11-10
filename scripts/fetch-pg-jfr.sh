#!/bin/bash
# PG 서버(여러 대면 모두)의 JFR 녹화를 내 맥으로 가져온다. env/terraform.tfvars에 pg_jfr_enabled = true로 띄운 경우에만 동작
#   SSM Run Command로 PG 컨테이너를 멈춰 녹화를 파일로 남기고(dumponexit), S3에 올린 뒤 컨테이너를 다시 켠다
#
# 사용 (Infra 레포 루트에서, 부하 테스트가 끝난 뒤):
#   ./scripts/fetch-pg-jfr.sh                 # ./pg-<시각>.jfr로 저장
#   ./scripts/fetch-pg-jfr.sh ../LoadTest/results
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
ENV_DIR="$(cd "$(dirname "$0")/../env" && pwd)"
OUT_DIR="${1:-.}"
BUCKET=$(terraform -chdir="$ENV_DIR" output -raw jfr_bucket)
[ -z "$BUCKET" ] && { echo "JFR이 꺼져 있습니다. env/terraform.tfvars에 pg_jfr_enabled = true를 넣고 terraform apply 하세요"; exit 1; }

INSTANCES=$(aws ec2 describe-instances --region "$REGION" \
  --filters Name=tag:Project,Values=minipg Name=tag:Role,Values=pg Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`]|[0].Value]' --output text | sort -k2)
[ -z "$INSTANCES" ] && { echo "실행 중인 pg 인스턴스가 없습니다"; exit 1; }

STAMP=$(date +%Y%m%d-%H%M%S)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

while read -r ID NAME; do
  KEY="pg-${STAMP}-${NAME#minipg-}.jfr"
  cat > "$TMP/$ID.json" <<JSON
{"commands": [
  "set -e",
  "docker stop -t 60 pg-server",
  "ls -lh /var/log/minipg-jfr/pg.jfr",
  "aws s3 cp --only-show-errors --region $REGION /var/log/minipg-jfr/pg.jfr s3://$BUCKET/$KEY",
  "docker start pg-server"
]}
JSON
  CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$ID" \
    --document-name AWS-RunShellScript --parameters "file://$TMP/$ID.json" \
    --query Command.CommandId --output text)
  echo "$ID $NAME $CMD_ID $KEY" >> "$TMP/commands"
  echo "$NAME ($ID) → s3://$BUCKET/$KEY"
done <<< "$INSTANCES"

mkdir -p "$OUT_DIR"
while read -r ID NAME CMD_ID KEY; do
  aws ssm wait command-executed --region "$REGION" --command-id "$CMD_ID" --instance-id "$ID" || true
  echo "== $NAME"
  aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$ID" \
    --query '[Status, StandardOutputContent, StandardErrorContent]' --output text
  aws s3 cp --only-show-errors --region "$REGION" "s3://$BUCKET/$KEY" "$OUT_DIR/$KEY"
  echo "저장: $OUT_DIR/$KEY"
done < "$TMP/commands"
