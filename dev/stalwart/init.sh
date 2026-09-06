#!/bin/sh
# Creates the test domain in a running Stalwart instance.
# Run once after: docker compose up -d
# Safe to run multiple times (idempotent).
#
# Usage: ./init.sh [base_url] [admin_user] [admin_pass] [domain]
# Defaults match dev/stalwart/.env

BASE="${1:-http://localhost:8090}"
ADMIN_USER="${2:-admin}"
ADMIN_PASS="${3:-changeme}"
DOMAIN="${4:-example.test}"

set -e

echo "Waiting for Stalwart at $BASE ..."
until curl -sf "$BASE/jmap/session" >/dev/null 2>&1; do
  printf '.'
  sleep 2
done
echo " ready."

# Get the admin account ID from the session
ADMIN_CREDS=$(printf '%s:%s' "$ADMIN_USER" "$ADMIN_PASS" | base64 | tr -d '\n')
SESSION=$(curl -sf -H "Authorization: Basic $ADMIN_CREDS" "$BASE/jmap/session")
ADMIN_ACCOUNT_ID=$(printf '%s' "$SESSION" | python3 -c "
import sys, json
s = json.load(sys.stdin)
caps = s.get('primaryAccounts', {})
# The admin account ID is the value for urn:stalwart:jmap capability
print(caps.get('urn:stalwart:jmap', ''))
")

if [ -z "$ADMIN_ACCOUNT_ID" ]; then
  echo "ERROR: Could not determine admin account ID from session" >&2
  echo "Session was: $SESSION" >&2
  exit 1
fi
echo "Admin account ID: $ADMIN_ACCOUNT_ID"

# Check if the domain already exists
QUERY_RESULT=$(curl -sf \
  -H "Authorization: Basic $ADMIN_CREDS" \
  -H "Content-Type: application/json" \
  -X POST "$BASE/jmap" \
  -d "{
    \"using\": [\"urn:stalwart:jmap\"],
    \"methodCalls\": [[\"x:Domain/query\", {
      \"accountId\": \"$ADMIN_ACCOUNT_ID\",
      \"filter\": {\"name\": \"$DOMAIN\"}
    }, \"c1\"]]
  }")

EXISTING_IDS=$(printf '%s' "$QUERY_RESULT" | python3 -c "
import sys, json
r = json.load(sys.stdin)
ids = r['methodResponses'][0][1].get('ids', [])
print(ids[0] if ids else '')
")

if [ -n "$EXISTING_IDS" ]; then
  echo "Domain $DOMAIN already exists (id=$EXISTING_IDS), nothing to do."
  exit 0
fi

# Create the domain
CREATE_RESULT=$(curl -sf \
  -H "Authorization: Basic $ADMIN_CREDS" \
  -H "Content-Type: application/json" \
  -X POST "$BASE/jmap" \
  -d "{
    \"using\": [\"urn:stalwart:jmap\"],
    \"methodCalls\": [[\"x:Domain/set\", {
      \"accountId\": \"$ADMIN_ACCOUNT_ID\",
      \"create\": {
        \"d1\": {\"name\": \"$DOMAIN\"}
      }
    }, \"c1\"]]
  }")

DOMAIN_ID=$(printf '%s' "$CREATE_RESULT" | python3 -c "
import sys, json
r = json.load(sys.stdin)
resp = r['methodResponses'][0][1]
created = resp.get('created', {})
if 'd1' in created:
    print(created['d1']['id'])
else:
    notCreated = resp.get('notCreated', {})
    print('ERROR: ' + str(notCreated), file=sys.stderr)
    sys.exit(1)
")

echo "Domain $DOMAIN created (id=$DOMAIN_ID)"
