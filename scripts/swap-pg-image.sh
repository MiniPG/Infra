#!/bin/bash
# 같은 PG 인스턴스에서 컨테이너 이미지만 바꿔 다시 띄운다. 코드 A/B 비교용 (인스턴스를 새로 만들면 물리 서버가 달라짐)
#   SSM Run Command로 실행. 환경 변수와 볼륨은 지금 컨테이너 것을 그대로 쓰고, 이미지 태그만 커밋 SHA로 바꾼다
#   JFR이 켜져 있으면, 멈추면서 남은 직전 실행의 녹화를 S3에 올린 뒤 OUT_DIR로 내려받는다
#
# 사용 (Infra 레포 루트에서):
#   ./scripts/swap-pg-image.sh <커밋 SHA 전체> [OUT_DIR] [직전 실행 이름]
#   ./scripts/swap-pg-image.sh ec7f62c4de66734cf0bd39add2f0b6ceaf3cc811 ../LoadTest/results
#   ./scripts/swap-pg-image.sh 19f2ef9037d0258277976004aac1233b770d9ecd ../LoadTest/results A1
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
ENV_DIR="$(cd "$(dirname "$0")/../env" && pwd)"
SHA="${1:?커밋 SHA 전체를 넣으세요}"
OUT_DIR="${2:-.}"
PREV_LABEL="${3:-prev}"
BUCKET=$(terraform -chdir="$ENV_DIR" output -raw jfr_bucket 2>/dev/null || true)

INSTANCE_ID=$(aws ec2 describe-instances --region "$REGION" \
  --filters Name=tag:Project,Values=minipg Name=tag:Role,Values=pg Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)
[ -z "$INSTANCE_ID" ] && { echo "실행 중인 pg 인스턴스가 없습니다"; exit 1; }

KEY="pg-$(date +%Y%m%d-%H%M%S)-${PREV_LABEL}.jfr"

REMOTE=$(cat <<'EOS'
set -euo pipefail
SHA="$1"; REGION="$2"; BUCKET="$3"; KEY="$4"
REPO=$(docker inspect -f '{{.Config.Image}}' pg-server | sed -E 's/:[^:/]+$//')
REGISTRY="${REPO%%/*}"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
docker pull -q "$REPO:$SHA"

docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' pg-server \
  | grep -E '^(SPRING_|CARD_|LOG_DIR=|TZ=|JAVA_TOOL_OPTIONS=)' > /root/pg-server.env
chmod 600 /root/pg-server.env
VOLUMES=$(docker inspect -f '{{range .HostConfig.Binds}}-v {{.}} {{end}}' pg-server)
echo "이전 이미지: $(docker inspect -f '{{.Config.Image}}' pg-server)"

docker stop -t 60 pg-server >/dev/null
if [ -n "$BUCKET" ] && [ -f /var/log/minipg-jfr/pg.jfr ]; then
  aws s3 cp --only-show-errors --region "$REGION" /var/log/minipg-jfr/pg.jfr "s3://$BUCKET/$KEY"
  echo "직전 실행 JFR: s3://$BUCKET/$KEY"
  rm -f /var/log/minipg-jfr/pg.jfr
fi
docker rm pg-server >/dev/null

docker run -d --name pg-server --network host --restart unless-stopped \
  --env-file /root/pg-server.env $VOLUMES "$REPO:$SHA" >/dev/null
echo "새 이미지: $REPO:$SHA"

for i in $(seq 1 60); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' localhost:8080/actuator/health/readiness)" = "200" ]; then
    echo "준비 완료: $(date '+%H:%M:%S') (약 $((i * 3))초)"
    exit 0
  fi
  sleep 3
done
echo "180초 안에 준비되지 않았습니다. docker logs pg-server로 확인하세요"
exit 1
EOS
)
REMOTE_B64=$(printf '%s' "$REMOTE" | base64 | tr -d '\n')

PARAMS=$(mktemp)
trap 'rm -f "$PARAMS"' EXIT
cat > "$PARAMS" <<JSON
{"commands": ["echo $REMOTE_B64 | base64 -d > /root/swap-pg.sh && bash /root/swap-pg.sh $SHA $REGION '$BUCKET' $KEY"],
 "executionTimeout": ["600"]}
JSON

echo "pg: $INSTANCE_ID → $SHA"
CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript --parameters "file://$PARAMS" \
  --query Command.CommandId --output text)

for i in $(seq 1 120); do
  STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$STATUS" in Pending|InProgress|Delayed) sleep 5 ;; *) break ;; esac
done
aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query '[Status, StandardOutputContent, StandardErrorContent]' --output text

if [ -n "$BUCKET" ] && aws s3 ls --region "$REGION" "s3://$BUCKET/$KEY" >/dev/null 2>&1; then
  mkdir -p "$OUT_DIR"
  aws s3 cp --only-show-errors --region "$REGION" "s3://$BUCKET/$KEY" "$OUT_DIR/$KEY"
  echo "저장: $OUT_DIR/$KEY"
fi
