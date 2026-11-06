#!/bin/bash
# Grafana 주소와 접속 상태를 확인하고, 비밀번호를 클립보드에 복사한 뒤 브라우저로 연다
#   ./scripts/grafana.sh           # 확인 + 비밀번호 복사 + 브라우저 열기
#   ./scripts/grafana.sh --no-open # 브라우저는 열지 않음
set -uo pipefail

ENV_DIR="$(cd "$(dirname "$0")/../env" && pwd)"

URL=$(terraform -chdir="$ENV_DIR" output -raw grafana_url 2>/dev/null)
[ -z "$URL" ] && { echo "Grafana 주소가 없습니다. env에서 terraform apply 했나요?"; exit 1; }
echo "주소     : $URL"
echo "아이디   : admin"

MY_IP=$(curl -s -m 5 https://checkip.amazonaws.com | tr -d '[:space:]')
ALLOWED=$(grep -E '^\s*my_ip_cidr' "$ENV_DIR/terraform.tfvars" | sed -E 's/.*"(.*)".*/\1/')
if [ "$MY_IP/32" = "$ALLOWED" ]; then
  echo "내 IP    : $MY_IP (허용됨)"
else
  echo "내 IP    : $MY_IP ← 허용된 IP($ALLOWED)와 다름"
  echo "           env/terraform.tfvars의 my_ip_cidr를 \"$MY_IP/32\"로 고치고 terraform apply 하세요"
  exit 1
fi

CODE=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$URL/login")
if [ "$CODE" = "200" ]; then
  echo "상태     : 접속 가능"
else
  echo "상태     : 응답 없음 (HTTP $CODE). apply 직후면 3~5분 뒤 다시 실행하세요"
  exit 1
fi

PASSWORD=$(eval "$(terraform -chdir="$ENV_DIR" output -raw grafana_password_command)" 2>/dev/null)
if [ -n "$PASSWORD" ] && command -v pbcopy >/dev/null; then
  printf '%s' "$PASSWORD" | pbcopy
  echo "비밀번호 : 클립보드에 복사함 (붙여넣기만 하면 됨)"
else
  echo "비밀번호 : 복사 실패. 직접 확인: eval \"\$(terraform -chdir=env output -raw grafana_password_command)\""
fi

[ "${1:-}" != "--no-open" ] && command -v open >/dev/null && open "$URL"
