#!/usr/bin/env bash
# Viche V1 E2E curl validation — proves all 5 endpoints work together.
# Usage: VICHE=http://localhost:4000 ./scripts/e2e-curl-test.sh
set -euo pipefail

VICHE=${VICHE:-http://localhost:4000}

# ── colour helpers ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

pass()  { echo -e "${GREEN}  ✓ PASS${RESET}  $*"; }
fail()  { echo -e "${RED}  ✗ FAIL${RESET}  $*"; exit 1; }
step()  { echo -e "\n${CYAN}${BOLD}▶ $*${RESET}"; }
title() { echo -e "\n${BOLD}════════════════════════════════════════${RESET}"; echo -e "${BOLD}  Viche V1 E2E — $*${RESET}"; echo -e "${BOLD}════════════════════════════════════════${RESET}"; }

assert_contains() {
  local label="$1" value="$2" pattern="$3"
  if echo "$value" | grep -q "$pattern"; then
    pass "$label"
  else
    fail "$label — expected pattern '$pattern' in: $value"
  fi
}

assert_equals() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label — expected '$expected', got '$actual'"
  fi
}

assert_not_empty() {
  local label="$1" value="$2"
  if [ -n "$value" ] && [ "$value" != "null" ]; then
    pass "$label"
  else
    fail "$label — got empty/null value"
  fi
}

# ── 0. Wait for server ──────────────────────────────────────────────────────
title "Starting (target: $VICHE)"

step "0. Waiting for server to be ready…"
for i in $(seq 1 20); do
  if curl -sf "$VICHE/" >/dev/null 2>&1; then
    pass "Server is up (attempt $i)"
    break
  fi
  if [ "$i" -eq 20 ]; then
    fail "Server did not respond after 20 attempts. Is 'mix phx.server' running?"
  fi
  sleep 1
done

# ── 1. /.well-known/agent-registry ─────────────────────────────────────────
step "1. GET /.well-known/agent-registry"
WK=$(curl -sf "$VICHE/.well-known/agent-registry")
echo "  Response: $WK" | head -c 300; echo
assert_contains "well-known returns protocol field"  "$WK" '"protocol"'
assert_contains "well-known returns endpoints field" "$WK" '"endpoints"'
assert_contains "well-known returns quickstart"      "$WK" '"quickstart"'
assert_contains "well-known includes register path"  "$WK" '/registry/register'

# ── 2. Register two agents ──────────────────────────────────────────────────
step "2. Register agent-a (capabilities: testing)"
REG_A=$(curl -sf -X POST "$VICHE/registry/register" \
  -H 'Content-Type: application/json' \
  -d '{"name":"agent-a","capabilities":["testing"],"description":"E2E test agent A"}')
