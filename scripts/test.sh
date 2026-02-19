#!/usr/bin/env bash
set -euo pipefail

DOD_IMAGE="wolfi-ca-certificates-dod-unclass:latest-amd64"
NODOD_IMAGE="wolfi-base:latest-amd64"
DOD_TEST_URL="https://www.defensetravel.osd.mil/"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Test 1: DoD certs are present in the system trust store ==="
DOD_COUNT=$(docker run --rm "$DOD_IMAGE" sh -c 'grep -c "BEGIN CERTIFICATE" /etc/ssl/certs/ca-certificates.crt')
NODOD_COUNT=$(docker run --rm "$NODOD_IMAGE" sh -c 'grep -c "BEGIN CERTIFICATE" /etc/ssl/certs/ca-certificates.crt')
if [ "$DOD_COUNT" -gt "$NODOD_COUNT" ]; then
  pass "DoD image has $DOD_COUNT certs vs $NODOD_COUNT in baseline (delta: $((DOD_COUNT - NODOD_COUNT)))"
else
  fail "DoD image ($DOD_COUNT) should have more certs than baseline ($NODOD_COUNT)"
fi

echo ""
echo "=== Test 2: Individual DoD cert files are installed ==="
CERT_COUNT=$(docker run --rm "$DOD_IMAGE" sh -c 'ls /usr/share/ca-certificates/dod/*.crt | wc -l')
if [ "$CERT_COUNT" -gt 0 ]; then
  pass "$CERT_COUNT individual DoD certs installed in /usr/share/ca-certificates/dod/"
else
  fail "No DoD certs found in /usr/share/ca-certificates/dod/"
fi

echo ""
echo "=== Test 3: Standard HTTPS still works (google.com) ==="
if docker run --rm "$DOD_IMAGE" curl -s --max-time 10 -o /dev/null -w '%{http_code}' https://www.google.com | grep -q '200'; then
  pass "curl to google.com returned 200"
else
  fail "curl to google.com did not return 200"
fi

echo ""
echo "=== Test 4: DoD PKI site fails WITHOUT DoD certs ==="
NODOD_RESULT=$(docker run --rm "$NODOD_IMAGE" curl -sI --max-time 15 -o /dev/null -w '%{ssl_verify_result}' "$DOD_TEST_URL" 2>&1 || true)
if [ "$NODOD_RESULT" != "0" ]; then
  pass "Without DoD certs, SSL verify result = $NODOD_RESULT (expected non-zero)"
else
  fail "Without DoD certs, SSL verify unexpectedly succeeded"
fi

echo ""
echo "=== Test 5: DoD PKI site succeeds WITH DoD certs ==="
DOD_RESULT=$(docker run --rm "$DOD_IMAGE" curl -sI --max-time 15 -o /dev/null -w '%{ssl_verify_result}' "$DOD_TEST_URL" 2>&1)
if [ "$DOD_RESULT" = "0" ]; then
  pass "With DoD certs, SSL verify result = 0 (verified)"
else
  fail "With DoD certs, SSL verify result = $DOD_RESULT (expected 0)"
fi

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
