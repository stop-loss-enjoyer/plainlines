#!/usr/bin/env bash
# Required Notice: Copyright 2026 stop-loss-enjoyer
# Plainlines is source-available under the PolyForm Shield License 1.0.0.
#
# Runs audit.sh on every fixture and asserts the expected result. Exit 1 on any mismatch.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$HERE/../../audit.sh"
fails=0; total=0
# Fixtures that need the transitive check use a fake Include tree (works without MetaEditor copy).
export AUDIT_INCLUDE_DIR="$HERE/fake-include"

check_pass() { # label, env prefix handled by caller via export
  local label="$1"; shift
  total=$((total+1))
  if out=$("$AUDIT" "$@" 2>&1); then echo "ok   pass: $label"; else echo "FAIL pass: $label unexpectedly failed:"; echo "$out" | sed 's/^/       /'; fails=$((fails+1)); fi
}
for f in "$HERE"/pass/*.mq5; do check_pass "${f#$HERE/}" "$f"; done
# clean fixture against the real Include copy too (transitive check on the stock library), if present
REAL="$HOME/.local/share/plainlines-build/MQL5/Include"
if [[ -d "$REAL" ]]; then AUDIT_INCLUDE_DIR="$REAL" check_pass "pass/clean.mq5 against real Include" "$HERE/pass/clean.mq5"; else echo "skip real Include (not installed)"; fi
# the SendOrderSafe exception: allowed only at the configured path
AUDIT_SEND_ORDER_FILE="tests/audit/pass-send/src/Trade/SendOrderSafe.mqh" check_pass "pass-send (OrderSend in the allowed file)" "$HERE/pass-send"
# the same file at the wrong path must fail
total=$((total+1))
if out=$("$AUDIT" "$HERE/pass-send" 2>&1); then echo "FAIL pass-send outside the configured path was accepted"; fails=$((fails+1)); else echo "ok   fail: pass-send at wrong path rejected"; fi

# the ACCOUNT_LOGIN exception: allowed only in the configured file
AUDIT_ACCOUNT_FILE="tests/audit/pass-account/src/Terminal/Account.mqh" check_pass "pass-account (ACCOUNT_LOGIN in the allowed file)" "$HERE/pass-account"
total=$((total+1))
if out=$("$AUDIT" "$HERE/pass-account" 2>&1); then echo "FAIL pass-account outside the configured path was accepted"; fails=$((fails+1)); else echo "ok   fail: pass-account at wrong path rejected"; fi


for f in "$HERE"/fail/*.mq5; do
  total=$((total+1)); name="$(basename "$f")"
  expect="$(sed -n '1s|^// expect: ||p' "$f")"
  out=$("$AUDIT" "$f" 2>&1); rc=$?
  if [[ $rc -eq 0 ]]; then echo "FAIL fail/$name: audit passed, expected failure"; fails=$((fails+1))
  elif ! grep -qF -- "$expect" <<<"$out"; then echo "FAIL fail/$name: rejected, but message lacks '$expect':"; echo "$out" | sed 's/^/       /'; fails=$((fails+1))
  else echo "ok   fail: $name ($expect)"; fi
done
echo "tests/audit: $((total-fails))/$total passed"
[[ $fails -eq 0 ]]
