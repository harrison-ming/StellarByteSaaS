#!/usr/bin/env bash
# StellarByte Postgres backup (docs/redeploy-spec.md 5.5). Modeled on the Contabo
# /usr/local/sbin/listmonk-backup.sh family (dump -> verify -> sha256 + manifest ->
# atomic publish -> optional private R2 copy with read-back -> prune), merged into
# one script with subcommands.
#
#   stellarbyte-backup.sh backup [--prune]     dump every database, verify, offsite copy
#   stellarbyte-backup.sh verify FILE.dump     catalog + checksum + manifest + modes
#   stellarbyte-backup.sh watchdog [--local-only]
#                                              newest set is fresh, valid, and in R2
#   stellarbyte-backup.sh restore-drill FILE.dump
#                                              restore into a throwaway database inside
#                                              the running Postgres container and compare
#                                              per-table row counts with the dump's source
#   stellarbyte-backup.sh --dry-run backup     print what would happen
#
# No database password is accepted: pg_dump / pg_restore run inside the Postgres
# container over its local socket. pg_restore also runs inside the container, so the
# host does not need a PostgreSQL 17 client (Contabo host pg_restore is older).
#
# Environment (defaults are the Contabo values):
#   STELLARBYTE_BACKUP_DIR            /opt/stellarpostiz/backups
#   STELLARBYTE_BACKUP_RETENTION_DAYS 14
#   STELLARBYTE_DB_CONTAINER          stellarbyte-postgres
#   STELLARBYTE_DB_USER               postgres
#   STELLARBYTE_DATABASES             "stellarbyte temporal temporal_visibility"
#   STELLARBYTE_BACKUP_MAX_AGE_MINUTES 1560 (watchdog freshness, 26h)
#   STELLARBYTE_R2_CONFIG_FILE        unset = no offsite copy (backup) / required (watchdog)
#       file mode 600 with R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT, R2_BUCKET
#   STELLARBYTE_R2_PREFIX             stellarbyte
#   DOCKER_BIN / AWS_BIN              docker / aws
set -euo pipefail

BACKUP_DIR="${STELLARBYTE_BACKUP_DIR:-/opt/stellarpostiz/backups}"
RETENTION_DAYS="${STELLARBYTE_BACKUP_RETENTION_DAYS:-14}"
DB_CONTAINER="${STELLARBYTE_DB_CONTAINER:-stellarbyte-postgres}"
DB_USER="${STELLARBYTE_DB_USER:-postgres}"
DATABASES="${STELLARBYTE_DATABASES:-stellarbyte temporal temporal_visibility}"
MAX_AGE_MINUTES="${STELLARBYTE_BACKUP_MAX_AGE_MINUTES:-1560}"
R2_CONFIG_FILE="${STELLARBYTE_R2_CONFIG_FILE:-}"
R2_PREFIX="${STELLARBYTE_R2_PREFIX:-stellarbyte}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
AWS_BIN="${AWS_BIN:-aws}"

DRY_RUN=false
TEMP_FILES=()
DRILL_DB=""
umask 077

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  local path
  for path in "${TEMP_FILES[@]:-}"; do
    [[ -n "$path" && -f "$path" ]] && rm -f -- "$path"
  done
  if [[ -n "$DRILL_DB" ]]; then
    "$DOCKER_BIN" exec "$DB_CONTAINER" dropdb -U "$DB_USER" --if-exists "$DRILL_DB" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT HUP INT TERM

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

require_command() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

stat_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then stat -c '%a' "$1"; else stat -f '%Lp' "$1"; fi
}

# Tables that must be present in each database's dump (catalog sanity check).
required_tables() {
  case "$1" in
    stellarbyte) echo 'User Organization UserOrganization Integration Post Media' ;;
    temporal) echo 'executions current_executions namespaces schema_version' ;;
    temporal_visibility) echo 'executions_visibility schema_version' ;;
    *) echo '' ;;
  esac
}

db_of() {
  # stellarbyte-<db>-YYYYMMDDTHHMMSSZ.dump -> <db>
  local base
  base="$(basename "$1")"
  [[ "$base" =~ ^stellarbyte-([a-z_]+)-20[0-9]{6}T[0-9]{6}Z\.dump$ ]] || die "unexpected backup name: $base"
  printf '%s' "${BASH_REMATCH[1]}"
}

pg_restore_in_container() {
  "$DOCKER_BIN" exec -i "$DB_CONTAINER" pg_restore "$@"
}

