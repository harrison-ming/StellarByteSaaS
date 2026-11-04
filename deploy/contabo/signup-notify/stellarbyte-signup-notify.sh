#!/usr/bin/env bash
# StellarByte new-registration notifier (docs/redeploy-spec.md D23).
# Host-side, no app code: every run reads (read-only transaction) the users created after the
# stored watermark from the stellarbyte database and posts one Discord message per user to
# #stellarbyte-signups via a channel webhook. Installed as /usr/local/sbin/stellarbyte-signup-notify.sh,
# driven by stellarbyte-signup-notify.timer (every 5 min) through notify-command-status.sh,
# so a failing run alerts #errors once (and once on recovery).
#
#   run                 post users newer than the watermark, then advance it (first run: start at now)
#   init [<ISO-UTC>]    set the watermark to the given time (default now) without posting
#   status              print the watermark and how many users are pending (no posting)
#
# Env: STELLARBYTE_SIGNUP_ENV_FILE (default /root/.config/stellarbyte/signup-notify.env, root 600,
#      one line DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...),
#      STELLARBYTE_SIGNUP_STATE_DIR (default /var/lib/stellarbyte-signup-notify),
#      STELLARBYTE_PG_CONTAINER (default stellarbyte-postgres).
set -euo pipefail

ENV_FILE="${STELLARBYTE_SIGNUP_ENV_FILE:-/root/.config/stellarbyte/signup-notify.env}"
STATE_DIR="${STELLARBYTE_SIGNUP_STATE_DIR:-/var/lib/stellarbyte-signup-notify}"
PG_CONTAINER="${STELLARBYTE_PG_CONTAINER:-stellarbyte-postgres}"
MARK="$STATE_DIR/watermark"
# watermark line: "<createdAt as YYYY-MM-DD HH:MM:SS.ffffff> <user id>"
MARK_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})? [A-Za-z0-9-]*$'

die() { echo "stellarbyte-signup-notify: $*" >&2; exit 1; }

psql_ro() {
  # default_transaction_read_only: this script can never write to the app database.
  docker exec -e PGOPTIONS='-c default_transaction_read_only=on' "$PG_CONTAINER" \
    psql -U postgres -d stellarbyte -v ON_ERROR_STOP=1 -qAt -c "$1"
}

load_webhook() {
  [ -f "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ] || die "missing env file $ENV_FILE"
  [ "$(stat -c %a "$ENV_FILE")" = 600 ] || die "$ENV_FILE must be mode 600"
  WEBHOOK_URL="$(sed -n 's/^DISCORD_WEBHOOK_URL=//p' "$ENV_FILE" | tr -d '"'"'" | head -n1)"
  case "$WEBHOOK_URL" in
    https://discord.com/api/webhooks/*) ;;
    *) die "DISCORD_WEBHOOK_URL missing or not a discord webhook" ;;
  esac
}

read_mark() {
  [ -f "$MARK" ] || return 1
  MARK_LINE="$(head -n1 "$MARK")"
  [[ "$MARK_LINE" =~ $MARK_RE ]] || die "corrupt watermark in $MARK"
  MARK_TS="${MARK_LINE% *}"
  MARK_ID="${MARK_LINE##* }"
}

write_mark() {
  install -d -m 0700 "$STATE_DIR"
  printf '%s %s\n' "$1" "$2" > "$MARK.tmp" && mv "$MARK.tmp" "$MARK"
}

# One row per new user, as compact JSON (user-controlled text never touches the shell parser;
# email / org are cut to 200 chars so a hostile signup cannot exceed Discord's 2000-char limit).
pending_sql() {
  cat <<SQL
SELECT json_build_object(
  'ts', to_char(u."createdAt", 'YYYY-MM-DD HH24:MI:SS.US'),
  'id', u.id,
  'email', u.email,
  'provider', u."providerName",
  'activated', u.activated,
  'org', (SELECT o.name FROM "UserOrganization" uo JOIN "Organization" o ON o.id = uo."organizationId"
          WHERE uo."userId" = u.id ORDER BY uo."createdAt" LIMIT 1)
)
FROM "User" u
WHERE (u."createdAt", u.id) > ('$MARK_TS'::timestamp, '$MARK_ID')
ORDER BY u."createdAt", u.id
LIMIT 50;
SQL
}

post() {
  local row="$1" payload code
  payload="$(jq -c '{
      content: ("**New StellarByte signup** (app.stellarbyte.ca)\n"
        + "Time: " + (.ts | sub("\\.[0-9]+$"; "")) + " UTC\n"
        + "Email: " + (.email[0:200]) + "\n"
        + "Organization: " + ((.org // "(none)")[0:200]) + "\n"
        + "Provider: " + .provider
        + (if .provider == "LOCAL" and (.activated | not) then " (awaiting email activation)" else "" end)),
      allowed_mentions: { parse: [] }
    }' <<<"$row")"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -H 'Content-Type: application/json' \
    --data "$payload" "$WEBHOOK_URL")" || return 1
  [ "$code" = 204 ] || [ "$code" = 200 ] || { echo "discord returned HTTP $code" >&2; return 1; }
}

cmd="${1:-run}"
case "$cmd" in
  init)
    ts="${2:-$(date -u '+%Y-%m-%d %H:%M:%S')}"
    [[ "$ts " =~ $MARK_RE ]] || die "init: expected 'YYYY-MM-DD HH:MM:SS' (UTC), got '$ts'"
    write_mark "$ts" ""
    read_mark
    echo "watermark set to $MARK_TS UTC"
    ;;
  status)
    if read_mark; then
      echo "watermark: $MARK_TS UTC ${MARK_ID:+(user $MARK_ID)}"
      echo "pending: $(psql_ro "$(pending_sql)" | grep -c . || true)"
    else
      echo "watermark: none (next run initialises it to now)"
    fi
    ;;
  run)
    load_webhook
    if ! read_mark; then
      write_mark "$(date -u '+%Y-%m-%d %H:%M:%S')" ""
      echo "watermark initialised to now; nothing posted"
      exit 0
    fi
    rows="$(psql_ro "$(pending_sql)")"
    n=0
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      post "$row" || die "posting failed after $n message(s); watermark kept at the last posted user"
      write_mark "$(jq -r .ts <<<"$row")" "$(jq -r .id <<<"$row")"
      n=$((n + 1))
      sleep 1   # Discord: 5 messages / 5 s per channel
    done <<<"$rows"
    echo "posted $n signup notification(s)"
    ;;
  *) die "usage: $0 run|init [<YYYY-MM-DD HH:MM:SS>]|status" ;;
esac
