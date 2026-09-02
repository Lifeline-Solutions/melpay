#!/usr/bin/env bash
# Notify IndexNow (Bing, DuckDuckGo, Yandex, Seznam, Naver) that URLs changed.
# Google does not participate in IndexNow; use Google Search Console for Google.
#
# Prereq: public/<KEY>.txt must be deployed and reachable at
#   https://malpayment.com/<KEY>.txt
#
# Usage:
#   script/indexnow.sh                       # submits the default URL list below
#   script/indexnow.sh https://malpayment.com/pricing   # submits given URL(s)

set -euo pipefail

HOST="malpayment.com"
KEY="e0cb22f7368b460e9c608ddd22d7191d808442b0b2b546fb81772c87ae4a4e35"

if [ "$#" -gt 0 ]; then
  URLS=("$@")
else
  URLS=(
    "https://malpayment.com/"
    "https://malpayment.com/users/sign_in"
    "https://malpayment.com/users/sign_up"
  )
fi

# Build JSON array of URLs
url_json=$(printf '"%s",' "${URLS[@]}")
url_json="[${url_json%,}]"

payload=$(cat <<JSON
{
  "host": "${HOST}",
  "key": "${KEY}",
  "keyLocation": "https://${HOST}/${KEY}.txt",
  "urlList": ${url_json}
}
JSON
)

echo "Submitting to IndexNow:"
printf '  %s\n' "${URLS[@]}"

http_code=$(curl -sS -o /tmp/indexnow_resp.txt -w '%{http_code}' \
  -X POST "https://api.indexnow.org/indexnow" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data "${payload}")

echo "HTTP ${http_code}"
cat /tmp/indexnow_resp.txt 2>/dev/null || true
echo

case "${http_code}" in
  200|202) echo "OK — accepted." ;;
  403) echo "403 — key file not found/valid at https://${HOST}/${KEY}.txt (deploy it first)." ;;
  422) echo "422 — URLs don't match host, or bad key." ;;
  *)   echo "Unexpected response." ;;
esac
