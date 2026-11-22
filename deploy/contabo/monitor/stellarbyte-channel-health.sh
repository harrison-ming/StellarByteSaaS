#!/usr/bin/env bash
# StellarByte channel / publishing health check (docs/DEPLOYMENT.md 12.3).
# Exits non-zero, so notify-command-status.sh posts to Discord #errors once (and
# again on recovery), when any of these holds:
#   1. a live channel needs a reconnect (refreshNeeded / stuck inBetweenSteps)
#   2. a live channel's token expires within STELLARBYTE_TOKEN_WARN_DAYS and it has
#      no refresh token (so it cannot renew itself, e.g. personal LinkedIn)
#   3. a post went to ERROR within the last STELLARBYTE_ERROR_WINDOW_HOURS
#   4. a queued post is overdue by more than STELLARBYTE_OVERDUE_MINUTES
# Read-only: SELECTs only, over the Postgres container's local socket. Prints names
# and ids, never token values.
set -euo pipefail

DB_CONTAINER="${STELLARBYTE_DB_CONTAINER:-stellarbyte-postgres}"
DB_USER="${STELLARBYTE_DB_USER:-postgres}"
DB_NAME="${STELLARBYTE_DB_NAME:-stellarbyte}"
WARN_DAYS="${STELLARBYTE_TOKEN_WARN_DAYS:-14}"
ERROR_HOURS="${STELLARBYTE_ERROR_WINDOW_HOURS:-26}"
OVERDUE_MINUTES="${STELLARBYTE_OVERDUE_MINUTES:-30}"

for v in "$WARN_DAYS" "$ERROR_HOURS" "$OVERDUE_MINUTES"; do
  [[ "$v" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: thresholds must be positive integers" >&2; exit 2; }
done

q() {
  docker exec -i "$DB_CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -At -F ' | '
}

problems=0
report() {
  local title="$1" rows="$2"
  if [[ -n "$rows" ]]; then
    problems=$((problems + 1))
    printf '%s:\n' "$title"
    sed 's/^/  /' <<<"$rows"
  fi
}

reconnect="$(q <<'SQL'
SELECT i."providerIdentifier", i.name, i.id,
       CASE WHEN i."refreshNeeded" THEN 'refreshNeeded' ELSE 'inBetweenSteps' END
FROM "Integration" i
WHERE i."deletedAt" IS NULL AND i.disabled = false
  AND (i."refreshNeeded" = true OR i."inBetweenSteps" = true)
ORDER BY 1, 2;
SQL
)"
report "channels needing a reconnect" "$reconnect"

expiring="$(q <<SQL
SELECT i."providerIdentifier", i.name, i.id, to_char(i."tokenExpiration", 'YYYY-MM-DD')
FROM "Integration" i
WHERE i."deletedAt" IS NULL AND i.disabled = false
  AND i."tokenExpiration" IS NOT NULL
  AND i."tokenExpiration" < now() + interval '${WARN_DAYS} days'
  AND coalesce(i."refreshToken", '') = ''
ORDER BY 4;
SQL
)"
report "tokens expiring within ${WARN_DAYS} days without a refresh token (reconnect manually)" "$expiring"

failed="$(q <<SQL
SELECT i."providerIdentifier", i.name, p.id, to_char(p."updatedAt", 'YYYY-MM-DD HH24:MI'),
       left(regexp_replace(coalesce(p.error, ''), '\s+', ' ', 'g'), 160)
FROM "Post" p JOIN "Integration" i ON i.id = p."integrationId"
WHERE p."deletedAt" IS NULL AND p.state = 'ERROR'
  AND p."updatedAt" > now() - interval '${ERROR_HOURS} hours'
ORDER BY p."updatedAt" DESC;
SQL
)"
report "posts failed in the last ${ERROR_HOURS}h" "$failed"

overdue="$(q <<SQL
SELECT i."providerIdentifier", i.name, p.id, to_char(p."publishDate", 'YYYY-MM-DD HH24:MI')
FROM "Post" p JOIN "Integration" i ON i.id = p."integrationId"
WHERE p."deletedAt" IS NULL AND p.state = 'QUEUE' AND p."parentPostId" IS NULL
  AND p."publishDate" < now() - interval '${OVERDUE_MINUTES} minutes'
  AND p."publishDate" > now() - interval '7 days'
ORDER BY p."publishDate";
SQL
)"
report "queued posts overdue by more than ${OVERDUE_MINUTES} min" "$overdue"

if ((problems > 0)); then
  exit 1
fi
echo "channel health ok"