verify_catalog() {
  local file="$1" db="$2" catalog table
  [[ -s "$file" ]] || die "backup is empty: $file"
  catalog="$(pg_restore_in_container --list <"$file")"
  [[ -n "$catalog" ]] || die "pg_restore returned an empty catalog: $file"
  pg_restore_in_container --file=/dev/null <"$file"
  for table in $(required_tables "$db"); do
    grep -Eq "TABLE( DATA)? public \"?${table}\"?([[:space:]]|$)" <<<"$catalog" \
      || die "backup catalog of $db is missing public.$table"
  done
}

verify_checksum() {
  local file="$1" expected actual
  [[ -f "${file}.sha256" ]] || die "checksum file is missing: ${file}.sha256"
  expected="$(awk 'NR == 1 {print tolower($1)}' "${file}.sha256")"
  [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || die "checksum file is malformed"
  actual="$(sha256_file "$file" | tr '[:upper:]' '[:lower:]')"
  [[ "$actual" == "$expected" ]] || die "checksum mismatch: $file"
}

verify_manifest() {
  local file="$1" name sum
  name="$(basename "$file")"
  [[ -f "${file}.manifest" ]] || die "manifest is missing: ${file}.manifest"
  grep -Fxq 'format=postgresql-custom' "${file}.manifest" || die "manifest format is invalid"
  grep -Fxq "file=$name" "${file}.manifest" || die "manifest filename does not match"
  sum="$(awk -F= '$1 == "sha256" {print $2}' "${file}.manifest")"
  [[ "$sum" =~ ^[a-fA-F0-9]{64}$ ]] || die "manifest checksum is malformed"
  grep -Fiqx "${sum}  ${name}" "${file}.sha256" || die "manifest and checksum file do not match"
}

verify_permissions() {
  local file="$1" dir artifact mode
  dir="$(dirname "$file")"
  mode="$(stat_mode "$dir")"
  [[ "$mode" == "700" ]] || die "backup directory mode is $mode, expected 700"
  for artifact in "$file" "${file}.sha256" "${file}.manifest"; do
    mode="$(stat_mode "$artifact")"
    [[ "$mode" == "600" ]] || die "artifact mode is $mode, expected 600: $artifact"
  done
}

verify_existing() {
  local file="$1" db
  [[ -f "$file" ]] || die "backup does not exist: $file"
  db="$(db_of "$file")"
  verify_catalog "$file" "$db"
  verify_checksum "$file"
  verify_manifest "$file"
  verify_permissions "$file"
  log "verified backup: $file"
}

load_r2_config() {
  [[ "$R2_CONFIG_FILE" == /* && -f "$R2_CONFIG_FILE" && ! -L "$R2_CONFIG_FILE" ]] \
    || die "R2 config must be an absolute, regular, non-symlink file"
  [[ "$(stat_mode "$R2_CONFIG_FILE")" == "600" ]] || die "R2 config mode must be 600"
  set -a
  # shellcheck disable=SC1090
  source "$R2_CONFIG_FILE"
  set +a
  : "${R2_ACCESS_KEY_ID:?missing R2_ACCESS_KEY_ID}"
  : "${R2_SECRET_ACCESS_KEY:?missing R2_SECRET_ACCESS_KEY}"
  : "${R2_ENDPOINT:?missing R2_ENDPOINT}"
  : "${R2_BUCKET:?missing R2_BUCKET}"
  export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
  export AWS_DEFAULT_REGION=auto
  require_command "$AWS_BIN"
}

# Read back the remote copy and compare checksum + manifest + full-object hash.
r2_check() {
  local name="$1" expected="$2" remote size line manifest actual
  remote="s3://${R2_BUCKET}/${R2_PREFIX}/${name}"
  size="$("$AWS_BIN" s3api head-object --bucket "$R2_BUCKET" --key "${R2_PREFIX}/${name}" \
    --endpoint-url "$R2_ENDPOINT" --query ContentLength --output text)"
  [[ "$size" =~ ^[1-9][0-9]*$ ]] || die "remote dump is missing or empty: $name"
  line="$("$AWS_BIN" s3 cp "${remote}.sha256" - --endpoint-url "$R2_ENDPOINT" --only-show-errors)"
  [[ "$line" == "${expected}  ${name}" ]] || die "remote checksum artifact does not match: $name"
  manifest="$("$AWS_BIN" s3 cp "${remote}.manifest" - --endpoint-url "$R2_ENDPOINT" --only-show-errors)"
  grep -Fxq "file=${name}" <<<"$manifest" || die "remote manifest filename does not match: $name"
  grep -Fxq "sha256=${expected}" <<<"$manifest" || die "remote manifest checksum does not match: $name"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$("$AWS_BIN" s3 cp "$remote" - --endpoint-url "$R2_ENDPOINT" --only-show-errors | sha256sum | awk '{print $1}')"
  else
    actual="$("$AWS_BIN" s3 cp "$remote" - --endpoint-url "$R2_ENDPOINT" --only-show-errors | shasum -a 256 | awk '{print $1}')"
  fi
  [[ "$actual" == "$expected" ]] || die "remote dump checksum mismatch: $name"
  log "private R2 checksum verified: $name ($size bytes)"
}

r2_copy() {
  local file="$1" artifact
  for artifact in "$file" "${file}.sha256" "${file}.manifest"; do
    [[ -f "$artifact" && ! -L "$artifact" && -s "$artifact" ]] || die "bad artifact: $artifact"
    "$AWS_BIN" s3 cp "$artifact" "s3://${R2_BUCKET}/${R2_PREFIX}/$(basename "$artifact")" \
      --endpoint-url "$R2_ENDPOINT" --only-show-errors
  done
  r2_check "$(basename "$file")" "$(awk 'NR == 1 {print $1}' "${file}.sha256")"
}

prepare_dir() {
  [[ ! -L "$BACKUP_DIR" ]] || die "backup directory must not be a symlink"
  install -d -m 0700 "$BACKUP_DIR"
  chmod 0700 "$BACKUP_DIR"
}

dump_one() {
  local db="$1" ts="$2" base final tmp sum bytes
  base="stellarbyte-${db}-${ts}.dump"
  final="$BACKUP_DIR/$base"
  tmp="$BACKUP_DIR/.${base}.part.$$"
  TEMP_FILES+=("$tmp" "$tmp.sha256" "$tmp.manifest")
  [[ ! -e "$final" ]] || die "refusing to overwrite existing backup: $final"

  "$DOCKER_BIN" exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -d "$db" -Fc --no-owner --no-privileges >"$tmp"
  chmod 0600 "$tmp"
  verify_catalog "$tmp" "$db"

  sum="$(sha256_file "$tmp")"
  bytes="$(wc -c <"$tmp" | tr -d '[:space:]')"
  printf '%s  %s\n' "$sum" "$base" >"$tmp.sha256"
  printf 'format=postgresql-custom\ndatabase=%s\ncreated_at_utc=%s\nfile=%s\nbytes=%s\nsha256=%s\n' \
    "$db" "$ts" "$base" "$bytes" "$sum" >"$tmp.manifest"
  chmod 0600 "$tmp.sha256" "$tmp.manifest"
  mv -- "$tmp.sha256" "$final.sha256"
  mv -- "$tmp.manifest" "$final.manifest"
  mv -- "$tmp" "$final"
  verify_permissions "$final"
  verify_checksum "$final"
  verify_manifest "$final"
  log "dumped $db -> $final ($bytes bytes)"
  [[ -z "$R2_CONFIG_FILE" ]] || r2_copy "$final"
}

prune_backups() {
  local path minutes=$((RETENTION_DAYS * 1440))
  while IFS= read -r -d '' path; do
    log "pruning expired backup artifact: $path"
    rm -f -- "$path"
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f \
    \( -name 'stellarbyte-*-20??????T??????Z.dump' -o -name 'stellarbyte-*-20??????T??????Z.dump.sha256' \
       -o -name 'stellarbyte-*-20??????T??????Z.dump.manifest' \) -mmin "+$minutes" -print0)
}

cmd_backup() {
  local prune=false ts db
  while (($# > 0)); do
    case "$1" in --prune) prune=true; shift ;; *) die "unknown backup argument: $1" ;; esac
  done
  [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || die "retention must be a non-negative integer"
  if [[ "$DRY_RUN" == true ]]; then
    log "dry-run: would pg_dump -Fc [$DATABASES] from $DB_CONTAINER into $BACKUP_DIR"
    log "dry-run: would verify catalog, sha256, manifest, modes 0700/0600"
    [[ -z "$R2_CONFIG_FILE" ]] || log "dry-run: would copy to s3://<bucket>/$R2_PREFIX/ and read back"
    [[ "$prune" == false ]] || log "dry-run: would prune artifacts older than $RETENTION_DAYS days"
    return 0
  fi
  require_command "$DOCKER_BIN"; require_command install; require_command find
  [[ -z "$R2_CONFIG_FILE" ]] || load_r2_config
  prepare_dir
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  for db in $DATABASES; do dump_one "$db" "$ts"; done
  [[ "$prune" == false ]] || prune_backups
  log "backup complete: $BACKUP_DIR (set $ts)"
}

cmd_watchdog() {
  local local_only=false db latest candidate
  while (($# > 0)); do
    case "$1" in --local-only) local_only=true; shift ;; *) die "unknown watchdog argument: $1" ;; esac
  done
  [[ "$MAX_AGE_MINUTES" =~ ^[1-9][0-9]*$ ]] || die "max age must be a positive integer"
  if [[ "$DRY_RUN" == true ]]; then
    log "dry-run: would require a verified backup newer than $MAX_AGE_MINUTES minutes for each of [$DATABASES]"
    return 0
  fi
  [[ -d "$BACKUP_DIR" && ! -L "$BACKUP_DIR" ]] || die "backup directory is missing or is a symlink"
  [[ "$local_only" == true ]] || { [[ -n "$R2_CONFIG_FILE" ]] || die "watchdog needs STELLARBYTE_R2_CONFIG_FILE (or --local-only)"; load_r2_config; }
  for db in $DATABASES; do
    latest=""
    while IFS= read -r -d '' candidate; do
      if [[ -z "$latest" || "$candidate" -nt "$latest" ]]; then latest="$candidate"; fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "stellarbyte-${db}-20??????T??????Z.dump" \
      -mmin "-$MAX_AGE_MINUTES" -print0)
    [[ -n "$latest" ]] || die "no fresh backup for database $db"
    verify_existing "$latest" >/dev/null
    [[ "$local_only" == true ]] || r2_check "$(basename "$latest")" "$(awk 'NR == 1 {print $1}' "${latest}.sha256")" >/dev/null
    log "backup watchdog healthy: $(basename "$latest")"
  done
}

# Row counts of every user table, exact (count(*)), as "schema.table|n" lines.
count_rows() {
  local db="$1"
  "$DOCKER_BIN" exec -i "$DB_CONTAINER" psql -X -q -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$db" -At <<'SQL'
SELECT schemaname || '.' || tablename || '|' ||
       (xpath('/row/n/text()', query_to_xml(
          format('SELECT count(*) AS n FROM %I.%I', schemaname, tablename), false, true, '')))[1]::text
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema') AND schemaname NOT LIKE 'pg_temp%'
ORDER BY 1;
SQL
}

cmd_restore_drill() {
  local file="${1:-}" db src_counts dst_counts
  [[ -n "$file" ]] || die "restore-drill needs a backup file"
  db="$(db_of "$file")"
  verify_checksum "$file"
  verify_catalog "$file" "$db"
  if [[ "$DRY_RUN" == true ]]; then
    log "dry-run: would restore $file into a temporary database in $DB_CONTAINER and compare row counts with $db"
    return 0
  fi
  DRILL_DB="restore_drill_${db}_$$"
  "$DOCKER_BIN" exec "$DB_CONTAINER" createdb -U "$DB_USER" "$DRILL_DB"
  pg_restore_in_container -U "$DB_USER" -d "$DRILL_DB" --no-owner --no-privileges --exit-on-error <"$file"
  dst_counts="$(count_rows "$DRILL_DB")"
  src_counts="$(count_rows "$db")"
  log "restore drill counts ($db, restored | live):"
  join -t '|' -a1 -a2 -e MISSING -o 0,1.2,2.2 <(sort <<<"$dst_counts") <(sort <<<"$src_counts") \
    | awk -F'|' '{printf "  %-50s %10s %10s%s\n", $1, $2, $3, ($2==$3 ? "" : "  <- differs")}'
  if [[ "$dst_counts" != "$src_counts" ]]; then
    log "NOTE: counts differ from the live database (expected if it changed after the dump)"
    return 3
  fi
  log "restore drill complete: $db restored into $DRILL_DB, all table counts match, temp database dropped"
}

(($# > 0)) || { usage; exit 2; }
if [[ "$1" == --dry-run ]]; then DRY_RUN=true; shift; fi
(($# > 0)) || { usage; exit 2; }
sub="$1"; shift
case "$sub" in
  backup) cmd_backup "$@" ;;
  verify) (($# == 1)) || die "verify needs exactly one file"; verify_existing "$1" ;;
  watchdog) cmd_watchdog "$@" ;;
  restore-drill) cmd_restore_drill "$@" ;;
  -h|--help|help) usage ;;
  *) die "unknown subcommand: $sub" ;;
esac
