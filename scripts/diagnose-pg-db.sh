#!/bin/bash
# PG DB(MySQL)가 CPU를 어디에 쓰는지 부하 중에 한 번 잰다. 부하를 유지하는 구간 한가운데에서 실행한다
#   SSM Run Command로 DB 서버에서 SEC초 동안 아래를 모아 출력하고 내 맥에도 저장한다
#   - mpstat: CPU 모드별 비율 (user / sys / soft)
#   - MySQL 상태 변수: 초당 쿼리 종류, 인덱스로 읽은 행, 주고받은 바이트
#   - performance_schema: 쿼리 종류별 누적 시간 (시작할 때 요약 테이블을 비우므로 Grafana 쿼리별 패널이 잠깐 끊긴다)
#   - perf: mysqld가 CPU를 쓴 라이브러리와 함수
#
# 사용 (Infra 레포 루트에서):
#   ./scripts/diagnose-pg-db.sh                  # 30초, ./pg-db-<시각>.txt로 저장
#   SEC=60 ./scripts/diagnose-pg-db.sh ../LoadTest/results
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
SEC="${SEC:-30}"
OUT_DIR="${1:-.}"

INSTANCE_ID=$(aws ec2 describe-instances --region "$REGION" \
  --filters Name=tag:Project,Values=minipg Name=tag:Role,Values=pg-db Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)
[ -z "$INSTANCE_ID" ] && { echo "실행 중인 pg-db 인스턴스가 없습니다"; exit 1; }

REMOTE=$(cat <<'SH'
set -u
SEC=__SEC__
dnf install -y -q sysstat perf >/dev/null 2>&1 || true
sql() { docker exec -i mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$@" 2>/dev/null' -- "$@"; }
VARS="'Questions','Com_select','Com_insert','Com_update','Com_commit','Com_set_option','Com_stmt_prepare','Com_stmt_execute','Handler_read_key','Handler_read_next','Handler_read_rnd_next','Innodb_rows_read','Bytes_received','Bytes_sent'"
echo "SHOW GLOBAL STATUS WHERE Variable_name IN ($VARS)" | sql -N > /tmp/s0
echo "TRUNCATE performance_schema.events_statements_summary_by_digest" | sql
PID=$(pidof mysqld)
perf record -F 99 -p "$PID" -o /tmp/perf.data -- sleep "$SEC" >/dev/null 2>&1 &
mpstat 1 "$SEC" | tail -1 > /tmp/mp
wait
echo "SHOW GLOBAL STATUS WHERE Variable_name IN ($VARS)" | sql -N > /tmp/s1

echo "== CPU 모드별 ($SEC초 평균, 2 vCPU 합쳐 100%)"
awk '{printf "usr %s  sys %s  soft %s  iowait %s  idle %s\n",$3,$5,$8,$6,$NF}' /tmp/mp
echo
echo "== MySQL 상태 (초당)"
join <(sort /tmp/s0) <(sort /tmp/s1) | awk -v s="$SEC" '{printf "%-22s %12.1f\n",$1,($3-$2)/s}'
echo
echo "== 쿼리 종류별 누적 시간 (상위 12)"
sql -t <<SQL
SELECT ROUND(COUNT_STAR/$SEC,1) AS per_s,
       ROUND(100*SUM_TIMER_WAIT/(SELECT SUM(SUM_TIMER_WAIT) FROM performance_schema.events_statements_summary_by_digest),1) AS time_pct,
       ROUND(AVG_TIMER_WAIT/1000000,1) AS avg_us,
       ROUND(SUM_ROWS_EXAMINED/COUNT_STAR,1) AS rows_exam,
       ROUND(SUM_ROWS_SENT/COUNT_STAR,1) AS rows_sent,
       LEFT(DIGEST_TEXT,70) AS query
FROM performance_schema.events_statements_summary_by_digest
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC LIMIT 12;
SQL
echo
echo "== mysqld CPU 표본: 라이브러리별"
DEBUGINFOD_URLS= timeout 90 perf report -i /tmp/perf.data --stdio --no-children --sort dso -q 2>/dev/null | head -12
echo
echo "== mysqld CPU 표본: 함수별 상위 30"
DEBUGINFOD_URLS= timeout 90 perf report -i /tmp/perf.data --stdio --no-children --sort sym -q 2>/dev/null | head -30
SH
)
REMOTE="${REMOTE/__SEC__/$SEC}"
B64=$(printf '%s' "$REMOTE" | base64 | tr -d '\n')

echo "pg-db: $INSTANCE_ID, ${SEC}초 수집"
CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "commands=[\"echo $B64 | base64 -d > /tmp/diag.sh && bash /tmp/diag.sh\"]" \
  --query Command.CommandId --output text)

while true; do
  sleep 5
  STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$STATUS" in Pending|InProgress|Delayed) ;; *) break ;; esac
done

mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/pg-db-$(date +%Y%m%d-%H%M%S).txt"
aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query StandardOutputContent --output text | tee "$OUT"
echo
echo "상태: $STATUS, 저장: $OUT"