echo "  Response: $REG_A"
A=$(echo "$REG_A" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
assert_not_empty "agent-a gets an id"   "$A"
assert_contains  "agent-a inbox_url"    "$REG_A" '"inbox_url"'
assert_contains  "agent-a registered_at" "$REG_A" '"registered_at"'
echo "  agent-a id: $A"

step "2. Register agent-b (capabilities: coding)"
REG_B=$(curl -sf -X POST "$VICHE/registry/register" \
  -H 'Content-Type: application/json' \
  -d '{"name":"agent-b","capabilities":["coding"],"description":"E2E test agent B"}')
echo "  Response: $REG_B"
B=$(echo "$REG_B" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
assert_not_empty "agent-b gets an id"   "$B"
echo "  agent-b id: $B"

# ── 3. Discover by capability ───────────────────────────────────────────────
step "3. GET /registry/discover?capability=coding  (expect agent-b)"
DISC=$(curl -sf "$VICHE/registry/discover?capability=coding")
echo "  Response: $DISC"
assert_contains "discover returns agents array"         "$DISC" '"agents"'
assert_contains "discover finds agent-b by name"        "$DISC" 'agent-b'
assert_contains "discover returns coding capability"    "$DISC" '"coding"'

step "3b. Discover by name=agent-a (expect agent-a only)"
DISC_A=$(curl -sf "$VICHE/registry/discover?name=agent-a")
echo "  Response: $DISC_A"
assert_contains "discover by name finds agent-a"        "$DISC_A" 'agent-a'

step "3c. Discover missing capability → empty agents list"
DISC_EMPTY=$(curl -sf "$VICHE/registry/discover?capability=nonexistent-cap-xyz")
echo "  Response: $DISC_EMPTY"
assert_equals "no agents for unknown capability" "$DISC_EMPTY" '{"agents":[]}'

# ── 4. Send message A → B ───────────────────────────────────────────────────
step "4. POST /messages/$B  (A sends task to B)"
SEND=$(curl -sf -X POST "$VICHE/messages/$B" \
  -H 'Content-Type: application/json' \
  -d "{\"type\":\"task\",\"from\":\"$A\",\"body\":\"Implement a rate limiter. Repo: test/api-server.\",\"reply_to\":\"$A\"}")
echo "  Response: $SEND"
MSG_ID=$(echo "$SEND" | grep -o '"message_id":"[^"]*"' | head -1 | cut -d'"' -f4)
assert_not_empty "send returns message_id" "$MSG_ID"
echo "  message_id: $MSG_ID"

# ── 5. Read B's inbox (expect message from A) ───────────────────────────────
step "5. GET /inbox/$B  (B reads inbox — expect 1 message, auto-consumed)"
INBOX_B=$(curl -sf "$VICHE/inbox/$B")
echo "  Response: $INBOX_B"
assert_contains "inbox returns messages array"          "$INBOX_B" '"messages"'
assert_contains "inbox message has correct id"          "$INBOX_B" "$MSG_ID"
assert_contains "inbox message from is agent-a"         "$INBOX_B" "\"from\":\"$A\""
assert_contains "inbox message type is task"            "$INBOX_B" '"type":"task"'
assert_contains "inbox message has body"                "$INBOX_B" 'rate limiter'
assert_contains "inbox message has sent_at"             "$INBOX_B" '"sent_at"'

# ── 6. Read B's inbox again (expect empty — consumed) ───────────────────────
step "6. GET /inbox/$B  (second read — expect empty: Erlang receive semantics)"
INBOX_B2=$(curl -sf "$VICHE/inbox/$B")
echo "  Response: $INBOX_B2"
assert_equals "inbox is empty after consume" "$INBOX_B2" '{"messages":[]}'

# ── 7. B replies to A via POST /messages/{A} ────────────────────────────────
step "7. POST /messages/$A  (B sends result reply to A)"
REPLY=$(curl -sf -X POST "$VICHE/messages/$A" \
  -H 'Content-Type: application/json' \
  -d "{\"type\":\"result\",\"from\":\"$B\",\"body\":\"Rate limiter implemented. 3 files changed: +45 -2 across middleware/rateLimiter.js\"}")
echo "  Response: $REPLY"
REPLY_ID=$(echo "$REPLY" | grep -o '"message_id":"[^"]*"' | head -1 | cut -d'"' -f4)
assert_not_empty "reply returns message_id" "$REPLY_ID"

# ── 8. Read A's inbox (expect result from B) ────────────────────────────────
step "8. GET /inbox/$A  (A reads reply — expect result from B)"
INBOX_A=$(curl -sf "$VICHE/inbox/$A")
echo "  Response: $INBOX_A"
assert_contains "A inbox has result message"            "$INBOX_A" '"type":"result"'
assert_contains "A inbox result from is agent-b"        "$INBOX_A" "\"from\":\"$B\""
assert_contains "A inbox result has body"               "$INBOX_A" 'Rate limiter implemented'

# ── 9. Error cases ───────────────────────────────────────────────────────────
step "9. Error: GET /inbox/nonexistent-agent → 404"
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$VICHE/inbox/nonexistent-agent-xyz")
assert_equals "unknown agent inbox returns 404" "$STATUS" "404"

step "9b. Error: POST /messages/nonexistent-agent → 404"
STATUS2=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$VICHE/messages/nonexistent-agent-xyz" \
  -H 'Content-Type: application/json' \
  -d "{\"type\":\"ping\",\"from\":\"$A\",\"body\":\"hello\"}")
assert_equals "sending to unknown agent returns 404" "$STATUS2" "404"

step "9c. Error: POST /registry/register without capabilities → 422"
STATUS3=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$VICHE/registry/register" \
  -H 'Content-Type: application/json' \
  -d '{"name":"bad-agent"}')
assert_equals "register without capabilities returns 422" "$STATUS3" "422"

step "9d. Error: GET /registry/discover without params → 400"
STATUS4=$(curl -s -o /dev/null -w '%{http_code}' "$VICHE/registry/discover")
assert_equals "discover without params returns 400" "$STATUS4" "400"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  ALL CHECKS PASSED — V1 flow proven ✓  ${RESET}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo ""
echo "  Proven flow:"
echo "    register → discover → send → inbox (consume) → inbox (empty) → reply → inbox (reply)"
echo ""
