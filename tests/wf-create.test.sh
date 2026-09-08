#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf_script="${WF_SCRIPT_UNDER_TEST:-$repo_dir/scripts/wf.sh}"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/bin"
cat > "$test_dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
write_status=false
request_url=""
for arg in "$@"; do
  [ "$arg" != '-w' ] || write_status=true
  case "$arg" in https://mock.wireflow.test/*) request_url="$arg";; esac
done
if [ "$request_url" = 'https://mock.wireflow.test/workflows/lint' ]; then
  body='{"ok":true}'
  status=200
else
  printf 'create\n' >> "$MOCK_REQUESTS"
  body="$MOCK_BODY"
  status="$MOCK_STATUS"
fi
printf '%s' "$body"
if "$write_status"; then printf '\n%s' "$status"; fi
MOCK
chmod +x "$test_dir/bin/curl"
printf '%s\n' '{"name":"test","nodes":[],"edges":[]}' > "$test_dir/graph.json"
export PATH="$test_dir/bin:$PATH"
export WIREFLOW_API_KEY=wf_test_offline_key
export WIREFLOW_BASE_URL=https://mock.wireflow.test
export WF_SKIP_LAYOUT=1 WF_MAX_RETRIES=0
export MOCK_REQUESTS="$test_dir/requests"
failures=0

for status in 201 400 401 409 422 429 500; do
  export MOCK_STATUS="$status"
  if [ "$status" = 201 ]; then
    export MOCK_BODY='{"data":{"id":"saved-workflow"}}'
  else
    export MOCK_BODY='{"error":{"message":"create rejected"}}'
  fi
  : > "$MOCK_REQUESTS"
  result=0
  (cd "$test_dir" && bash "$wf_script" create graph.json) > "$test_dir/out" 2> "$test_dir/err" || result=$?
  if [ "$status" = 201 ]; then
    if [ "$result" -ne 0 ]; then echo "FAIL: HTTP 201 exited $result"; failures=$((failures + 1)); fi
  elif [ "$result" -eq 0 ]; then
    echo "FAIL: HTTP $status reported success"; failures=$((failures + 1))
  elif ! grep -q "HTTP $status" "$test_dir/err"; then
    echo "FAIL: HTTP $status missing from stderr"; failures=$((failures + 1))
  fi
  if [ "$(cat "$test_dir/out")" != "$MOCK_BODY" ]; then
    echo "FAIL: HTTP $status lost or modified the response body"; failures=$((failures + 1))
  fi
  if [ "$(wc -l < "$MOCK_REQUESTS" | tr -d ' ')" != 1 ]; then
    echo "FAIL: HTTP $status issued duplicate create requests"; failures=$((failures + 1))
  fi
done
if [ "$failures" -eq 0 ]; then echo 'PASS: create status, response body and request count (7 HTTP cases)'; fi
exit "$failures"
