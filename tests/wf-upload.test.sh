#!/usr/bin/env bash
# wf.sh upload: inline door up to 4MB, presigned flow above it. A fake curl on
# PATH records every call and returns canned responses. No network.
# Run: bash tests/wf-upload.test.sh
set -uo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="${WF_SCRIPT_UNDER_TEST:-$repo_dir/scripts/wf.sh}"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
cat > "$t/bin/curl" <<'MOCK'
#!/usr/bin/env bash
if [ -n "${MOCK_CURL_FAIL:-}" ] && printf '%s' "$*" | grep -q "$MOCK_CURL_FAIL"; then echo "curl: (6) Could not resolve host" >&2; exit 6; fi
url=""; method=""; write=false; hdrs=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  a="${args[$i]}"
  case "$a" in
    -X) method="${args[$((i+1))]}" ;;
    -w) write=true ;;
    -d) hdrs="$hdrs|body=${args[$((i+1))]}" ;;
    -H) hdrs="$hdrs|${args[$((i+1))]}" ;;
    http://*|https://*) url="$a" ;;
  esac
done
printf '%s %s %s\n' "$method" "$url" "$hdrs" >> "$MOCK_LOG"
case "$url" in
  */media/upload-url/complete) [ -n "${MOCK_COMPLETE_FAIL:-}" ] && { printf '{"error":{"message":"boom"}}'; exit 0; }; printf '{"data":{"url":"https://cdn.test/big.mp4"}}' ;;
  */media/upload-url)
    if [ -n "${MOCK_MINT_FAIL:-}" ]; then printf '{"error":{"message":"nope"}}'; exit 0; fi
    printf '{"data":{"uploadUrl":"https://storage.test/put?sig=1","method":"PUT","mediaId":"abc.mp4","headers":{"Content-Type":"video/mp4","Content-Length":"%s"}}}' "$MOCK_BYTES" ;;
  https://storage.test/*) printf 'ok'; "$write" && printf '\n%s' "${MOCK_PUT_CODE:-200}" ;;
  */media/upload) printf '{"data":{"url":"https://cdn.test/small.png"}}' ;;
  *) printf '{}' ;;
esac
MOCK
chmod +x "$t/bin/curl"
export PATH="$t/bin:$PATH" WIREFLOW_API_KEY=wf_test_offline_key WIREFLOW_BASE_URL=https://mock.wireflow.test
export MOCK_LOG="$t/log"
fails=0
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }

head -c 5000000 /dev/zero > "$t/big.mp4"
head -c 1000 /dev/zero > "$t/small.png"

: > "$t/log"; export MOCK_BYTES=5000000
out=$(bash "$wf" upload "$t/big.mp4" 2>"$t/err"); rc=$?
[ "$rc" = 0 ] && [ "$out" = "https://cdn.test/big.mp4" ] && pass "big file prints the CDN url" || fail "big file: rc=$rc out='$out' $(cat "$t/err")"
grep -q '^POST https://mock.wireflow.test/media/upload-url ' "$t/log" && pass "big file mints via /media/upload-url" || fail "no upload-url call"
grep -q '^PUT https://storage.test/put?sig=1 ' "$t/log" && pass "big file PUTs to the presigned url" || fail "no PUT"
grep -q '^POST https://mock.wireflow.test/media/upload-url/complete ' "$t/log" && pass "big file finalizes" || fail "no complete call"
grep -q '^POST https://mock.wireflow.test/media/upload ' "$t/log" && fail "big file hit the inline door" || pass "big file never hits the inline door"
grep '^PUT ' "$t/log" | grep -qi 'authorization' && fail "bearer token leaked to storage" || pass "PUT carries no Authorization"
grep '^PUT ' "$t/log" | grep -q '|Content-Type: video/mp4|Content-Length: 5000000' && pass "PUT sends the signed headers verbatim" || fail "signed headers missing: $(grep '^PUT ' "$t/log")"

: > "$t/log"
out=$(bash "$wf" upload "$t/small.png" 2>"$t/err"); rc=$?
[ "$rc" = 0 ] && [ "$out" = "https://cdn.test/small.png" ] && pass "small file prints the CDN url" || fail "small file: rc=$rc out='$out'"
[ "$(wc -l < "$t/log" | tr -d ' ')" = 1 ] && grep -q '^POST https://mock.wireflow.test/media/upload ' "$t/log" && pass "small file stays on the inline door" || fail "small file calls: $(cat "$t/log")"

: > "$t/log"; MOCK_MINT_FAIL=1 bash "$wf" upload "$t/big.mp4" >/dev/null 2>"$t/err"; rc=$?
[ "$rc" != 0 ] && grep -q 'step 1' "$t/err" && pass "mint failure exits non-zero naming step 1" || fail "mint failure: rc=$rc $(cat "$t/err")"
grep -q '^PUT ' "$t/log" && fail "PUT attempted after failed mint" || pass "no PUT after failed mint"

: > "$t/log"; MOCK_PUT_CODE=403 bash "$wf" upload "$t/big.mp4" >/dev/null 2>"$t/err"; rc=$?
[ "$rc" != 0 ] && grep -q 'step 2.*403' "$t/err" && pass "PUT failure exits non-zero naming step 2 and the status" || fail "PUT failure: rc=$rc $(cat "$t/err")"
grep -q 'upload-url/complete' "$t/log" && fail "finalize attempted after failed PUT" || pass "no finalize after failed PUT"

: > "$t/log"; MOCK_CURL_FAIL='/media/upload-url ' bash "$wf" upload "$t/big.mp4" >/dev/null 2>"$t/err"; rc=$?
[ "$rc" != 0 ] && grep -q 'step 1' "$t/err" && pass "mint network failure exits non-zero naming step 1" || fail "mint curl failure: rc=$rc $(cat "$t/err")"
grep -q '^PUT ' "$t/log" && fail "PUT after mint network failure" || pass "no PUT after mint network failure"

: > "$t/log"; MOCK_COMPLETE_FAIL=1 bash "$wf" upload "$t/big.mp4" >/dev/null 2>"$t/err"; rc=$?
[ "$rc" != 0 ] && grep -q 'step 3' "$t/err" && pass "complete HTTP error exits non-zero naming step 3" || fail "complete failure: rc=$rc $(cat "$t/err")"

head -c 4194304 /dev/zero > "$t/edge.png"; head -c 4194305 /dev/zero > "$t/over.png"
: > "$t/log"; export MOCK_BYTES=4194304; bash "$wf" upload "$t/edge.png" >/dev/null 2>&1
grep -q '/media/upload-url' "$t/log" && fail "exactly 4194304 bytes went presigned" || pass "4194304 bytes stays inline"
: > "$t/log"; export MOCK_BYTES=4194305; bash "$wf" upload "$t/over.png" >/dev/null 2>&1
grep -q '/media/upload-url' "$t/log" && pass "4194305 bytes goes presigned" || fail "4194305 bytes stayed inline"

cp "$t/big.mp4" "$t/clip.MP4"
: > "$t/log"; export MOCK_BYTES=5000000; bash "$wf" upload "$t/clip.MP4" >/dev/null 2>&1
mint_sent=$(grep -c '^POST .*/media/upload-url ' "$t/log")
[ "$mint_sent" = 1 ] && grep '^POST .*/media/upload-url ' "$t/log" | grep -q 'video/mp4' && pass "uppercase extension maps to video/mp4" || fail "uppercase ext not mapped: $(cat "$t/log")"

[ "$fails" -eq 0 ] && echo "ALL PASS" || echo "$fails FAILED" >&2
exit "$fails"
